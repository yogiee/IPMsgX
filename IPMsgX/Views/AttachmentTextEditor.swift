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
    var onPasteImage: ((Data, String) -> Void)? = nil
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
        applyTypography(to: textView)
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

    private func applyTypography(to textView: AttachDropTextView) {
        let settings = SettingsService.shared
        let font = settings.messageNSFont
        textView.font = font
        // Use the dynamic label color so text stays legible in both light and dark mode.
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.caretHeight = font.capHeight - font.descender

        // A line height above the font's natural height places all the extra
        // space ABOVE the glyphs (text sits at the bottom of the cell). Raise
        // the baseline by half the extra space to center the glyphs.
        let naturalLH = NSLayoutManager().defaultLineHeight(for: font)
        let lh = ceil(naturalLH * CGFloat(settings.messageLineHeight))
        // Divisor below the geometric 2 raises the glyphs slightly above true
        // center — user-tuned against the clamped caret; don't "correct" it.
        let baselineOffset = (lh - naturalLH) / 1.5
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lh
        style.maximumLineHeight = lh
        textView.defaultParagraphStyle = style

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: style,
            .foregroundColor: NSColor.labelColor,
            .baselineOffset: baselineOffset
        ]
        textView.typingAttributes = attributes
        if let storage = textView.textStorage, storage.length > 0 {
            storage.beginEditing()
            storage.addAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? AttachDropTextView else { return }
        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            let len = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
        }
        // After the string update so programmatically-set text is restyled too.
        applyTypography(to: textView)
        context.coordinator.parent = self
        textView.onFileDrop = { urls in onFileDrop(urls) }
        textView.onPasteImage = onPasteImage
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
    var onPasteImage: ((Data, String) -> Void)?
    var onIsTargetedChange: ((Bool) -> Void)?

    /// Caret height, set by applyTypography. AppKit sizes the insertion
    /// indicator to the full line fragment (line height × multiple); the clamp
    /// shrinks it to visual text height (cap→descender), centered vertically
    /// in the fragment and nudged 1pt right so it doesn't touch glyph ink.
    var caretHeight: CGFloat = 0

    // Since macOS 14 the caret is an AppKit-managed NSTextInsertionIndicator
    // subview with no size API (drawInsertionPoint is no longer called), so we
    // re-clamp its frame whenever AppKit positions it.
    private var caretObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var isClampingCaret = false

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard subview is NSTextInsertionIndicator else { return }
        caretObservations[ObjectIdentifier(subview)] = subview.observe(\.frame) { [weak self] indicator, _ in
            MainActor.assumeIsolated {
                self?.clampCaret(indicator)
            }
        }
        clampCaret(subview)
    }

    override func willRemoveSubview(_ subview: NSView) {
        caretObservations.removeValue(forKey: ObjectIdentifier(subview))
        super.willRemoveSubview(subview)
    }

    private func clampCaret(_ indicator: NSView) {
        guard !isClampingCaret, caretHeight > 0 else { return }
        let f = indicator.frame
        guard f.height > caretHeight + 0.5 else { return }
        isClampingCaret = true
        indicator.frame = NSRect(x: f.minX + 1,
                                 y: f.minY + (f.height - caretHeight) / 2,
                                 width: f.width, height: caretHeight)
        isClampingCaret = false
    }

    /// Intercept paste: if the clipboard holds an image (and not text), route it to the
    /// inline-image handler instead of inserting it as text.
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let hasText = (pb.string(forType: .string)?.isEmpty == false)
        if !hasText {
            if let data = pb.data(forType: .png) {
                onPasteImage?(data, "png")
                return
            }
            if let tiff = pb.data(forType: .tiff),
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                onPasteImage?(png, "png")
                return
            }
        }
        super.paste(sender)
    }

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
