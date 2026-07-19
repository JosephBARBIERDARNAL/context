import Foundation

protocol OllamaServing: Sendable {
    func listModels() async throws -> [ModelInfo]
    func streamChat(
        model: String,
        history: [Message],
        options: GenerationOptions
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

struct OllamaError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

final class OllamaClient: OllamaServing, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func listModels() async throws -> [ModelInfo] {
        let (data, response) = try await session.data(
            from: baseURL.appendingPathComponent("api/tags"))
        try validate(response: response)
        let payload = try JSONDecoder().decode(TagsResponse.self, from: data)
        return payload.models.map { ModelInfo(name: $0.name, sizeBytes: $0.size) }
    }

    func streamChat(
        model: String,
        history: [Message],
        options: GenerationOptions
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeChatRequest(
                        model: model, history: history, options: options)

                    let (bytes, response) = try await session.bytes(for: request)
                    try validate(response: response)
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard !line.isEmpty else { continue }
                        for event in try decodeChatLine(line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw OllamaError(message: "Ollama returned an invalid response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw OllamaError(message: "Ollama returned HTTP \(response.statusCode).")
        }
    }

    func makeChatRequest(
        model: String,
        history: [Message],
        options: GenerationOptions
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(model: model, history: history, options: options))
        return request
    }

    func decodeChatLine(_ line: String) throws -> [ChatStreamEvent] {
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: Data(line.utf8))
        if let error = chunk.error {
            throw OllamaError(message: error)
        }
        var events: [ChatStreamEvent] = []
        if let thinking = chunk.message?.thinking, !thinking.isEmpty {
            events.append(.thinking(thinking))
        }
        if let content = chunk.message?.content, !content.isEmpty {
            events.append(.content(content))
        }
        return events
    }
}

private struct TagsResponse: Decodable {
    let models: [TagModel]
}

private struct TagModel: Decodable {
    let name: String
    let size: UInt64
}

private struct ChatChunk: Decodable {
    let message: ChatChunkMessage?
    let error: String?
}

private struct ChatChunkMessage: Decodable {
    let content: String
    let thinking: String?
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [RequestMessage]
    let stream = true
    let options: RuntimeOptions?
    let think: ThinkingValue?

    init(model: String, history: [Message], options: GenerationOptions) {
        self.model = model
        messages = history.map { RequestMessage(role: $0.role, content: $0.content) }
        self.options = options.hasRuntimeOverrides ? RuntimeOptions(options) : nil
        think = ThinkingValue(options.thinking)
    }
}

private struct RequestMessage: Encodable {
    let role: String
    let content: String
}

private enum ThinkingValue: Encodable {
    case boolean(Bool)
    case level(String)

    init?(_ mode: ThinkingMode) {
        switch mode {
        case .modelDefault: return nil
        case .on: self = .boolean(true)
        case .off: self = .boolean(false)
        case .low, .medium, .high: self = .level(mode.rawValue)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .boolean(let value): try container.encode(value)
        case .level(let value): try container.encode(value)
        }
    }
}

private struct RuntimeOptions: Encodable {
    let temperature: Double?
    let numCtx: UInt64?
    let numPredict: Int32?
    let seed: Int32?
    let stop: [String]?
    let topK: UInt32?
    let topP: Double?
    let minP: Double?
    let repeatLastN: Int32?
    let repeatPenalty: Double?
    let tfsZ: Double?
    let mirostat: UInt8?
    let mirostatEta: Double?
    let mirostatTau: Double?

    init(_ options: GenerationOptions) {
        temperature = options.temperature
        numCtx = options.numCtx
        numPredict = options.numPredict
        seed = options.seed
        stop = options.stop
        topK = options.topK
        topP = options.topP
        minP = options.minP
        repeatLastN = options.repeatLastN
        repeatPenalty = options.repeatPenalty
        tfsZ = options.tfsZ
        mirostat = options.mirostat
        mirostatEta = options.mirostatEta
        mirostatTau = options.mirostatTau
    }

    enum CodingKeys: String, CodingKey {
        case temperature
        case numCtx = "num_ctx"
        case numPredict = "num_predict"
        case seed
        case stop
        case topK = "top_k"
        case topP = "top_p"
        case minP = "min_p"
        case repeatLastN = "repeat_last_n"
        case repeatPenalty = "repeat_penalty"
        case tfsZ = "tfs_z"
        case mirostat
        case mirostatEta = "mirostat_eta"
        case mirostatTau = "mirostat_tau"
    }
}
