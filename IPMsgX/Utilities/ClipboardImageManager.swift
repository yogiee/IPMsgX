// IPMsgX/Utilities/ClipboardImageManager.swift
// Manages temporary storage for pasted clipboard images

import AppKit

enum ClipboardImageManager {
    static var clipboardDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("IPMsgX-clipboard", isDirectory: true)
    }

    /// Saves an image from the general pasteboard to a temp file. Returns the file URL, or nil if no image found.
    static func saveImageFromPasteboard() -> URL? {
        let pasteboard = NSPasteboard.general

        // Try PNG first, then TIFF (macOS screenshots are typically TIFF)
        var imageData: Data?
        if let png = pasteboard.data(forType: .png) {
            imageData = png
        } else if let tiff = pasteboard.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) {
            imageData = png
        }

        guard let data = imageData else { return nil }

        // Ensure directory exists
        let dir = clipboardDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let fileURL = dir.appendingPathComponent("clipboard-\(timestamp).png")

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    /// Deletes clipboard images older than 24 hours
    static func cleanupOldFiles() {
        let dir = clipboardDirectory
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for file in files {
            if let created = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
               created < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }
}
