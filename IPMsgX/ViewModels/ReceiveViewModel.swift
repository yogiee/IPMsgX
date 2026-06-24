// IPMsgX/ViewModels/ReceiveViewModel.swift
// View model for received message window

import SwiftUI
import AppKit

@Observable
@MainActor
final class ReceiveViewModel {
    let message: ReceivedMessage
    var isSealOpened: Bool
    var replyText: String = ""
    var showReplyField: Bool = false

    /// Whether to quote the original message in the reply. Defaults to the user's setting
    /// but can be toggled per-reply (mirrors the original's Quote checkbox).
    var quoteEnabled: Bool = SettingsService.shared.quoteCheckDefault

    // Locked-message password prompt
    var showPasswordPrompt: Bool = false
    var passwordInput: String = ""
    var passwordError: Bool = false

    var downloadProgress: DownloadProgress?
    var isDownloading: Bool = false
    var downloadError: String?
    var downloadedFileURL: URL?
    var showImagePreview: Bool = false

    // Inline (clipboard-position) images — loaded to a temp dir, shown inline & animated,
    // never persisted. Cleaned up when the window closes.
    var inlineImageURLs: [Int: URL] = [:]
    var inlineImageSizes: [Int: CGSize] = [:]
    var inlineLoading: Set<Int> = []
    var quickLookItem: QuickLookItem?

    private let appState: AppState
    private var activeDownloader: FileDownloader?

    init(message: ReceivedMessage, appState: AppState) {
        self.message = message
        self.appState = appState
        self.isSealOpened = !message.isSealed || appState.isSealOpened(packetNo: message.packetNo)
    }

    var senderDisplayName: String {
        message.fromUser.displayName
    }

    var senderInfo: String {
        var info = "\(message.fromUser.logOnName)@\(message.fromUser.hostName)"
        if let group = message.fromUser.groupName, !group.isEmpty {
            info += " [\(group)]"
        }
        return info
    }

    var dateString: String {
        message.receiveDate.formatted(date: .abbreviated, time: .standard)
    }

    var hasAttachments: Bool {
        message.hasAttachments
    }

    /// Inline images (sent with a clipboard position) — shown inline, not as download buttons.
    var inlineImages: [IPMsgAttachmentParser.ParsedAttachment] {
        message.attachments.filter { $0.clipboardPosition != nil }
    }

    /// Regular file attachments (no clipboard position) — shown as download buttons.
    var fileAttachments: [IPMsgAttachmentParser.ParsedAttachment] {
        message.attachments.filter { $0.clipboardPosition == nil }
    }

    var hasFileAttachments: Bool { !fileAttachments.isEmpty }

    var securityBadge: String? {
        if message.secureLevel > 0 {
            return message.secureLevelDescription
        }
        return nil
    }

    /// A locked message requires the receiver's own password to open — but only if the
    /// receiver actually has a password set (otherwise there's nothing to validate against).
    var requiresPassword: Bool {
        message.isLocked && !SettingsService.shared.password.isEmpty
    }

    /// Called when the user clicks the seal cover. Locked messages prompt for the password;
    /// otherwise the seal opens immediately.
    func attemptOpenSeal() {
        guard !isSealOpened else { return }
        if requiresPassword {
            passwordInput = ""
            passwordError = false
            showPasswordPrompt = true
        } else {
            Task { await revealSeal() }
        }
    }

    /// Validate the entered password against the receiver's stored password.
    func submitPassword() {
        if passwordInput == SettingsService.shared.password {
            showPasswordPrompt = false
            passwordInput = ""
            Task { await revealSeal() }
        } else {
            passwordError = true
        }
    }

    /// Reveal the sealed content and notify the sender that the seal was opened.
    private func revealSeal() async {
        isSealOpened = true
        appState.markSealOpened(packetNo: message.packetNo)
        await appState.openSeal(message: message)
    }

    func reply() async {
        guard !replyText.isEmpty else { return }

        let quotePrefix = SettingsService.shared.quoteString
        var replyMessage = replyText
        if quoteEnabled {
            let quoted = message.message.components(separatedBy: "\n")
                .map { quotePrefix + $0 }
                .joined(separator: "\n")
            replyMessage = quoted + "\n\n" + replyText
        }

        _ = await appState.sendMessage(
            to: [message.fromUser],
            message: replyMessage,
            isSealed: false,
            isLocked: false
        )

        replyText = ""
        showReplyField = false
    }

    // MARK: - Inline images (ephemeral)

