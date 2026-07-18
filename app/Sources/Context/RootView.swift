import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 340)
        } detail: {
            if state.selectedConversationID != nil {
                ChatView()
            } else {
                EmptyStateView()
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

struct EmptyStateView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ContentUnavailableView {
            Label("No Chat Selected", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Start a new conversation with a local model.")
        } actions: {
            Button("New Chat") { state.newChat() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
