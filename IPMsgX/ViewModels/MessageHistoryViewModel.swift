// IPMsgX/ViewModels/MessageHistoryViewModel.swift
// View model for message history search and filtering

import SwiftUI
import SwiftData

@Observable
@MainActor
final class MessageHistoryViewModel {
    var searchText: String = ""
    var filterDirection: MessageDirection?
    var filterStartDate: Date?
    var filterEndDate: Date?
    var selectedPeer: String?

    /// Build conversation list from all messages, grouped by peer
    func conversations(from messages: [MessageRecord]) -> [ConversationInfo] {
        var map: [String: ConversationInfo] = [:]

        for record in messages {
            let key = record.peerUserName
            if var conv = map[key] {
                conv.messageCount += 1
                if record.date > conv.lastDate {
                    conv.lastDate = record.date
                    conv.lastMessagePreview = record.messageBody
                    conv.lastDirection = record.direction
                }
                if record.direction == .received { conv.receivedCount += 1 }
                else { conv.sentCount += 1 }
                map[key] = conv
            } else {
                map[key] = ConversationInfo(
                    peerName: key,
                    peerHost: record.peerHostName,
                    lastDate: record.date,
                    lastMessagePreview: record.messageBody,
                    lastDirection: record.direction,
                    messageCount: 1,
                    sentCount: record.direction == .sent ? 1 : 0,
                    receivedCount: record.direction == .received ? 1 : 0
                )
            }
        }

        return map.values.sorted { $0.lastDate > $1.lastDate }
    }

    /// Filter messages for the selected conversation thread
    func threadMessages(from messages: [MessageRecord]) -> [MessageRecord] {
        guard let peer = selectedPeer else { return [] }
        return messages
            .filter { $0.peerUserName == peer }
            .filter { record in
                let matchesSearch = searchText.isEmpty ||
                    record.messageBody.localizedCaseInsensitiveContains(searchText)

                let matchesDirection: Bool = {
                    guard let dir = filterDirection else { return true }
                    return record.direction == dir
                }()

                return matchesSearch && matchesDirection
            }
            .sorted { $0.date < $1.date }
    }
}

struct ConversationInfo: Identifiable {
    var id: String { peerName }
    let peerName: String
    let peerHost: String
    var lastDate: Date
    var lastMessagePreview: String
    var lastDirection: MessageDirection
    var messageCount: Int
    var sentCount: Int
    var receivedCount: Int
}
