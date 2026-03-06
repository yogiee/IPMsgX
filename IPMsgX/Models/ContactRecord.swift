// IPMsgX/Models/ContactRecord.swift
// SwiftData model for contact history

import Foundation
import SwiftData

@Model
final class ContactRecord {
    var logOnName: String
    var hostName: String
    var lastSeenIP: String
    var displayName: String
    var groupName: String?
    var lastSeen: Date
    var favorite: Bool

    init(
        logOnName: String,
        hostName: String,
        lastSeenIP: String,
        displayName: String,
        groupName: String? = nil,
        lastSeen: Date = Date(),
        favorite: Bool = false
    ) {
        self.logOnName = logOnName
        self.hostName = hostName
        self.lastSeenIP = lastSeenIP
        self.displayName = displayName
        self.groupName = groupName
        self.lastSeen = lastSeen
        self.favorite = favorite
    }
}
