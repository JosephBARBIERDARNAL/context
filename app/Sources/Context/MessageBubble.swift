import AppKit
import SwiftUI

struct MessageBubble: View {
    let role: String
    let content: String

    @State private var hovering = false
    @State private var copied = false

    private var isUser: Bool { role == "user" }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
            HStack(alignment: .bottom) {
                if isUser { Spacer(minLength: 70) }
                Text(attributed)
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassEffect(
                        isUser ? .regular.tint(.accentColor.opacity(0.5)) : .regular,
                        in: .rect(cornerRadius: 20, style: .continuous))
                if !isUser { Spacer(minLength: 70) }
            }
            copyButton
                .opacity(hovering || copied ? 1 : 0)
        }
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .animation(.easeInOut(duration: 0.15), value: copied)
    }

    private var copyButton: some View {
        Button(action: copy) {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .help("Copy message")
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

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(content)
    }
}