    private var inlineTempDir: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("IPMsgX-inline", isDirectory: true)
            .appendingPathComponent("\(message.packetNo)", isDirectory: true)
    }

    /// Download each inline image into a temp dir (once), for inline display only.
    func loadInlineImages() async {
        guard !inlineImages.isEmpty else { return }
        let dir = inlineTempDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for img in inlineImages {
            guard inlineImageURLs[img.fileID] == nil, !inlineLoading.contains(img.fileID) else { continue }
            inlineLoading.insert(img.fileID)
            let dest = dir.appendingPathComponent(img.fileName)
            let downloader = FileDownloader()
            let ok = await downloader.downloadFile(
                from: message.fromUser,
                packetNo: message.packetNo,
                fileID: img.fileID,
                fileName: img.fileName,
                fileSize: img.fileSize,
                savePath: dir,
                selfLogOnName: HostInfo.logOnUser,
                selfHostName: HostInfo.hostName
            )
            inlineLoading.remove(img.fileID)
            if ok, let image = NSImage(contentsOf: dest) {
                inlineImageURLs[img.fileID] = dest
                inlineImageSizes[img.fileID] = Self.displaySize(for: image.size)
            }
        }
    }

    /// Cap the longest side so inline images sit nicely in the message body.
    private static func displaySize(for pixelSize: CGSize) -> CGSize {
        let maxDim: CGFloat = 360
        guard pixelSize.width > 0, pixelSize.height > 0 else { return CGSize(width: maxDim, height: maxDim) }
        let scale = min(1, maxDim / max(pixelSize.width, pixelSize.height))
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }

    func showQuickLook(fileID: Int) {
        if let url = inlineImageURLs[fileID] {
            quickLookItem = QuickLookItem(url: url)
        }
    }

    /// Copy an inline image out of the temp dir to the user's download location.
    func saveInline(fileID: Int) {
        guard let src = inlineImageURLs[fileID] else { return }
        let settings = SettingsService.shared
        let fm = FileManager.default
        if settings.alwaysPromptSaveLocation {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = src.lastPathComponent
            panel.directoryURL = settings.downloadLocation
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let dst = panel.url else { return }
            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: src, to: dst)
        } else {
            let name = Self.uniqueFileName(for: src.lastPathComponent, in: settings.downloadLocation)
            try? fm.copyItem(at: src, to: settings.downloadLocation.appendingPathComponent(name))
        }
    }

    /// Delete the temp dir — inline images are one-time and don't persist.
    func cleanupInlineTemp() {
        try? FileManager.default.removeItem(at: inlineTempDir)
    }

    func downloadAttachment(_ attachment: IPMsgAttachmentParser.ParsedAttachment) {
        let settings = SettingsService.shared
        let saveDir: URL
        let fileName: String

        if settings.alwaysPromptSaveLocation {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = attachment.fileName
            panel.directoryURL = settings.downloadLocation
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let saveURL = panel.url else { return }
            saveDir = saveURL.deletingLastPathComponent()
            fileName = saveURL.lastPathComponent
        } else {
            // Save straight to the configured folder, avoiding overwrites.
            saveDir = settings.downloadLocation
            fileName = Self.uniqueFileName(for: attachment.fileName, in: saveDir)
        }

        isDownloading = true
        downloadError = nil
        downloadProgress = nil

        let downloader = FileDownloader()
        activeDownloader = downloader

        Task {
            // Monitor progress
            let progressTask = Task {
                for await progress in downloader.progress {
                    self.downloadProgress = progress
                    if progress.isComplete {
                        break
                    }
                }
            }

            let success = await downloader.downloadFile(
                from: message.fromUser,
                packetNo: message.packetNo,
                fileID: attachment.fileID,
                fileName: fileName,
                fileSize: attachment.fileSize,
                savePath: saveDir,
                selfLogOnName: HostInfo.logOnUser,
                selfHostName: HostInfo.hostName
            )

            await progressTask.value

            isDownloading = false
            activeDownloader = nil

            if success {
                downloadedFileURL = saveDir.appendingPathComponent(fileName)
                if isImageFile(fileName) {
                    showImagePreview = true
                }
            } else {
                downloadError = "Download failed"
            }
        }
    }

    func cancelDownload() {
        Task {
            await activeDownloader?.cancel()
        }
        isDownloading = false
        activeDownloader = nil
    }

    private func isImageFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "webp"].contains(ext)
    }

    /// Returns a non-colliding file name in `dir` by appending " (1)", " (2)", … if needed.
    static func uniqueFileName(for name: String, in dir: URL) -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.appendingPathComponent(name).path) else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var n = 1
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            if !fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
                return candidate
            }
            n += 1
        }
    }

    static func formattedSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
