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
                    .background(
                        isUser
                            ? Color.accentColor.opacity(0.22)
                            : Color.secondary.opacity(0.08),
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
            selectablePlainText(content, size: 18)
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
                    if isStreaming {
                        selectablePlainText(content, size: 18)
                    } else {
                        Markdown(MarkdownContentCache.shared.content(for: content))
                            .markdownTheme(.gitHub)
                            .markdownImageProvider(DisabledMarkdownImageProvider())
                            .markdownInlineImageProvider(DisabledMarkdownInlineImageProvider())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func selectablePlainText(
        _ text: String,
        size: CGFloat,
        italic: Bool = false,
        secondary: Bool = false,
        lineSpacing: CGFloat = 4
    ) -> some View {
        if text.utf8.count >= 1_024 {
            SelectableTextView(
                text: text,
                size: size,
                italic: italic,
                secondary: secondary,
                lineSpacing: lineSpacing)
        } else {
            Text(text)
                .font(.system(size: size))
                .italic(italic)
                .foregroundStyle(secondary ? .secondary : .primary)
                .lineSpacing(lineSpacing)
                .textSelection(.enabled)
        }
    }

    private func reasoningText(_ text: String) -> some View {
        selectablePlainText(
            text,
            size: 15,
            italic: true,
            secondary: true,
            lineSpacing: 2)
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

private struct SelectableTextView: NSViewRepresentable {
    typealias NSViewType = CachedTextView

    let text: String
    let size: CGFloat
    let italic: Bool
    let secondary: Bool
    let lineSpacing: CGFloat

    func makeNSView(context: NSViewRepresentableContext<SelectableTextView>) -> CachedTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(containerSize: .zero)
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        let textView = CachedTextView(frame: .zero, textContainer: container)
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = .zero
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        update(textView)
        return textView
    }

    func updateNSView(
        _ textView: CachedTextView,
        context: NSViewRepresentableContext<SelectableTextView>
    ) {
        update(textView)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textView: CachedTextView,
        context: NSViewRepresentableContext<SelectableTextView>
    ) -> CGSize? {
        guard let width = proposal.width, width > 0,
            let container = textView.textContainer,
            let layoutManager = textView.layoutManager
        else { return nil }

        if abs(textView.measuredWidth - width) < 0.5, textView.measuredHeight > 0 {
            return CGSize(width: width, height: textView.measuredHeight)
        }

        if abs(container.containerSize.width - width) >= 0.5 {
            container.containerSize = NSSize(
                width: width,
                height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: container)
        let height = ceil(layoutManager.usedRect(for: container).height)
        textView.measuredWidth = width
        textView.measuredHeight = max(height, size)
        return CGSize(width: width, height: textView.measuredHeight)
    }

    private func update(_ textView: CachedTextView) {
        guard textView.source != text else { return }

        let baseFont = NSFont.systemFont(ofSize: size)
        let font =
            italic
            ? NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            : baseFont
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = lineSpacing
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: secondary ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]

        textView.source = text
        textView.measuredWidth = -1
        textView.measuredHeight = 0
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: attributes))
        textView.invalidateIntrinsicContentSize()
    }
}

private final class CachedTextView: NSTextView {
    var source = ""
    var measuredWidth: CGFloat = -1
    var measuredHeight: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

struct DisabledMarkdownImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        EmptyView()
    }
}

struct DisabledMarkdownInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        throw MarkdownImageLoadingError.disabled
    }
}

enum MarkdownImageLoadingError: Error {
    case disabled
}

@MainActor
private final class MarkdownContentCache {
    static let shared = MarkdownContentCache()

    private let cache = NSCache<NSString, CachedMarkdownContent>()

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 8 * 1_024 * 1_024
    }

    func content(for source: String) -> MarkdownContent {
        let key = source as NSString
        if let cached = cache.object(forKey: key) {
            return cached.content
        }

        let parsed = MarkdownContent(source)
        cache.setObject(
            CachedMarkdownContent(parsed),
            forKey: key,
            cost: source.utf8.count)
        return parsed
    }
}

private final class CachedMarkdownContent: NSObject {
    let content: MarkdownContent

    init(_ content: MarkdownContent) {
        self.content = content
    }
}
