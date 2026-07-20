import Foundation

struct Conversation: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: Int64
    let title: String
    let model: String
    let createdAt: Int64
    let updatedAt: Int64
}

struct Message: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: Int64
    let conversationId: Int64
    let role: String
    let content: String
    let thinking: String?
    let createdAt: Int64
}

struct SearchableMessage: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: Int64
    let conversationId: Int64
    let conversationTitle: String
    let conversationUpdatedAt: Int64
    let role: String
    let content: String
    let createdAt: Int64
}

struct ModelInfo: Identifiable, Codable, Equatable, Hashable, Sendable {
    let name: String
    let sizeBytes: UInt64

    var id: String { name }
}

enum ThinkingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case modelDefault = "default"
    case on
    case off
    case low
    case medium
    case high

    var id: String { rawValue }
}

struct GenerationOptions: Codable, Equatable, Sendable {
    var thinking: ThinkingMode = .modelDefault
    var temperature: Double?
    var numCtx: UInt64?
    var numPredict: Int32?
    var seed: Int32?
    var stop: [String]?
    var topK: UInt32?
    var topP: Double?
    var minP: Double?
    var repeatLastN: Int32?
    var repeatPenalty: Double?
    var tfsZ: Double?
    var mirostat: UInt8?
    var mirostatEta: Double?
    var mirostatTau: Double?

    static let modelDefaults = GenerationOptions()
    static let appDefaults = GenerationOptions(numCtx: 4096)

    var hasRuntimeOverrides: Bool {
        temperature != nil || numCtx != nil || numPredict != nil || seed != nil
            || stop != nil || topK != nil || topP != nil || minP != nil
            || repeatLastN != nil || repeatPenalty != nil || tfsZ != nil
            || mirostat != nil || mirostatEta != nil || mirostatTau != nil
    }
}

enum ChatStreamEvent: Equatable, Sendable {
    case thinking(String)
    case content(String)
}

struct StreamingSnapshot: Equatable, Sendable {
    var content = ""
    var thinking = ""

    static let empty = StreamingSnapshot()
}
