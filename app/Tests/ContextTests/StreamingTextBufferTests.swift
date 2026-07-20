import Testing

@testable import Context

@Suite("Streaming text buffer")
struct StreamingTextBufferTests {
    @Test @MainActor
    func publishesFirstTokenThenCoalescesABurst() {
        var published: [StreamingSnapshot] = []
        let buffer = StreamingTextBuffer(interval: .seconds(60)) {
            published.append($0)
        }

        buffer.append(.content("a"))
        for _ in 0..<1_000 {
            buffer.append(.content("x"))
        }

        #expect(published == [StreamingSnapshot(content: "a")])
        #expect(buffer.snapshot.content == "a" + String(repeating: "x", count: 1_000))

        buffer.flush()

        #expect(published.count == 2)
        #expect(published.last == buffer.snapshot)
    }

    @Test @MainActor
    func stopCancelsPendingPublishWithoutLosingBufferedText() async {
        var published: [StreamingSnapshot] = []
        let buffer = StreamingTextBuffer(interval: .seconds(60)) {
            published.append($0)
        }

        buffer.append(.thinking("first"))
        buffer.append(.thinking(" second"))
        buffer.stop()
        await Task.yield()

        #expect(published == [StreamingSnapshot(thinking: "first")])
        #expect(buffer.snapshot.thinking == "first second")
    }

    @Test @MainActor
    func publishesTheLatestSnapshotAfterTheRefreshInterval() async throws {
        var published: [StreamingSnapshot] = []
        let buffer = StreamingTextBuffer(interval: .milliseconds(5)) {
            published.append($0)
        }

        buffer.append(.content("a"))
        buffer.append(.content("b"))

        for _ in 0..<50 where published.count < 2 {
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(published == [StreamingSnapshot(content: "a"), StreamingSnapshot(content: "ab")])
    }
}
