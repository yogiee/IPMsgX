// IPMsgX/Services/LogService.swift
// File-based logging matching the original IP Messenger log format

import Foundation
import os

private let logger = Logger(subsystem: "com.ipmsgx", category: "LogService")

actor LogService {
    static let shared = LogService()

    private let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd HH:mm:ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    // MARK: - Public API

    func logReceivedMessage(_ msg: ReceivedMessage) {
        let settings = SettingsService.shared
        let entry = formatReceived(msg)

        if settings.standardLogEnabled {
            append(entry, toFile: settings.standardLogFile)
        }
        if settings.alternateLogEnabled {
            append(entry, toFile: settings.alternateLogFile)
        }
    }

    func logSentMessage(_ msg: SentMessage) {
        let settings = SettingsService.shared
        let entry = formatSent(msg)

        if settings.standardLogEnabled {
            append(entry, toFile: settings.standardLogFile)
        }
        if settings.alternateLogEnabled {
            append(entry, toFile: settings.alternateLogFile)
        }
    }

    // MARK: - Formatting (matches original IP Messenger log format)

    private func formatReceived(_ msg: ReceivedMessage) -> String {
        var lines: [String] = []
        lines.append("=====================================")
        lines.append(" From: \(msg.fromUser.displayName) (\(msg.fromUser.logOnName)@\(msg.fromUser.hostName)/\(msg.fromUser.ipAddress))")
        lines.append(" Date: \(dateFormatter.string(from: msg.receiveDate))")

        var flags: [String] = []
        if msg.isSealed { flags.append("Sealed") }
        if msg.isLocked { flags.append("Locked") }
        if msg.isBroadcast { flags.append("Broadcast") }
        if msg.secureLevel > 0 { flags.append("Encrypted(\(msg.secureLevelDescription))") }
        if !flags.isEmpty {
            lines.append(" Flags: \(flags.joined(separator: ", "))")
        }

        lines.append("-------------------------------------")
        lines.append(msg.message)

        if msg.hasAttachments {
            lines.append("-------------------------------------")
            lines.append(" Attachments:")
            for attach in msg.attachments {
                lines.append("   \(attach.fileName) (\(attach.fileSize) bytes)")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func formatSent(_ msg: SentMessage) -> String {
        var lines: [String] = []
        lines.append("=====================================")
        let recipients = msg.toUsers.map { "\($0.displayName)" }.joined(separator: ", ")
        lines.append(" To: \(recipients)")
        lines.append(" Date: \(dateFormatter.string(from: msg.sendDate))")

        var flags: [String] = []
        if msg.isSealed { flags.append("Sealed") }
        if msg.isLocked { flags.append("Locked") }
        if !flags.isEmpty {
            lines.append(" Flags: \(flags.joined(separator: ", "))")
        }

        lines.append("-------------------------------------")
        lines.append(msg.message)

        if msg.hasAttachments {
            lines.append("-------------------------------------")
            lines.append(" Attachments:")
            for url in msg.attachmentURLs {
                lines.append("   \(url.lastPathComponent)")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - File I/O

    private func append(_ text: String, toFile path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        // Ensure parent directory exists
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = text.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            try? text.write(toFile: expandedPath, atomically: true, encoding: .utf8)
        }
    }
}
