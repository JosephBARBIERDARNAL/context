import Foundation

@MainActor
final class StreamingTextBuffer {
    typealias Publisher = @MainActor (StreamingSnapshot) -> Void

    private let interval: Duration
    private let publisher: Publisher
    private var pendingPublish: Task<Void, Never>?
    private var hasPublished = false
    private var publishedSnapshot: StreamingSnapshot?

    private(set) var snapshot = StreamingSnapshot.empty

    init(
        interval: Duration = .milliseconds(50),
        publisher: @escaping Publisher
    ) {
        self.interval = interval
        self.publisher = publisher
    }

    func append(_ event: ChatStreamEvent) {
        switch event {
        case .thinking(let token):
            snapshot.thinking += token
        case .content(let token):
            snapshot.content += token
        }

        if !hasPublished {
            publishLatest()
        } else {
            schedulePublish()
        }
    }

    func flush() {
        pendingPublish?.cancel()
        pendingPublish = nil
        publishLatest()
    }

    func stop() {
        pendingPublish?.cancel()
        pendingPublish = nil
    }

    private func schedulePublish() {
        guard pendingPublish == nil else { return }
        pendingPublish = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            pendingPublish = nil
            publishLatest()
        }
    }

    private func publishLatest() {
        guard publishedSnapshot != snapshot else { return }
        hasPublished = true
        publishedSnapshot = snapshot
        publisher(snapshot)
    }
}
