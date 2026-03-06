// IPMsgX/Views/ImagePreviewView.swift
// Simple image preview for downloaded attachments

import SwiftUI
import AppKit

struct ImagePreviewView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 800, maxHeight: 600)
                    .padding()
            } else {
                ContentUnavailableView(
                    "Cannot Load Image",
                    systemImage: "photo.badge.exclamationmark"
                )
            }

            Divider()

            HStack {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
