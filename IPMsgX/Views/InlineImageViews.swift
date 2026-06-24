// IPMsgX/Views/InlineImageViews.swift
// AppKit-backed views for inline images: animated (GIF) display + QuickLook preview.

import SwiftUI
import AppKit
import Quartz

/// Displays an image and animates it (GIF/APNG) — SwiftUI's Image shows only the first frame.
struct AnimatedImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.image = NSImage(contentsOf: url)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.animates = true
        if nsView.image == nil {
            nsView.image = NSImage(contentsOf: url)
        }
    }
}

/// Embeddable QuickLook preview (zoom, full-resolution, animation) for a single file.
struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as NSURL
    }
}

/// Identifiable URL wrapper for presenting a QuickLook sheet via `.sheet(item:)`.
struct QuickLookItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Sheet hosting a large QuickLook preview of an inline image.
struct QuickLookSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            QuickLookView(url: url)
                .frame(minWidth: 480, minHeight: 360)
            Divider()
            HStack {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(8)
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
