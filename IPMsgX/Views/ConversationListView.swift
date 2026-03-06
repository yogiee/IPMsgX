// IPMsgX/Views/ConversationListView.swift
// Recent conversations with unread badges

import SwiftUI

struct ConversationListView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedUser: UserIdentifier?

    var body: some View {
        List(selection: $selectedUser) {
            if conversations.isEmpty {
                ContentUnavailableView(
                    "No Conversations",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Messages you send and receive will appear here.")
                )
            } else {
                ForEach(conversations, id: \.userID) { conv in
                    ConversationRow(conversation: conv)
                        .tag(conv.userID)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Conversation Aggregation

    private var conversations: [ConversationSummary] {
        var map: [UserIdentifier: ConversationSummary] = [:]

        for msg in appState.receivedMessages {
            let id = msg.fromUser.id
            if var existing = map[id] {
                existing.messageCount += 1
                if msg.receiveDate > existing.lastDate {
                    existing.lastDate = msg.receiveDate
                    existing.lastMessagePreview = msg.message
                }
                map[id] = existing
            } else {
                map[id] = ConversationSummary(
                    userID: id,
                    displayName: msg.fromUser.displayName,
                    groupName: msg.fromUser.groupName,
                    lastDate: msg.receiveDate,
                    lastMessagePreview: msg.message,
                    messageCount: 1,
                    unreadCount: 0,
                    isOnline: appState.onlineUsers.contains { $0.id == id }
                )
            }
        }

        for msg in appState.sentMessages {
            for user in msg.toUsers {
                let id = user.id
                if var existing = map[id] {
                    existing.messageCount += 1
                    if msg.sendDate > existing.lastDate {
                        existing.lastDate = msg.sendDate
                        existing.lastMessagePreview = msg.message
                    }
                    map[id] = existing
                } else {
                    map[id] = ConversationSummary(
                        userID: id,
                        displayName: user.displayName,
                        groupName: user.groupName,
                        lastDate: msg.sendDate,
                        lastMessagePreview: msg.message,
                        messageCount: 1,
                        unreadCount: 0,
                        isOnline: appState.onlineUsers.contains { $0.id == id }
                    )
                }
            }
        }

        return map.values.sorted { $0.lastDate > $1.lastDate }
    }
}

// MARK: - Conversation Summary

struct ConversationSummary {
    let userID: UserIdentifier
    var displayName: String
    var groupName: String?
    var lastDate: Date
    var lastMessagePreview: String
    var messageCount: Int
    var unreadCount: Int
    var isOnline: Bool
}

// MARK: - Conversation Row

private struct ConversationRow: View {
    let conversation: ConversationSummary

    var body: some View {
        HStack(spacing: 10) {
            // Avatar
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                if conversation.isOnline {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.background, lineWidth: 1.5))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(conversation.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(conversation.lastDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(conversation.lastMessagePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if conversation.unreadCount > 0 {
                Text("\(conversation.unreadCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
