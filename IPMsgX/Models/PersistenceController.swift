// IPMsgX/Models/PersistenceController.swift
// SwiftData ModelContainer setup and convenience queries

import Foundation
import SwiftData

enum PersistenceController {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            MessageRecord.self,
            ContactRecord.self,
        ])

        // Use an explicit, app-namespaced store path. The SwiftData default
        // (~/Library/Application Support/default.store) is shared and unnamespaced for a
        // non-sandboxed app, so it can collide with other apps or get reset — which is what
        // wiped earlier history. An isolated path under Application Support/IPMsgX/ is stable.
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("IPMsgX", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("IPMsgX.store")

        migrateLegacyStoreIfNeeded(to: storeURL, legacy: appSupport.appendingPathComponent("default.store"))

        let config = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// One-time migration: if the namespaced store doesn't exist yet but the legacy shared
    /// default.store does, copy it (plus its SQLite WAL/SHM sidecars) so existing history
    /// carries over. Copy rather than move, leaving the legacy file intact as a fallback.
    private static func migrateLegacyStoreIfNeeded(to storeURL: URL, legacy: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: storeURL.path), fm.fileExists(atPath: legacy.path) else { return }
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: legacy.path + suffix)
            let dst = URL(fileURLWithPath: storeURL.path + suffix)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }
    }

    @MainActor
    static func saveReceivedMessage(_ msg: ReceivedMessage) {
        let context = sharedModelContainer.mainContext

        // Inline images are ephemeral — never persist their bytes. Store only a text reference
        // like <inline-image-gif> in the body. Regular file attachments are listed as names.
        let inline = msg.attachments.filter { $0.clipboardPosition != nil }
        let files = msg.attachments.filter { $0.clipboardPosition == nil }

        var body = msg.message
        if !inline.isEmpty {
            let placeholders = inline.map { att -> String in
                let ext = (att.fileName as NSString).pathExtension.lowercased()
                return ext.isEmpty ? "<inline-image>" : "<inline-image-\(ext)>"
            }.joined(separator: " ")
            body = body.isEmpty ? placeholders : body + "\n" + placeholders
        }

        let attachNames = files.map(\.fileName).joined(separator: ", ")
        let record = MessageRecord(
            packetNo: msg.packetNo,
            direction: .received,
            date: msg.receiveDate,
            peerUserName: msg.fromUser.displayName,
            peerHostName: msg.fromUser.hostName,
            peerIPAddress: msg.fromUser.ipAddress,
            messageBody: body,
            isSealed: msg.isSealed,
            isLocked: msg.isLocked,
            isBroadcast: msg.isBroadcast,
            secureLevel: msg.secureLevel,
            hasAttachments: !files.isEmpty,
            attachmentNames: attachNames.isEmpty ? nil : attachNames
        )
        context.insert(record)
        try? context.save()
    }

    @MainActor
    static func saveSentMessage(_ msg: SentMessage) {
        let context = sharedModelContainer.mainContext

        // Inline images are ephemeral — store only a <inline-image-…> reference in the body.
        var body = msg.message
        if !msg.inlineImageURLs.isEmpty {
            let placeholders = msg.inlineImageURLs.map { url -> String in
                let ext = url.pathExtension.lowercased()
                return ext.isEmpty ? "<inline-image>" : "<inline-image-\(ext)>"
            }.joined(separator: " ")
            body = body.isEmpty ? placeholders : body + "\n" + placeholders
        }
        let attachNames = msg.attachmentURLs.map(\.lastPathComponent).joined(separator: ", ")

        for user in msg.toUsers {
            let record = MessageRecord(
                packetNo: msg.packetNo,
                direction: .sent,
                date: msg.sendDate,
                peerUserName: user.displayName,
                peerHostName: user.hostName,
                peerIPAddress: user.ipAddress,
                messageBody: body,
                isSealed: msg.isSealed,
                isLocked: msg.isLocked,
                hasAttachments: msg.hasAttachments,
                attachmentNames: attachNames.isEmpty ? nil : attachNames
            )
            context.insert(record)
        }
        try? context.save()
    }

    @MainActor
    static func updateContact(_ user: UserInfo) {
        let context = sharedModelContainer.mainContext
        let logOn = user.logOnName
        let host = user.hostName
        let descriptor = FetchDescriptor<ContactRecord>(
            predicate: #Predicate { $0.logOnName == logOn && $0.hostName == host }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.lastSeenIP = user.ipAddress
            existing.displayName = user.displayName
            existing.groupName = user.groupName
            existing.lastSeen = Date()
        } else {
            let contact = ContactRecord(
                logOnName: user.logOnName,
                hostName: user.hostName,
                lastSeenIP: user.ipAddress,
                displayName: user.displayName,
                groupName: user.groupName
            )
            context.insert(contact)
        }
        try? context.save()
    }
}
