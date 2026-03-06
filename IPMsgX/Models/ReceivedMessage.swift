// IPMsgX/Models/ReceivedMessage.swift
// Received message value type — ported from RecvMessage.h

import Foundation

struct ReceivedMessage: Identifiable, Sendable {
    let id = UUID()
    let packetNo: Int
    let receiveDate: Date
    let fromUser: UserInfo
    let message: String
    let secureLevel: Int
    let doubt: Bool
    let isSealed: Bool
    let isLocked: Bool
    let isMulticast: Bool
    let isBroadcast: Bool
    let isAbsenceReply: Bool
    let attachments: [IPMsgAttachmentParser.ParsedAttachment]

    var hasAttachments: Bool {
        !attachments.isEmpty
    }

    var secureLevelDescription: String {
        switch secureLevel {
        case 4: return "RSA2048+AES256+SHA256"
        case 3: return "RSA2048+AES256+SHA1"
        case 2: return "RSA2048+AES256"
        case 1: return "RSA1024+Blowfish128"
        default: return "None"
        }
    }
}
