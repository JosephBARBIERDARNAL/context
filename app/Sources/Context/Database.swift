import Foundation
import SQLite3

protocol ChatDatabase: Sendable {
    func listConversations() async throws -> [Conversation]
    func createConversationWithMessage(model: String, content: String) async throws -> Conversation
    func deleteConversation(id: Int64) async throws
    func renameConversation(id: Int64, title: String) async throws
    func setConversationModel(id: Int64, model: String) async throws
    func getMessages(conversationId: Int64) async throws -> [Message]
    func listSearchableMessages() async throws -> [SearchableMessage]
    func insertMessage(
        conversationId: Int64, role: String, content: String, thinking: String?
    ) async throws -> Message
    func replaceMessageAndTruncate(
        conversationId: Int64, messageId: Int64, content: String
    ) async throws
    func maybeAutotitle(conversationId: Int64, content: String) async throws
}

struct DatabaseError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

actor Database: ChatDatabase {
    nonisolated(unsafe) private var connection: OpaquePointer?

    init(path: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(path, &database) == SQLITE_OK, let database else {
            let message =
                database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Could not open the database."
            sqlite3_close(database)
            throw DatabaseError(message: message)
        }
        connection = database
        do {
            try Self.initialize(database)
        } catch {
            sqlite3_close(database)
            connection = nil
            throw error
        }
    }

    deinit {
        sqlite3_close(connection)
    }

    func listConversations() throws -> [Conversation] {
        let statement = try prepare(
            """
            SELECT id, title, model, created_at, updated_at
            FROM conversations
            WHERE EXISTS (
                SELECT 1 FROM messages
                WHERE messages.conversation_id = conversations.id
            )
            ORDER BY updated_at DESC, id DESC
            """)
        defer { sqlite3_finalize(statement) }

        var conversations: [Conversation] = []
        while try step(statement) {
            conversations.append(
                Conversation(
                    id: sqlite3_column_int64(statement, 0),
                    title: text(statement, 1),
                    model: text(statement, 2),
                    createdAt: sqlite3_column_int64(statement, 3),
                    updatedAt: sqlite3_column_int64(statement, 4)))
        }
        return conversations
    }

    func createConversationWithMessage(model: String, content: String) throws -> Conversation {
        let timestamp = now()
        let title = title(from: content)
        var conversationId: Int64 = 0
        try transaction {
            let conversation = try prepare(
                """
                INSERT INTO conversations (title, model, created_at, updated_at)
                VALUES (?1, ?2, ?3, ?3)
                """)
            defer { sqlite3_finalize(conversation) }
            try bind(title, to: conversation, at: 1)
            try bind(model, to: conversation, at: 2)
            try bind(timestamp, to: conversation, at: 3)
            try finish(conversation)

            conversationId = sqlite3_last_insert_rowid(connection)
            let message = try prepare(
                """
                INSERT INTO messages (conversation_id, role, content, created_at)
                VALUES (?1, 'user', ?2, ?3)
                """)
            defer { sqlite3_finalize(message) }
            try bind(conversationId, to: message, at: 1)
            try bind(content, to: message, at: 2)
            try bind(timestamp, to: message, at: 3)
            try finish(message)
        }

        return Conversation(
            id: conversationId,
            title: title,
            model: model,
            createdAt: timestamp,
            updatedAt: timestamp)
    }

    func deleteConversation(id: Int64) throws {
        try executeUpdate("DELETE FROM conversations WHERE id = ?1") {
            try bind(id, to: $0, at: 1)
        }
    }

    func renameConversation(id: Int64, title: String) throws {
        try executeUpdate("UPDATE conversations SET title = ?1 WHERE id = ?2") {
            try bind(title, to: $0, at: 1)
            try bind(id, to: $0, at: 2)
        }
    }

    func setConversationModel(id: Int64, model: String) throws {
        try executeUpdate("UPDATE conversations SET model = ?1 WHERE id = ?2") {
            try bind(model, to: $0, at: 1)
            try bind(id, to: $0, at: 2)
        }
    }

    func getMessages(conversationId: Int64) throws -> [Message] {
        let statement = try prepare(
            """
            SELECT id, conversation_id, role, content, thinking, created_at
            FROM messages WHERE conversation_id = ?1 ORDER BY id ASC
            """)
        defer { sqlite3_finalize(statement) }
        try bind(conversationId, to: statement, at: 1)

        var messages: [Message] = []
        while try step(statement) {
            messages.append(
                Message(
                    id: sqlite3_column_int64(statement, 0),
                    conversationId: sqlite3_column_int64(statement, 1),
                    role: text(statement, 2),
                    content: text(statement, 3),
                    thinking: optionalText(statement, 4),
                    createdAt: sqlite3_column_int64(statement, 5)))
        }
        return messages
    }

    func listSearchableMessages() throws -> [SearchableMessage] {
        let statement = try prepare(
            """
            SELECT m.id, m.conversation_id, c.title, c.updated_at,
                   m.role, m.content, m.created_at
            FROM messages m
            JOIN conversations c ON c.id = m.conversation_id
            ORDER BY c.updated_at DESC, c.id DESC, m.created_at DESC, m.id DESC
            """)
        defer { sqlite3_finalize(statement) }

        var messages: [SearchableMessage] = []
        while try step(statement) {
            messages.append(
                SearchableMessage(
                    id: sqlite3_column_int64(statement, 0),
                    conversationId: sqlite3_column_int64(statement, 1),
                    conversationTitle: text(statement, 2),
                    conversationUpdatedAt: sqlite3_column_int64(statement, 3),
                    role: text(statement, 4),
                    content: text(statement, 5),
                    createdAt: sqlite3_column_int64(statement, 6)))
        }
        return messages
    }

    func insertMessage(
        conversationId: Int64,
        role: String,
        content: String,
        thinking: String? = nil
    ) throws -> Message {
        let timestamp = now()
        let statement = try prepare(
            """
            INSERT INTO messages (conversation_id, role, content, thinking, created_at)
            VALUES (?1, ?2, ?3, ?4, ?5)
            """)
        defer { sqlite3_finalize(statement) }
        try bind(conversationId, to: statement, at: 1)
        try bind(role, to: statement, at: 2)
        try bind(content, to: statement, at: 3)
        try bind(thinking, to: statement, at: 4)
        try bind(timestamp, to: statement, at: 5)
        try finish(statement)
        let id = sqlite3_last_insert_rowid(connection)

        try executeUpdate("UPDATE conversations SET updated_at = ?1 WHERE id = ?2") {
            try bind(timestamp, to: $0, at: 1)
            try bind(conversationId, to: $0, at: 2)
        }
        return Message(
            id: id,
            conversationId: conversationId,
            role: role,
            content: content,
            thinking: thinking,
            createdAt: timestamp)
    }

    func replaceMessageAndTruncate(
        conversationId: Int64,
        messageId: Int64,
        content: String
    ) throws {
        try transaction {
            let update = try prepare(
                """
                UPDATE messages SET content = ?1, created_at = ?2
                WHERE id = ?3 AND conversation_id = ?4 AND role = 'user'
                """)
            defer { sqlite3_finalize(update) }
            try bind(content, to: update, at: 1)
            try bind(now(), to: update, at: 2)
            try bind(messageId, to: update, at: 3)
            try bind(conversationId, to: update, at: 4)
            try finish(update)
            guard sqlite3_changes(connection) > 0 else {
                throw DatabaseError(message: "The selected user message no longer exists.")
            }

            try executeUpdate(
                "DELETE FROM messages WHERE conversation_id = ?1 AND id > ?2"
            ) {
                try bind(conversationId, to: $0, at: 1)
                try bind(messageId, to: $0, at: 2)
            }
            try executeUpdate("UPDATE conversations SET updated_at = ?1 WHERE id = ?2") {
                try bind(now(), to: $0, at: 1)
                try bind(conversationId, to: $0, at: 2)
            }
        }
    }

    func maybeAutotitle(conversationId: Int64, content: String) throws {
        let query = try prepare("SELECT title FROM conversations WHERE id = ?1")
        defer { sqlite3_finalize(query) }
        try bind(conversationId, to: query, at: 1)
        guard try step(query), text(query, 0) == "New Chat" else { return }
        let derived = title(from: content)
        guard !derived.isEmpty else { return }
        try renameConversation(id: conversationId, title: derived)
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func executeUpdate(
        _ sql: String,
        bindings: (OpaquePointer) throws -> Void
    ) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bindings(statement)
        try finish(statement)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw currentError()
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
            let statement
        else {
            throw currentError()
        }
        return statement
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw currentError()
        }
    }

    private func bind(_ value: String?, to statement: OpaquePointer, at index: Int32) throws {
        if let value {
            try bind(value, to: statement, at: index)
        } else if sqlite3_bind_null(statement, index) != SQLITE_OK {
            throw currentError()
        }
    }

    private func bind(_ value: Int64, to statement: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
            throw currentError()
        }
    }

    private func finish(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() }
    }

    private func step(_ statement: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: true
        case SQLITE_DONE: false
        default: throw currentError()
        }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func optionalText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return text(statement, index)
    }

    private func currentError() -> DatabaseError {
        guard let connection else { return DatabaseError(message: "Database is closed.") }
        return DatabaseError(message: String(cString: sqlite3_errmsg(connection)))
    }

    private static func initialize(_ database: OpaquePointer) throws {
        func execute(_ sql: String) throws {
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw DatabaseError(message: String(cString: sqlite3_errmsg(database)))
            }
        }

        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY,
                title TEXT NOT NULL,
                model TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY,
                conversation_id INTEGER NOT NULL
                    REFERENCES conversations(id) ON DELETE CASCADE,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                thinking TEXT,
                created_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_messages_conversation
                ON messages(conversation_id);
            DELETE FROM conversations
            WHERE NOT EXISTS (
                SELECT 1 FROM messages
                WHERE messages.conversation_id = conversations.id
            );
            """)

        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(database, "PRAGMA table_info(messages)", -1, &statement, nil)
                == SQLITE_OK,
            let statement
        else {
            throw DatabaseError(message: String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        var hasThinking = false
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1), String(cString: name) == "thinking" {
                hasThinking = true
                break
            }
        }
        if !hasThinking {
            try execute("ALTER TABLE messages ADD COLUMN thinking TEXT")
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func now() -> Int64 {
    Int64(Date().timeIntervalSince1970)
}

private func title(from content: String) -> String {
    let collapsed = content.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    guard collapsed.count > 60 else { return collapsed }
    return String(collapsed.prefix(60)) + "…"
}
