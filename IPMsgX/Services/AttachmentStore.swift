// IPMsgX/Services/AttachmentStore.swift
// Manages sent file attachments available for download

import Foundation
import os

private let logger = Logger(subsystem: "com.ipmsgx", category: "AttachmentStore")

private let attachmentTimeout: TimeInterval = 24 * 60 * 60 // 24 hours

struct SendAttachmentInfo: Sendable, Identifiable {
    let id = UUID()
    let packetNo: Int
    let fileID: Int
    let path: URL
    let createdAt: Date
    var remainingUsers: Set<UserIdentifier>

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > attachmentTimeout
    }
}

actor AttachmentStore {
    private var attachments: [SendAttachmentInfo] = []
    private var nextFileID: Int = 0

    func addAttachment(packetNo: Int, path: URL, users: Set<UserIdentifier>) -> Int {
        let fileID = nextFileID
        nextFileID += 1

        let attachment = SendAttachmentInfo(
            packetNo: packetNo,
            fileID: fileID,
            path: path,
            createdAt: Date(),
            remainingUsers: users
        )
        attachments.append(attachment)
        logger.info("Added attachment: \(path.lastPathComponent) (pkt=\(packetNo), fid=\(fileID))")
        return fileID
    }

    func findAttachment(packetNo: Int, fileID: Int) -> SendAttachmentInfo? {
        attachments.first { $0.packetNo == packetNo && $0.fileID == fileID && !$0.isExpired }
    }

    func removeUser(_ userId: UserIdentifier, packetNo: Int) {
        for i in attachments.indices {
            if attachments[i].packetNo == packetNo {
                attachments[i].remainingUsers.remove(userId)
            }
        }
        // Clean up attachments with no remaining users
        attachments.removeAll { $0.remainingUsers.isEmpty }
    }

    func removeUser(_ userId: UserIdentifier) {
        for i in attachments.indices {
            attachments[i].remainingUsers.remove(userId)
        }
        attachments.removeAll { $0.remainingUsers.isEmpty }
    }

    func removeExpired() {
        let removed = attachments.filter(\.isExpired).count
        attachments.removeAll(where: \.isExpired)
        if removed > 0 {
            logger.info("Removed \(removed) expired attachments")
        }
    }

    func allAttachments() -> [SendAttachmentInfo] {
        attachments.filter { !$0.isExpired }
    }
}
