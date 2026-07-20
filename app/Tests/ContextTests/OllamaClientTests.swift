import Foundation
import Testing

@testable import Context

@Suite("Ollama client", .serialized)
struct OllamaClientTests {
    @Test func listsModelsFromHTTPResponse() async throws {
        let (client, session) = makeClient { request in
            #expect(request.url?.path == "/api/tags")
            return response(
                for: request,
                statusCode: 200,
                body: #"{"models":[{"name":"gemma","size":123}]}"#)
        }
        defer { session.invalidateAndCancel() }

        #expect(
            try await client.listModels()
                == [ModelInfo(name: "gemma", sizeBytes: 123)])
    }

    @Test func rejectsNonSuccessfulHTTPResponse() async {
        let (client, session) = makeClient { request in
            response(for: request, statusCode: 503, body: "unavailable")
        }
        defer { session.invalidateAndCancel() }

        await #expect(throws: OllamaError.self) {
            try await client.listModels()
        }
    }

    @Test func streamsEventsFromHTTPResponse() async throws {
        let (client, session) = makeClient { request in
            #expect(request.url?.path == "/api/chat")
            return response(
                for: request,
                statusCode: 200,
                body: """
                    {"message":{"content":"","thinking":"reason"},"done":false}
                    {"message":{"content":"answer","thinking":""},"done":true}

                    """)
        }
        defer { session.invalidateAndCancel() }

        var events: [ChatStreamEvent] = []
        for try await event in client.streamChat(
            model: "model", history: [], options: .modelDefaults)
        {
            events.append(event)
        }
        #expect(events == [.thinking("reason"), .content("answer")])
    }

    @Test func omitsModelDefaultsFromRequest() throws {
        let client = OllamaClient()
        let request = try client.makeChatRequest(
            model: "model", history: [], options: .modelDefaults)
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["options"] == nil)
        #expect(json["think"] == nil)
        #expect(json["stream"] as? Bool == true)
    }

    @Test func appDefaultsSerializeTheContextCap() throws {
        let client = OllamaClient()
        let request = try client.makeChatRequest(
            model: "model", history: [], options: .appDefaults)
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any])
        let runtime = try #require(json["options"] as? [String: Any])

        #expect(runtime["num_ctx"] as? Int == 4096)
    }

    @Test func serializesRuntimeOverridesAndThinkingLevel() throws {
        let client = OllamaClient()
        let options = GenerationOptions(
            thinking: .high,
            temperature: 0.25,
            stop: ["END"],
            topK: 20)
        let request = try client.makeChatRequest(model: "model", history: [], options: options)
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any])
        let runtime = try #require(json["options"] as? [String: Any])

        #expect(json["think"] as? String == "high")
        #expect(runtime["temperature"] as? Double == 0.25)
        #expect(runtime["top_k"] as? Int == 20)
        #expect(runtime["stop"] as? [String] == ["END"])
    }

    @Test func separatesThinkingAndAnswerChunks() throws {
        let client = OllamaClient()
        #expect(
            try client.decodeChatLine(
                #"{"message":{"content":"","thinking":"reason"},"done":false}"#)
                == [.thinking("reason")])
        #expect(
            try client.decodeChatLine(
                #"{"message":{"content":"answer","thinking":""},"done":false}"#)
                == [.content("answer")])
    }

    @Test func surfacesStreamErrors() {
        let client = OllamaClient()
        #expect(throws: OllamaError.self) {
            try client.decodeChatLine(#"{"error":"model not found"}"#)
        }
    }

    private func makeClient(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (OllamaClient, URLSession) {
        StubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return (
            OllamaClient(baseURL: URL(string: "http://ollama.test")!, session: session), session
        )
    }

    private func response(
        for request: URLRequest,
        statusCode: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
