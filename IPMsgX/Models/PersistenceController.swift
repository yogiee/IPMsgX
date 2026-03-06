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
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @MainActor
    static func saveReceivedMessage(_ msg: ReceivedMessage) {
        let context = sharedModelContainer.mainContext
        let attachNames = msg.attachments.map(\.fileName).joined(separator: ", ")
        let record = MessageRecord(
            packetNo: msg.packetNo,
            direction: .received,
            date: msg.receiveDate,
            peerUserName: msg.fromUser.displayName,
            peerHostName: msg.fromUser.hostName,
            peerIPAddress: msg.fromUser.ipAddress,
            messageBody: msg.message,
            isSealed: msg.isSealed,
            isLocked: msg.isLocked,
            isBroadcast: msg.isBroadcast,
            secureLevel: msg.secureLevel,
            hasAttachments: msg.hasAttachments,
            attachmentNames: attachNames.isEmpty ? nil : attachNames
        )
        context.insert(record)
        try? context.save()
    }

    @MainActor
    static func saveSentMessage(_ msg: SentMessage) {
        let context = sharedModelContainer.mainContext
        for user in msg.toUsers {
            let record = MessageRecord(
                packetNo: msg.packetNo,
                direction: .sent,
                date: msg.sendDate,
                peerUserName: user.displayName,
                peerHostName: user.hostName,
                peerIPAddress: user.ipAddress,
                messageBody: msg.message,
                isSealed: msg.isSealed,
                isLocked: msg.isLocked,
                hasAttachments: msg.hasAttachments,
                attachmentNames: msg.attachmentURLs.map(\.lastPathComponent).joined(separator: ", ")
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
