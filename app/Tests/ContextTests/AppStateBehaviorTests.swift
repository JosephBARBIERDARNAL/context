import Foundation
import Testing

@testable import Context

@Suite("App state behavior")
struct AppStateBehaviorTests {
    @Test @MainActor
    func databaseFailureDisablesChatWithoutAcceptingAMessage() {
        let state = AppState(
            defaults: isolatedDefaults(),
            ollama: StubOllama(mode: .models([ModelInfo(name: "model", sizeBytes: 1)])),
            databaseFactory: { throw StubError.databaseUnavailable })
        state.ollamaStatus = .ready

        #expect(!state.canStartChat)
        state.newTab()
        #expect(state.tabs.isEmpty)
        #expect(!state.send("do not discard this"))
        #expect(state.errorMessage?.contains("Failed to open the local database") == true)
    }

    @Test @MainActor
    func cancellingBeforeTheFirstTokenDoesNotStoreAnEmptyAssistantMessage() async throws {
        let database = RecordingDatabase()
        let state = makeState(database: database, ollama: StubOllama(mode: .blocked))
        state.ollamaStatus = .ready
        state.newTab()
        let tab = try #require(state.activeTab)

        #expect(state.send("question"))
        try await waitUntil { tab.conversationID != nil }
        state.cancelStreaming()
        try await waitUntil { !tab.isStreaming }

        let conversationID = try #require(tab.conversationID)
        let messages = await database.getMessages(conversationId: conversationID)
        #expect(messages.map(\.role) == ["user"])
        #expect(messages.map(\.content) == ["question"])
    }

    @Test @MainActor
    func cancellationPreservesThinkingThatWasAlreadyStreamed() async throws {
        let database = RecordingDatabase()
        let state = makeState(database: database, ollama: StubOllama(mode: .thinkingThenBlocked))
        state.ollamaStatus = .ready
        state.newTab()
        let tab = try #require(state.activeTab)

        #expect(state.send("question"))
        try await waitUntil { tab.streamingThinkingText == "reason" }
        state.cancelStreaming()
        try await waitUntil { !tab.isStreaming }

        let conversationID = try #require(tab.conversationID)
        let messages = await database.getMessages(conversationId: conversationID)
        #expect(messages.map(\.role) == ["user", "assistant"])
        #expect(messages.last?.content == "")
        #expect(messages.last?.thinking == "reason")
    }

    @Test @MainActor
    func streamingFailureResetsTheTabAndReportsTheError() async throws {
        let database = RecordingDatabase()
        let state = makeState(database: database, ollama: StubOllama(mode: .streamFailure))
        state.ollamaStatus = .ready
        state.newTab()
        let tab = try #require(state.activeTab)

        #expect(state.send("question"))
        try await waitUntil { !tab.isStreaming }

        #expect(state.errorMessage == StubError.streamFailure.localizedDescription)
        #expect(tab.streamingText == nil)
        #expect(tab.streamingThinkingText == nil)
        let conversationID = try #require(tab.conversationID)
        #expect(await database.getMessages(conversationId: conversationID).count == 1)
    }

    @Test @MainActor
    func burstStreamStoresEveryBufferedToken() async throws {
        let database = RecordingDatabase()
        let state = makeState(database: database, ollama: StubOllama(mode: .burst))
        state.ollamaStatus = .ready
        state.newTab()
        let tab = try #require(state.activeTab)

        #expect(state.send("question"))
        try await waitUntil { !tab.isStreaming }

        let conversationID = try #require(tab.conversationID)
        let messages = await database.getMessages(conversationId: conversationID)
        #expect(messages.map(\.content) == ["question", "answer"])
    }

    @Test @MainActor
    func migratesLegacyContextDefaultOnceAndPreservesLaterOptOut() throws {
        let defaults = isolatedDefaults()
        defaults.set(
            try JSONEncoder().encode(GenerationOptions.modelDefaults),
            forKey: "generationOptions")

        let first = AppState(
            defaults: defaults,
            database: RecordingDatabase(),
            ollama: StubOllama(mode: .models([ModelInfo(name: "model", sizeBytes: 1)])))
        #expect(first.generationOptions.numCtx == 4096)

        var optedOut = first.generationOptions
        optedOut.numCtx = nil
        first.generationOptions = optedOut

        let relaunched = AppState(
            defaults: defaults,
            database: RecordingDatabase(),
            ollama: StubOllama(mode: .models([ModelInfo(name: "model", sizeBytes: 1)])))
        #expect(relaunched.generationOptions.numCtx == nil)
    }

