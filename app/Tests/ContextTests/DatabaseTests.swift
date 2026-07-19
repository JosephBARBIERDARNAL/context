import Foundation
import SQLite3
import Testing

@testable import Context

@Suite("Database")
struct DatabaseTests {
    @Test func firstMessageCreationIsAtomicAndVisible() async throws {
        let database = try Database(path: ":memory:")
        let conversation = try await database.createConversationWithMessage(
            model: "gemma4:26b", content: "explain swift actors")

        let conversations = try await database.listConversations()
        let messages = try await database.getMessages(conversationId: conversation.id)
        #expect(conversations == [conversation])
        #expect(messages.count == 1)
        #expect(messages[0].role == "user")
        #expect(messages[0].content == "explain swift actors")
    }

    @Test func thinkingRoundTripsAndConversationDeletionCascades() async throws {
        let database = try Database(path: ":memory:")
        let conversation = try await database.createConversationWithMessage(
            model: "model", content: "hello")
        let assistant = try await database.insertMessage(
            conversationId: conversation.id,
            role: "assistant",
            content: "answer",
            thinking: "reasoning")

        #expect(assistant.thinking == "reasoning")
        #expect(try await database.getMessages(conversationId: conversation.id).count == 2)
        try await database.deleteConversation(id: conversation.id)
        #expect(try await database.getMessages(conversationId: conversation.id).isEmpty)
    }

    @Test func editingUserMessageTruncatesLaterHistory() async throws {
        let database = try Database(path: ":memory:")
        let conversation = try await database.createConversationWithMessage(
            model: "model", content: "first")
        _ = try await database.insertMessage(
            conversationId: conversation.id, role: "assistant", content: "old", thinking: nil)
        let selected = try await database.insertMessage(
            conversationId: conversation.id, role: "user", content: "revise", thinking: nil)
        _ = try await database.insertMessage(
            conversationId: conversation.id, role: "assistant", content: "remove", thinking: nil)

        try await database.replaceMessageAndTruncate(
            conversationId: conversation.id, messageId: selected.id, content: "revised")
        let messages = try await database.getMessages(conversationId: conversation.id)
        #expect(messages.map(\.content) == ["first", "old", "revised"])
    }

    @Test func metadataSearchAndAutotitleMatchExistingBehavior() async throws {
        let database = try Database(path: ":memory:")
        let conversation = try await database.createConversationWithMessage(
            model: "old-model", content: "initial")
        try await database.renameConversation(id: conversation.id, title: "New Chat")
        try await database.setConversationModel(id: conversation.id, model: "new-model")
        try await database.maybeAutotitle(
            conversationId: conversation.id,
            content: String(repeating: "long title ", count: 12))

        let updated = try #require(await database.listConversations().first)
        #expect(updated.model == "new-model")
        #expect(updated.title.count <= 61)
        #expect(updated.title.hasSuffix("…"))

        let searchable = try await database.listSearchableMessages()
        #expect(searchable.count == 1)
        #expect(searchable[0].conversationTitle == updated.title)
        #expect(searchable[0].content == "initial")
    }

    @Test func opensLegacyDatabaseAndAddsThinkingColumn() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("context-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("legacy.db").path

        var connection: OpaquePointer?
        #expect(sqlite3_open(path, &connection) == SQLITE_OK)
        let schema =
            """
            CREATE TABLE conversations (
                id INTEGER PRIMARY KEY, title TEXT NOT NULL, model TEXT NOT NULL,
                created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
            );
            CREATE TABLE messages (
                id INTEGER PRIMARY KEY, conversation_id INTEGER NOT NULL,
                role TEXT NOT NULL, content TEXT NOT NULL, created_at INTEGER NOT NULL
            );
            """
        #expect(sqlite3_exec(connection, schema, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(connection)

        let database = try Database(path: path)
        let conversation = try await database.createConversationWithMessage(
            model: "model", content: "hello")
        let assistant = try await database.insertMessage(
            conversationId: conversation.id,
            role: "assistant",
            content: "answer",
            thinking: "preserved")
        #expect(assistant.thinking == "preserved")
    }
}
