// IPMsgX/Views/AttachmentTextEditor.swift
// NSViewRepresentable text editor that routes file drops to an attachment
// callback instead of inserting the path as text (default NSTextView behavior).

import SwiftUI
import AppKit

struct AttachmentTextEditor: NSViewRepresentable {
    @Binding var text: String
    var cmdEnterToSend: Bool
    var onEnterSend: () -> Void
    var onFileDrop: ([URL]) -> Void
    var isDropTargeted: Binding<Bool>

    func makeNSView(context: Context) -> NSScrollView {
        let textView = AttachDropTextView()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isRichText = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? AttachDropTextView else { return }
        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            let len = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
        }
        context.coordinator.parent = self
        textView.onFileDrop = { urls in onFileDrop(urls) }
        textView.onIsTargetedChange = { isDropTargeted.wrappedValue = $0 }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AttachmentTextEditor
        weak var textView: NSTextView?

        init(_ parent: AttachmentTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        /// Handle Return/⌘Return for send-on-enter, leaving Shift+Return
        /// to NSTextView's default newline insertion.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let flags = NSApp.currentEvent?.modifierFlags
                .intersection(.deviceIndependentFlagsMask) ?? []
            let isPlain = flags.intersection([.command, .shift, .control, .option]).isEmpty
            let isCmd   = flags.contains(.command)
            if (!parent.cmdEnterToSend && isPlain) || isCmd {
                parent.onEnterSend()
                return true  // consumed — NSTextView won't insert a newline
            }
            return false  // let NSTextView handle it (inserts \n naturally)
        }
    }
}

// MARK: - Custom NSTextView

private class AttachDropTextView: NSTextView {
    var onFileDrop: (([URL]) -> Void)?
    var onIsTargetedChange: ((Bool) -> Void)?

    private func hasFileURLs(_ info: NSDraggingInfo) -> Bool {
        info.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasFileURLs(sender) {
            onIsTargetedChange?(true)
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasFileURLs(sender) { return .copy }
        return super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onIsTargetedChange?(false)
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if hasFileURLs(sender) { return true }
        return super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onIsTargetedChange?(false)
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            onFileDrop?(urls)
            return true
        }
        return super.performDragOperation(sender)
    }
}
