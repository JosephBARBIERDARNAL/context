import AppKit
import MarkdownUI
import SwiftUI

struct MessageBubble: View {
    let role: String
    let content: String
    var thinking: String?
    var isStreaming = false
    var isSearchTarget = false
    var onEdit: (() -> Void)?

    @State private var hovering = false
    @State private var hoveringActions = false
    @State private var copied = false
    @State private var isThinkingExpanded = false

    private var isUser: Bool { role == "user" }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
            HStack(alignment: .bottom) {
                if isUser { Spacer(minLength: 70) }
                messageContent
                    .font(.system(size: 18))
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassEffect(
                        isUser ? .regular.tint(.accentColor.opacity(0.5)) : .regular,
                        in: .rect(cornerRadius: 20, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: isSearchTarget ? 3 : 0)
                            .shadow(
                                color: Color.accentColor.opacity(isSearchTarget ? 0.45 : 0),
                                radius: 8)
                    }
                if !isUser { Spacer(minLength: 70) }
            }
            if onEdit != nil || !content.isEmpty {
                actionButtons
                    .opacity(hovering || hoveringActions || copied ? 1 : 0.45)
                    .onHover { hoveringActions = $0 }
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .animation(.easeInOut(duration: 0.15), value: copied)
        .animation(.easeInOut(duration: 0.2), value: isSearchTarget)
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if let onEdit {
                actionButton(
                    systemImage: "pencil",
                    help: "Edit message",
                    action: onEdit)
            }
            actionButton(
                systemImage: copied ? "checkmark" : "doc.on.doc",
                help: copied ? "Copied" : "Copy message",
                action: copy)
        }
    }

    private func actionButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(.quaternary, in: Circle())
        .help(help)
    }

    @ViewBuilder
    private var messageContent: some View {
        if isUser {
            Text(content)
                .textSelection(.enabled)
        } else {
            let reasoning = thinking ?? ""
            let hasReasoning = !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isActivelyThinking = isStreaming && content.isEmpty && hasReasoning
            VStack(alignment: .leading, spacing: 10) {
                if hasReasoning {
                    if isActivelyThinking {
                        reasoningText(reasoning)
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isThinkingExpanded.toggle()
                            }
                        } label: {
                            Label(
                                isThinkingExpanded ? "Hide Thinking" : "Show Thinking",
                                systemImage: isThinkingExpanded
                                    ? "chevron.down" : "chevron.right"
                            )
                            .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        if isThinkingExpanded {
                            reasoningText(reasoning)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                if !content.isEmpty {
                    Markdown(content)
                        .markdownTheme(.gitHub)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func reasoningText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .italic()
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .textSelection(.enabled)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

}
