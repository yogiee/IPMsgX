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

    func downloadAttachment(_ attachment: IPMsgAttachmentParser.ParsedAttachment) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.fileName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        let saveDir = saveURL.deletingLastPathComponent()
        let fileName = saveURL.lastPathComponent

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

    static func formattedSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
