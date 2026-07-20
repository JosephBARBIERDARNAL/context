import AppKit
import SwiftUI

struct ComposerView: View {
    @Environment(AppState.self) private var state

    private var canSend: Bool {
        !state.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        @Bindable var state = state
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topLeading) {
                ComposerTextEditor(
                    text: $state.composerDraft,
                    accessibilityLabel: "Message \(state.selectedModel)",
                    focusRequest: state.composerFocusRequest,
                    onSubmit: send,
                    onEscape: {
                        state.sidebarFocusRequest += 1
                    })

                if state.composerDraft.isEmpty {
                    Text("Message \(state.selectedModel)…")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72)
            .padding(.leading, 16)
            .padding(.vertical, 11)

            Button(action: primaryAction) {
                Image(systemName: state.isStreaming ? "stop.fill" : "arrow.up")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .disabled(!state.isStreaming && !canSend)
            .padding(6)
            .help(state.isStreaming ? "Stop generating" : "Send")
        }
        .background(.background, in: .rect(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.separator.opacity(0.7), lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func primaryAction() {
        if state.isStreaming {
            state.cancelStreaming()
        } else {
            send()
        }
    }

    private func send() {
        guard canSend, !state.isStreaming else { return }
        let text = state.composerDraft
        if state.send(text) {
            state.composerDraft = ""
        }
    }
}

private struct ComposerTextEditor: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    @Binding var text: String

    let accessibilityLabel: String
    let focusRequest: Int
    let onSubmit: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: NSViewRepresentableContext<ComposerTextEditor>) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = ComposerNSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        textView.onSubmit = onSubmit
        textView.onEscape = onEscape
        textView.setAccessibilityLabel(accessibilityLabel)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(
        _ scrollView: NSScrollView,
        context: NSViewRepresentableContext<ComposerTextEditor>
    ) {
        guard let textView = scrollView.documentView as? ComposerNSTextView else { return }

        context.coordinator.parent = self
        textView.onSubmit = onSubmit
        textView.onEscape = onEscape
        textView.setAccessibilityLabel(accessibilityLabel)

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(
                NSRange(
                    location: min(selection.location, text.utf16.count),
                    length: 0))
        }

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextEditor
        weak var textView: NSTextView?
        var lastFocusRequest: Int?

        init(parent: ComposerTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private final class ComposerNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if [36, 76].contains(event.keyCode), !modifiers.contains(.shift) {
            onSubmit?()
        } else if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}
