// IPMsgX/Views/DownloadProgressView.swift
// File download progress sheet

import SwiftUI

struct DownloadProgressView: View {
    let fileName: String
    let progress: Double
    let downloadedSize: String
    let totalSize: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Downloading")
                .font(.headline)

            Text(fileName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ProgressView(value: progress)
                .progressViewStyle(.linear)

            HStack {
                Text(downloadedSize)
                Spacer()
                Text(totalSize)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Cancel") {
                onCancel()
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}
