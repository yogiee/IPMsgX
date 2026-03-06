// IPMsgX/Models/SentMessage.swift
// Sent message value type — ported from SendMessage.h

import Foundation

struct SentMessage: Identifiable, Sendable {
    let id = UUID()
    let packetNo: Int
    let sendDate: Date
    let message: String
    let toUsers: [UserInfo]
    let isSealed: Bool
    let isLocked: Bool
    let attachmentURLs: [URL]

    var hasAttachments: Bool {
        !attachmentURLs.isEmpty
    }
}