    @Test @MainActor
    func refreshModelsCoversReadyEmptyAndUnavailableStates() async {
        let database = RecordingDatabase()
        let ready = makeState(
            database: database,
            ollama: StubOllama(mode: .models([ModelInfo(name: "available", sizeBytes: 1)])))
        ready.defaultModel = "missing"
        ready.ollamaStatus = .ready
        ready.newTab()
        await ready.refreshModels()
        #expect(ready.ollamaStatus == .ready)
        #expect(ready.defaultModel == "available")
        #expect(ready.activeTab?.selectedModel == "available")

        let empty = makeState(database: database, ollama: StubOllama(mode: .models([])))
        await empty.refreshModels()
        #expect(empty.ollamaStatus == .noModels)

        let unavailable = makeState(database: database, ollama: StubOllama(mode: .listFailure))
        await unavailable.refreshModels()
        #expect(unavailable.ollamaStatus == .unavailable)
        #expect(unavailable.models.isEmpty)
    }

    @Test
    func remoteInlineMarkdownImagesAreRejected() async {
        let provider = DisabledMarkdownInlineImageProvider()
        await #expect(throws: MarkdownImageLoadingError.self) {
            try await provider.image(
                with: URL(string: "https://example.com/tracker.png")!, label: "tracker")
        }
    }

    @MainActor
    private func makeState(
        database: RecordingDatabase,
        ollama: StubOllama
    ) -> AppState {
        AppState(defaults: isolatedDefaults(), database: database, ollama: ollama)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "AppStateBehaviorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw StubError.timeout
    }
}

private enum StubError: LocalizedError {
    case databaseUnavailable
    case listFailure
    case streamFailure
    case timeout

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable: "database unavailable"
        case .listFailure: "list failure"
        case .streamFailure: "stream failure"
        case .timeout: "timed out waiting for state change"
        }
    }
}

private struct StubOllama: OllamaServing {
    enum Mode: Sendable {
        case models([ModelInfo])
        case listFailure
        case blocked
        case thinkingThenBlocked
        case streamFailure
        case burst
    }

    let mode: Mode

    func listModels() async throws -> [ModelInfo] {
        switch mode {
        case .listFailure:
            throw StubError.listFailure
        case .models(let models):
            return models
        case .blocked, .thinkingThenBlocked, .streamFailure, .burst:
            return [ModelInfo(name: "model", sizeBytes: 1)]
        }
    }

    func streamChat(
        model: String,
        history: [Message],
        options: GenerationOptions
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                if case .thinkingThenBlocked = mode {
                    continuation.yield(.thinking("reason"))
                }
                if case .streamFailure = mode {
                    continuation.finish(throwing: StubError.streamFailure)
                    return
                }
                if case .burst = mode {
                    for token in ["a", "n", "s", "w", "e", "r"] {
                        continuation.yield(.content(token))
                    }
                    continuation.finish()
                    return
                }
                do {
                    try await Task.sleep(for: .seconds(60))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private actor RecordingDatabase: ChatDatabase {
    private var conversations: [Conversation] = []
    private var messages: [Int64: [Message]] = [:]
    private var nextConversationID: Int64 = 1
    private var nextMessageID: Int64 = 1

    func listConversations() -> [Conversation] {
        conversations
    }

    func createConversationWithMessage(model: String, content: String) -> Conversation {
        let id = nextConversationID
        nextConversationID += 1
        let conversation = Conversation(
            id: id, title: content, model: model, createdAt: id, updatedAt: id)
        conversations.append(conversation)
        messages[id] = [makeMessage(conversationID: id, role: "user", content: content)]
        return conversation
    }

    func deleteConversation(id: Int64) {
        conversations.removeAll { $0.id == id }
        messages[id] = nil
    }

    func renameConversation(id: Int64, title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let existing = conversations[index]
        conversations[index] = Conversation(
            id: existing.id,
            title: title,
            model: existing.model,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt)
    }

    func setConversationModel(id: Int64, model: String) {}

    func getMessages(conversationId: Int64) -> [Message] {
        messages[conversationId] ?? []
    }

    func listSearchableMessages() -> [SearchableMessage] { [] }

    func insertMessage(
        conversationId: Int64,
        role: String,
        content: String,
        thinking: String?
    ) -> Message {
        let message = makeMessage(
            conversationID: conversationId, role: role, content: content, thinking: thinking)
        messages[conversationId, default: []].append(message)
        return message
    }

    func replaceMessageAndTruncate(
        conversationId: Int64,
        messageId: Int64,
        content: String
    ) {}

    func maybeAutotitle(conversationId: Int64, content: String) {}

    private func makeMessage(
        conversationID: Int64,
        role: String,
        content: String,
        thinking: String? = nil
    ) -> Message {
        defer { nextMessageID += 1 }
        return Message(
            id: nextMessageID,
            conversationId: conversationID,
            role: role,
            content: content,
            thinking: thinking,
            createdAt: nextMessageID)
    }
}
