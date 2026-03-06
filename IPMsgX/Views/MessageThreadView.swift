// IPMsgX/Views/MessageThreadView.swift
// Chat-bubble conversation view with sent/received alignment

import SwiftUI
import AppKit

private func isImageFile(_ url: URL) -> Bool {
    let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "webp"]
    return imageExtensions.contains(url.pathExtension.lowercased())
}

struct MessageThreadView: View {
    let userID: UserIdentifier
    @Environment(AppState.self) private var appState
    @State private var replyText = ""
    @State private var showReplyField = false

    var body: some View {
        VStack(spacing: 0) {
            // Chat bubbles
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(threadMessages) { item in
                            ChatBubbleView(item: item)
                                .id(item.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: threadMessages.count) {
                    if let last = threadMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Quick reply bar
            HStack(spacing: 8) {
                TextField("Reply...", text: $replyText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(8)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))

                Button {
                    sendReply()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(replyText.isEmpty ? Color.secondary : Color.blue)
                }
                .buttonStyle(.plain)
                .disabled(replyText.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(10)
        }
        .navigationTitle(peerDisplayName)
    }

    // MARK: - Thread Messages

    private var peerDisplayName: String {
        if let user = appState.onlineUsers.first(where: { $0.id == userID }) {
            return user.displayName
        }
        // Fall back to received messages
        if let msg = appState.receivedMessages.first(where: { $0.fromUser.id == userID }) {
            return msg.fromUser.displayName
        }
        return userID.logOnName
    }

    private var threadMessages: [ThreadItem] {
        var items: [ThreadItem] = []

        // Received from this user
        for msg in appState.receivedMessages where msg.fromUser.id == userID {
            items.append(ThreadItem(
                id: "recv-\(msg.packetNo)",
                direction: .received,
                date: msg.receiveDate,
                message: msg.message,
                senderName: msg.fromUser.displayName,
                isSealed: msg.isSealed,
                secureLevel: msg.secureLevel,
                hasAttachments: msg.hasAttachments,
                attachmentCount: msg.attachments.count,
                packetNo: msg.packetNo
            ))
        }

        // Sent to this user
        for msg in appState.sentMessages {
            if msg.toUsers.contains(where: { $0.id == userID }) {
                items.append(ThreadItem(
                    id: "sent-\(msg.packetNo)",
                    direction: .sent,
                    date: msg.sendDate,
                    message: msg.message,
                    senderName: "Me",
                    isSealed: msg.isSealed,
                    secureLevel: 0,
                    hasAttachments: msg.hasAttachments,
                    attachmentCount: msg.attachmentURLs.count,
                    packetNo: msg.packetNo,
                    isSealOpenedByRecipient: msg.isSealed && appState.sentSealOpenedPacketNos.contains(msg.packetNo),
                    attachmentURLs: msg.attachmentURLs
                ))
            }
        }

        return items.sorted { $0.date < $1.date }
    }

    private func sendReply() {
        guard !replyText.isEmpty else { return }
        let text = replyText
        replyText = ""
        Task {
            if let user = appState.onlineUsers.first(where: { $0.id == userID }) {
                _ = await appState.sendMessage(
                    to: [user],
                    message: text,
                    isSealed: SettingsService.shared.sealCheckDefault,
                    isLocked: false
                )
            }
        }
    }
}

// MARK: - Thread Item

struct ThreadItem: Identifiable {
    let id: String
    let direction: MessageDirection
    let date: Date
    let message: String
    let senderName: String
    let isSealed: Bool
    let secureLevel: Int
    let hasAttachments: Bool
    let attachmentCount: Int
    let packetNo: Int?  // Set for received messages, enables reopening
    var isSealOpenedByRecipient: Bool = false
    var attachmentURLs: [URL] = []
}

// MARK: - Chat Bubble

private struct ChatBubbleView: View {
    let item: ThreadItem
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            if item.direction == .sent { Spacer(minLength: 60) }

            VStack(alignment: item.direction == .sent ? .trailing : .leading, spacing: 2) {
                Text(item.message)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(
                        item.direction == .sent
                            ? Color.blue.opacity(0.15)
                            : Color.secondary.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                if !item.attachmentURLs.isEmpty {
                    let imageURLs = item.attachmentURLs.filter { isImageFile($0) }
                    if !imageURLs.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(imageURLs, id: \.absoluteString) { url in
                                if let nsImage = NSImage(contentsOf: url) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxWidth: 120, maxHeight: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 4) {
                    Text(item.date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if item.isSealed && item.direction == .sent {
                        if item.isSealOpenedByRecipient {
                            Label("Opened", systemImage: "lock.open.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else {
                            Label("Sealed", systemImage: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    } else if item.secureLevel > 0 {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    if item.hasAttachments, let packetNo = item.packetNo {
                        Button {
                            appState.showMessage(packetNo: packetNo)
                        } label: {
                            Label("\(item.attachmentCount)", systemImage: "paperclip")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .help("Open message to download attachments")
                    } else if item.hasAttachments {
                        Label("\(item.attachmentCount)", systemImage: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contextMenu {
                if let packetNo = item.packetNo {
                    Button("Open Message") {
                        appState.showMessage(packetNo: packetNo)
                    }
                }
            }

            if item.direction == .received { Spacer(minLength: 60) }
        }
    }
}
