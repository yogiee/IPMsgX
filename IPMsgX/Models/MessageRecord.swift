// IPMsgX/Models/MessageRecord.swift
// SwiftData model for persistent message history

import Foundation
import SwiftData

@Model
final class MessageRecord {
    var packetNo: Int
    var direction: MessageDirection
    var date: Date
    var peerUserName: String
    var peerHostName: String
    var peerIPAddress: String
    var messageBody: String
    var isSealed: Bool
    var isLocked: Bool
    var isBroadcast: Bool
    var secureLevel: Int
    var hasAttachments: Bool
    var attachmentNames: String? // Comma-separated

    init(
        packetNo: Int,
        direction: MessageDirection,
        date: Date,
        peerUserName: String,
        peerHostName: String,
        peerIPAddress: String,
        messageBody: String,
        isSealed: Bool = false,
        isLocked: Bool = false,
        isBroadcast: Bool = false,
        secureLevel: Int = 0,
        hasAttachments: Bool = false,
        attachmentNames: String? = nil
    ) {
        self.packetNo = packetNo
        self.direction = direction
        self.date = date
        self.peerUserName = peerUserName
        self.peerHostName = peerHostName
        self.peerIPAddress = peerIPAddress
        self.messageBody = messageBody
        self.isSealed = isSealed
        self.isLocked = isLocked
        self.isBroadcast = isBroadcast
        self.secureLevel = secureLevel
        self.hasAttachments = hasAttachments
        self.attachmentNames = attachmentNames
    }
}

enum MessageDirection: String, Codable {
    case sent
    case received
}
