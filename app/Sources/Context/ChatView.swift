import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var state
    @State private var highlightedMessageID: Int64?
    @State private var highlightTask: Task<Void, Never>?

    private let bottomAnchor = "bottom"

    var body: some View {
        @Bindable var state = state
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(state.messages) { message in
                        StoredMessageRow(
                            message: message,
                            isSearchTarget: highlightedMessageID == message.id
                        )
                        .id(message.id)
                    }
                    if state.isStreamingSelectedConversation {
                        let snapshot = state.streamingSnapshot ?? .empty
                        let text = snapshot.content
                        let thinking = snapshot.thinking
                        if !text.isEmpty || !thinking.isEmpty {
                            MessageBubble(
                                role: "assistant",
                                content: text,
                                thinking: thinking.isEmpty ? nil : thinking,
                                isStreaming: true)
                        } else {
                            ThinkingIndicator()
                        }
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .onChange(of: state.streamingSnapshot) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
            .onChange(of: state.messages.count) {
                updateScrollPosition(using: proxy)
            }
            .onChange(of: state.pendingMessageJumpID) {
                performPendingJump(using: proxy)
            }
            .onAppear {
                updateScrollPosition(using: proxy)
            }
        }
        .background {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.accentColor.opacity(0.02),
                    Color.clear,
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            ComposerView()
        }
        .navigationTitle(state.selectedConversation?.title ?? "New Chat")
        .navigationSubtitle(state.selectedModel)
        .toolbar {
            ToolbarItem {
                Picker("Model", selection: $state.selectedModel) {
                    ForEach(state.models, id: \.name) { model in
                        Text(model.name).tag(model.name)
                    }
                }
                .pickerStyle(.menu)
                .help("Model used for the next message")
            }
        }
    }

    private func updateScrollPosition(using proxy: ScrollViewProxy) {
        if state.pendingMessageJumpID == nil {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        } else {
            performPendingJump(using: proxy)
        }
    }

    private func performPendingJump(using proxy: ScrollViewProxy) {
        guard let messageID = state.pendingMessageJumpID,
            state.messages.contains(where: { $0.id == messageID })
        else { return }

        highlightTask?.cancel()
        highlightTask = Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(messageID, anchor: .center)
            }
            highlightedMessageID = messageID
            state.completeMessageJump(messageID)
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                highlightedMessageID = nil
            }
        }
    }
}

private struct StoredMessageRow: View {
    @Environment(AppState.self) private var state

    let message: Message
    let isSearchTarget: Bool

    var body: some View {
        MessageBubble(
            role: message.role,
            content: message.content,
            thinking: message.thinking,
            isSearchTarget: isSearchTarget,
            onEdit: editAction)
    }

    private var editAction: (() -> Void)? {
        guard message.role == "user", !state.isStreaming else { return nil }
        return { state.edit(message) }
    }
}

private struct ThinkingIndicator: View {
    var body: some View {
        HStack {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Thinking…")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.08), in: .capsule)
            Spacer()
        }
    }
}
