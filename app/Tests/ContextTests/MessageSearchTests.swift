import Testing

@testable import Context

@Suite("Message search")
struct MessageSearchTests {
    @Test func normalization() {
        #expect(MessageSearch.normalize("  CAFÉ\nChat  ") == "cafe chat")
    }

    @Test func exactMatchesRankAboveFuzzyMatches() {
        let corpus = [
            message(id: 1, content: "conversation search"),
            message(id: 2, content: "scatter every apple rapidly, crossing hills"),
        ]
        let matches = MessageSearch.matches(query: "search", in: corpus)
        #expect(matches.map(\.id) == [1, 2])
    }

    @Test func fuzzyPartialMatch() {
        let matches = MessageSearch.matches(
            query: "msg srch",
            in: [message(id: 1, content: "message search")])
        #expect(matches.map(\.id) == [1])
    }

    @Test func excludesNonmatchesAndCapsResults() {
        let corpus =
            (1...12).map { message(id: Int64($0), content: "matching text \($0)") }
            + [message(id: 20, content: "unrelated")]
        let matches = MessageSearch.matches(query: "matching", in: corpus, limit: 10)
        #expect(matches.count == 10)
        #expect(!matches.contains(where: { $0.id == 20 }))
    }

    @Test func groupsNewestConversationsFirst() {
        let olderStrong = message(
            id: 1, conversationID: 1, title: "Older", updatedAt: 10,
            content: "search")
        let newerWeak = message(
            id: 2, conversationID: 2, title: "Newer", updatedAt: 20,
            content: "something else")
        let groups = MessageSearch.groups(for: [
            MessageSearchMatch(message: olderStrong, score: 100),
            MessageSearchMatch(message: newerWeak, score: 10),
        ])
        #expect(groups.map(\.title) == ["Newer", "Older"])
    }

    private func message(
        id: Int64,
        conversationID: Int64 = 1,
        title: String = "Chat",
        updatedAt: Int64 = 1,
        content: String
    ) -> SearchableMessage {
        SearchableMessage(
            id: id,
            conversationId: conversationID,
            conversationTitle: title,
            conversationUpdatedAt: updatedAt,
            role: "user",
            content: content,
            createdAt: id)
    }
}
