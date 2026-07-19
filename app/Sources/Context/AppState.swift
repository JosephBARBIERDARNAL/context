import ContextCore
import Foundation
import Observation

extension Conversation: Identifiable {}
extension Message: Identifiable {}

extension GenerationOptions {
    static var modelDefaults: GenerationOptions {
        GenerationOptions(
            thinking: .modelDefault,
            temperature: nil,
            numCtx: nil,
            numPredict: nil,
            seed: nil,
            stop: nil,
            topK: nil,
            topP: nil,
            minP: nil,
            repeatLastN: nil,
            repeatPenalty: nil,
            tfsZ: nil,
            mirostat: nil,
            mirostatEta: nil,
            mirostatTau: nil)
    }
}

private struct StoredGenerationOptions: Codable {
    var thinking: String
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

    init(_ options: GenerationOptions) {
        thinking = options.thinking.storageName
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

    var options: GenerationOptions {
        GenerationOptions(
            thinking: ThinkingMode(storageName: thinking),
            temperature: temperature,
            numCtx: numCtx,
            numPredict: numPredict,
            seed: seed,
            stop: stop,
            topK: topK,
            topP: topP,
            minP: minP,
            repeatLastN: repeatLastN,
            repeatPenalty: repeatPenalty,
            tfsZ: tfsZ,
            mirostat: mirostat,
            mirostatEta: mirostatEta,
            mirostatTau: mirostatTau)
    }
}

private extension ThinkingMode {
    var storageName: String {
        switch self {
        case .modelDefault: "default"
        case .on: "on"
        case .off: "off"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        }
    }

    init(storageName: String) {
        switch storageName {
        case "on": self = .on
        case "off": self = .off
        case "low": self = .low
        case "medium": self = .medium
        case "high": self = .high
        default: self = .modelDefault
        }
    }
}

@Observable @MainActor
final class AppState {
    static let defaultModel = "gemma4:26b"
    private static let appearanceKey = "appearance"
    private static let defaultModelKey = "defaultModel"
    private static let generationOptionsKey = "generationOptions"

    enum OllamaStatus: Equatable {
        case checking
        case unavailable
        case noModels
        case ready
    }

    @ObservationIgnored private var core: ContextCore?
    @ObservationIgnored private let defaults: UserDefaults

