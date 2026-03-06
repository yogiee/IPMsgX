// IPMsgX/Views/AttachmentListView.swift
// Drag-and-drop file attachment UI for compose window

import SwiftUI
import UniformTypeIdentifiers

struct AttachmentListView: View {
    @Binding var attachmentURLs: [URL]
    var onAdd: ((URL) -> Void)?

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            if attachmentURLs.isEmpty {
                dropZone
            } else {
                attachmentGrid
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                addAttachment(url)
            }
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Drop files here or click to attach")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                .foregroundStyle(isTargeted ? .blue : .secondary.opacity(0.4))
        )
        .background(isTargeted ? Color.blue.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            showFilePicker()
        }
    }

    // MARK: - Attachment Grid

    private var attachmentGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("\(attachmentURLs.count) file(s) attached", systemImage: "paperclip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showFilePicker()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .font(.caption)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(attachmentURLs.enumerated()), id: \.offset) { idx, url in
                        let index = idx
                        AttachmentChip(url: url) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                _ = attachmentURLs.remove(at: index)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func addAttachment(_ url: URL) {
        guard !attachmentURLs.contains(url) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            attachmentURLs.append(url)
        }
        onAdd?(url)
    }

    private func showFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    addAttachment(url)
                }
            }
        }
    }
}

// MARK: - Attachment Chip

private struct AttachmentChip: View {
    let url: URL
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .foregroundStyle(.blue)
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(fileSizeString)
                .foregroundStyle(.tertiary)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var iconName: String {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue { return "folder.fill" }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "tiff":
            return "photo"
        case "pdf":
            return "doc.richtext"
        case "zip", "tar", "gz", "7z":
            return "doc.zipper"
        case "txt", "rtf", "md":
            return "doc.text"
        default:
            return "doc"
        }
    }

    private var fileSizeString: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
