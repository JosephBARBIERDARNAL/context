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
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text("CONTEXT")
                    .font(.system(size: 28, weight: .heavy))
                    .tracking(10)
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 24)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))

            Text("Local chats with your Ollama models.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            Button("New Chat") { state.newChat() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), .clear],
                startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        }
    }
}
