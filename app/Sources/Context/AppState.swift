import Foundation
import Observation

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

    @ObservationIgnored private var database: (any ChatDatabase)?
    @ObservationIgnored private let ollama: any OllamaServing
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var activeGenerationTask: Task<Void, Never>?

    var conversations: [Conversation] = []
    var selectedConversationID: Int64? {
        didSet { conversationSelectionChanged() }
    }
    var messages: [Message] = []
    var isDraftChat = false
    var streamingText: String?
    var streamingThinkingText: String?
    var isStreaming = false
    private(set) var activeGenerationConversationID: Int64?
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

    var isStreamingSelectedConversation: Bool {
        isStreaming && activeGenerationConversationID == selectedConversationID
    }

    init(
        defaults: UserDefaults = .standard,
        database injectedDatabase: (any ChatDatabase)? = nil,
        ollama: any OllamaServing = OllamaClient()
    ) {
        self.defaults = defaults
        self.ollama = ollama
        if let data = defaults.data(forKey: AppState.generationOptionsKey),
            let options = try? JSONDecoder().decode(GenerationOptions.self, from: data)
        {
            generationOptions = options
        }
        let savedDefaultModel =
            defaults.string(forKey: AppState.defaultModelKey)
            ?? AppState.defaultModel
        defaultModel = savedDefaultModel
        selectedModel = savedDefaultModel
        appearance =
            AppAppearance(
                rawValue: defaults.string(forKey: AppState.appearanceKey) ?? "") ?? .system

        if let injectedDatabase {
            database = injectedDatabase
        } else {
            do {
                let support = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true)
                let directory = support.appendingPathComponent("Context", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                database = try Database(
                    path: directory.appendingPathComponent("context.db").path)
            } catch {
                errorMessage = "Failed to open the local database: \(error.localizedDescription)"
            }
        }

        Task { await bootstrap() }
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
        guard let database else { return }
        Task {
            if activeGenerationConversationID == conversation.id,
                let activeGenerationTask
            {
                activeGenerationTask.cancel()
                await activeGenerationTask.value
            }
            do {
                try await database.deleteConversation(id: conversation.id)
                conversations = try await database.listConversations()
                if selectedConversationID == conversation.id {
                    selectedConversationID = conversations.first?.id
                }
            } catch {
                report(error)
            }
        }
    }

    func renameConversation(_ conversation: Conversation, to title: String) {
        guard let database else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                try await database.renameConversation(id: conversation.id, title: trimmed)
                conversations = try await database.listConversations()
            } catch {
                report(error)
            }
        }
    }

    private func bootstrap() async {
        if let database {
            do {
                conversations = try await database.listConversations()
                selectedConversationID = conversations.first?.id
            } catch {
                report(error)
            }
        }
        await refreshModels()
    }

    private func conversationSelectionChanged() {
        selectionTask?.cancel()
        if editingMessageID != nil {
            editingMessageID = nil
            composerDraft = ""
        }
        guard let database, let id = selectedConversationID else {
            messages = []
            return
        }
        isDraftChat = false
        if let model = selectedConversation?.model, !model.isEmpty {
            selectedModel = model
        }
        selectionTask = Task {
            do {
                let loaded = try await database.getMessages(conversationId: id)
                try Task.checkCancellation()
                guard selectedConversationID == id else { return }
                messages = loaded
            } catch is CancellationError {
                return
            } catch {
                report(error)
            }
        }
    }

    // MARK: - Message search

    func presentMessageSearch() {
        isMessageSearchPresented = true
        messageSearchError = nil
        guard let database else {
            searchableMessages = []
            messageSearchError = "Chat history is unavailable."
            return
        }
        Task {
            do {
                searchableMessages = try await database.listSearchableMessages()
            } catch {
                searchableMessages = []
                messageSearchError = "Couldn’t load chat history."
            }
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
        guard let database, !isStreaming else { return }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let originalConversationID = selectedConversationID
        let editingID = editingMessageID
        let model = selectedModel
        let options = generationOptions
        isStreaming = true
        streamingText = ""
        streamingThinkingText = ""
        activeGenerationConversationID = originalConversationID

        activeGenerationTask = Task {
            var conversationID = originalConversationID
            var answer = ""
            var thinking = ""
            do {
                if conversationID == nil {
                    let conversation = try await database.createConversationWithMessage(
                        model: model, content: content)
                    conversationID = conversation.id
                    activeGenerationConversationID = conversation.id
                    conversations = try await database.listConversations()
                    selectedConversationID = conversation.id
                } else if let conversationID, let editingID {
                    try await database.setConversationModel(id: conversationID, model: model)
                    try await database.replaceMessageAndTruncate(
                        conversationId: conversationID,
                        messageId: editingID,
                        content: content)
                    self.editingMessageID = nil
                } else if let conversationID {
                    try await database.setConversationModel(id: conversationID, model: model)
                    _ = try await database.insertMessage(
                        conversationId: conversationID,
                        role: "user",
                        content: content,
                        thinking: nil)
                    try await database.maybeAutotitle(
                        conversationId: conversationID, content: content)
                }

                guard let conversationID else { return }
                activeGenerationConversationID = conversationID
                let history = try await database.getMessages(conversationId: conversationID)
                if selectedConversationID == conversationID {
                    messages = history
                }
                conversations = try await database.listConversations()

                for try await event in ollama.streamChat(
                    model: model, history: history, options: options)
                {
                    switch event {
                    case .thinking(let token):
                        thinking += token
                        streamingThinkingText = thinking
                    case .content(let token):
                        answer += token
                        streamingText = answer
                    }
                }

                try await completeGeneration(
                    database: database,
                    conversationID: conversationID,
                    answer: answer,
                    thinking: thinking)
            } catch {
                guard let conversationID else {
                    handleGenerationError(error)
                    return
                }
                if Task.isCancelled || isCancellation(error) {
                    do {
                        try await completeGeneration(
                            database: database,
                            conversationID: conversationID,
                            answer: answer,
                            thinking: thinking)
                    } catch {
                        handleGenerationError(error)
                    }
                } else {
                    handleGenerationError(error)
                }
            }
        }
    }

    func cancelStreaming() {
        activeGenerationTask?.cancel()
    }

    private func completeGeneration(
        database: any ChatDatabase,
        conversationID: Int64,
        answer: String,
        thinking: String
    ) async throws {
        let message = try await database.insertMessage(
            conversationId: conversationID,
            role: "assistant",
            content: answer,
            thinking: thinking.isEmpty ? nil : thinking)
        isStreaming = false
        activeGenerationConversationID = nil
        activeGenerationTask = nil
        streamingText = nil
        streamingThinkingText = nil
        if conversationID == selectedConversationID {
            messages.append(message)
        }
        conversations = try await database.listConversations()
    }

    private func handleGenerationError(_ error: Error) {
        isStreaming = false
        activeGenerationConversationID = nil
        activeGenerationTask = nil
        streamingText = nil
        streamingThinkingText = nil
        report(error)
    }

    func refreshModels() async {
        ollamaStatus = .checking
        do {
            models = try await ollama.listModels()
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

    private func persistGenerationOptions() {
        if let data = try? JSONEncoder().encode(generationOptions) {
            defaults.set(data, forKey: AppState.generationOptionsKey)
        }
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    return (error as? URLError)?.code == .cancelled
}
