import SwiftUI

struct MessageBubble: View {
    let role: String
    let content: String

    private var isUser: Bool { role == "user" }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer(minLength: 60) }
            Text(attributed)
                .textSelection(.enabled)
                .padding(.horizontal, isUser ? 14 : 4)
                .padding(.vertical, isUser ? 9 : 0)
                .background {
                    if isUser {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.tint.opacity(0.18))
                            .glassEffect(
                                .regular,
                                in: .rect(cornerRadius: 18, style: .continuous))
                    }
                }
            if !isUser { Spacer(minLength: 60) }
        }
    }

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(content)
    }
}
