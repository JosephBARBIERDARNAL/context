import Foundation
import Testing

@testable import Context

@Suite("Ollama client")
struct OllamaClientTests {
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
}