    var conversations: [Conversation] = []
    var selectedConversationID: Int64? {
        didSet { conversationSelectionChanged() }
    }
    var messages: [Message] = []
    var isDraftChat = false
    /// Assistant text accumulated so far for the in-flight response.
    var streamingText: String?
    /// Reasoning accumulated separately from the visible assistant answer.
    var streamingThinkingText: String?
    var isStreaming = false
    var models: [ModelInfo] = []
    var selectedModel: String
    var generationOptions = GenerationOptions.modelDefaults {
        didSet { persistGenerationOptions() }
    }
    var defaultModel: String {
        didSet { defaults.set(defaultModel, forKey: AppState.defaultModelKey) }
    }
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: AppState.appearanceKey) }
    }
    var ollamaStatus = OllamaStatus.checking
    var errorMessage: String?
    var composerDraft = ""
    var composerFocusRequest = 0
    var sidebarFocusRequest = 0
    var editingMessageID: Int64?
    var isMessageSearchPresented = false
    var searchableMessages: [SearchableMessage] = []
    var messageSearchError: String?
    var pendingMessageJumpID: Int64?

    var canStartChat: Bool { ollamaStatus == .ready }

    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: AppState.generationOptionsKey),
            let stored = try? JSONDecoder().decode(StoredGenerationOptions.self, from: data)
        {
            generationOptions = stored.options
        }
        let savedDefaultModel = defaults.string(forKey: AppState.defaultModelKey)
            ?? AppState.defaultModel
        defaultModel = savedDefaultModel
        selectedModel = savedDefaultModel
        appearance = AppAppearance(
            rawValue: defaults.string(forKey: AppState.appearanceKey) ?? "") ?? .system
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            let dir = support.appendingPathComponent("Context", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let core = try ContextCore(dbPath: dir.appendingPathComponent("context.db").path)
            self.core = core
            conversations = try core.listConversations()
            selectedConversationID = conversations.first?.id
            conversationSelectionChanged()
        } catch {
            errorMessage = "Failed to open the local database: \(error)"
        }
        Task { await refreshModels() }
    }

    // MARK: - Conversations

    func newChat() {
        guard canStartChat else { return }
        isDraftChat = true
        selectedConversationID = nil
        messages = []
        editingMessageID = nil
        composerDraft = ""
        selectedModel = defaultModel
        composerFocusRequest += 1
    }

    func deleteConversation(_ conversation: Conversation) {
        guard let core else { return }
        do {
            core.cancel(conversationId: conversation.id)
            try core.deleteConversation(conversationId: conversation.id)
            conversations = try core.listConversations()
            if selectedConversationID == conversation.id {
                selectedConversationID = conversations.first?.id
            }
        } catch {
            report(error)
        }
    }

    func renameConversation(_ conversation: Conversation, to title: String) {
        guard let core else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try core.renameConversation(conversationId: conversation.id, title: trimmed)
            conversations = try core.listConversations()
        } catch {
            report(error)
        }
    }

    private func conversationSelectionChanged() {
        if editingMessageID != nil {
            editingMessageID = nil
            composerDraft = ""
        }
        guard let core, let id = selectedConversationID else {
            messages = []
            return
        }
        isDraftChat = false
        do {
            messages = try core.getMessages(conversationId: id)
            if let model = selectedConversation?.model, !model.isEmpty {
                selectedModel = model
            }
        } catch {
            report(error)
        }
    }

    // MARK: - Message search

    func presentMessageSearch() {
        isMessageSearchPresented = true
        messageSearchError = nil
        guard let core else {
            searchableMessages = []
            messageSearchError = "Chat history is unavailable."
            return
        }
        do {
            searchableMessages = try core.listSearchableMessages()
        } catch {
            searchableMessages = []
            messageSearchError = "Couldn’t load chat history."
        }
    }

    func dismissMessageSearch() {
        isMessageSearchPresented = false
        messageSearchError = nil
    }

    func jump(to result: SearchableMessage) {
        isMessageSearchPresented = false
        messageSearchError = nil
        if selectedConversationID != result.conversationId {
            selectedConversationID = result.conversationId
        }
        pendingMessageJumpID = result.id
    }

    func completeMessageJump(_ messageID: Int64) {
        guard pendingMessageJumpID == messageID else { return }
        pendingMessageJumpID = nil
    }

    // MARK: - Chat

    func edit(_ message: Message) {
        guard !isStreaming, message.role == "user" else { return }
        guard message.conversationId == selectedConversationID else { return }
        editingMessageID = message.id
        composerDraft = message.content
        composerFocusRequest += 1
    }

    func send(_ text: String) {
        guard let core, !isStreaming else { return }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        do {
            let isNewConversation = selectedConversationID == nil
            if selectedConversationID == nil {
                let conversation = try core.createConversationWithMessage(
                    model: selectedModel,
                    content: content)
                conversations = try core.listConversations()
                selectedConversationID = conversation.id
            }
            guard let id = selectedConversationID else { return }
            isStreaming = true
            streamingText = ""
            streamingThinkingText = ""
            let listener = StreamListener(state: self, conversationID: id)
            if isNewConversation {
                try core.generateReply(
                    conversationId: id,
                    model: selectedModel,
                    options: generationOptions,
                    listener: listener)
            } else if let editingMessageID {
                try core.resendMessage(
                    conversationId: id,
                    messageId: editingMessageID,
                    content: content,
                    model: selectedModel,
                    options: generationOptions,
                    listener: listener)
                self.editingMessageID = nil
            } else {
                try core.sendMessage(
                    conversationId: id,
                    content: content,
                    model: selectedModel,
                    options: generationOptions,
                    listener: listener)
            }
            // The user message is persisted synchronously by the core.
            messages = try core.getMessages(conversationId: id)
            conversations = try core.listConversations()
        } catch {
            isStreaming = false
            streamingText = nil
            streamingThinkingText = nil
            report(error)
        }
    }

    func cancelStreaming() {
        guard let core, let id = selectedConversationID else { return }
        core.cancel(conversationId: id)
    }

    func refreshModels() async {
        guard let core else { return }
        ollamaStatus = .checking
        do {
            models = try await core.listModels()
            guard !models.isEmpty else {
                ollamaStatus = .noModels
                return
            }
            if !models.contains(where: { $0.name == defaultModel }), let first = models.first {
                defaultModel = first.name
            }
            if selectedConversationID == nil {
                selectedModel = defaultModel
            } else if !models.contains(where: { $0.name == selectedModel }),
                let first = models.first
            {
                selectedModel = first.name
            }
            ollamaStatus = .ready
        } catch {
            models = []
            ollamaStatus = .unavailable
        }
    }

    // MARK: - Stream callbacks (hopped to MainActor by StreamListener)

    func handleToken(conversationID: Int64, token: String) {
        guard conversationID == selectedConversationID else { return }
        streamingText = (streamingText ?? "") + token
    }

    func handleThinking(conversationID: Int64, token: String) {
        guard conversationID == selectedConversationID else { return }
        streamingThinkingText = (streamingThinkingText ?? "") + token
    }

    func handleComplete(conversationID: Int64, message: Message) {
        isStreaming = false
        streamingText = nil
        streamingThinkingText = nil
        if conversationID == selectedConversationID {
            messages.append(message)
        }
        if let core {
            conversations = (try? core.listConversations()) ?? conversations
        }
    }

    func handleError(conversationID: Int64, error: String) {
        isStreaming = false
        streamingText = nil
        streamingThinkingText = nil
        errorMessage = error
    }

    private func persistGenerationOptions() {
        if let data = try? JSONEncoder().encode(StoredGenerationOptions(generationOptions)) {
            defaults.set(data, forKey: AppState.generationOptionsKey)
        }
    }

    private func report(_ error: Error) {
        errorMessage = String(describing: error)
    }
}

/// Bridges UniFFI's `ChatListener` callbacks (invoked on a tokio worker
/// thread) onto the MainActor.
final class StreamListener: ChatListener, @unchecked Sendable {
    private weak var state: AppState?
    private let conversationID: Int64

    init(state: AppState, conversationID: Int64) {
        self.state = state
        self.conversationID = conversationID
    }

    func onToken(token: String) {
        Task { @MainActor in
            self.state?.handleToken(conversationID: self.conversationID, token: token)
        }
    }

    func onThinking(token: String) {
        Task { @MainActor in
            self.state?.handleThinking(conversationID: self.conversationID, token: token)
        }
    }

    func onComplete(message: Message) {
        Task { @MainActor in
            self.state?.handleComplete(conversationID: self.conversationID, message: message)
        }
    }

    func onError(error: String) {
        Task { @MainActor in
            self.state?.handleError(conversationID: self.conversationID, error: error)
        }
    }
}
