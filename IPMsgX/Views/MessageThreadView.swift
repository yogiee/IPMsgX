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
    @State private var emojiPickerShown = false
    @State private var emojiTargetTextView: NSTextView? = nil
    @AppStorage("cmdEnterToSend") private var cmdEnterToSend: Bool = false

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

            // Compose area
            VStack(spacing: 0) {
                // Formatting toolbar
                HStack(spacing: 1) {
                    ComposeToolbarButton(systemImage: "face.smiling") {
                        emojiTargetTextView = NSApp.keyWindow?.firstResponder as? NSTextView
                        emojiPickerShown = true
                    }
                    .help("Emoji picker")
                    .popover(isPresented: $emojiPickerShown, arrowEdge: .bottom) {
                        EmojiPickerView { emoji in
                            if let tv = emojiTargetTextView {
                                tv.insertText(emoji, replacementRange: tv.selectedRange())
                            } else {
                                replyText += emoji
                            }
                            emojiPickerShown = false
                        }
                    }

                    Divider().frame(height: 16).padding(.horizontal, 3)

                    ComposeToolbarButton(systemImage: "bold") {
                        insertMarkdown("**", "**")
                    }
                    .help("Bold — wraps selection with **bold**")

                    ComposeToolbarButton(systemImage: "italic") {
                        insertMarkdown("*", "*")
                    }
                    .help("Italic — wraps selection with *italic*")

                    ComposeToolbarButton(systemImage: "strikethrough") {
                        insertMarkdown("~~", "~~")
                    }
                    .help("Strikethrough — wraps selection with ~~strikethrough~~\n(Underline is not supported by Markdown)")

                    ComposeToolbarButton(systemImage: "chevron.left.forwardslash.chevron.right") {
                        insertMarkdown("`", "`")
                    }
                    .help("Inline code — wraps selection with `code`")

                    ComposeToolbarButton(systemImage: "curlybraces") {
                        insertMarkdown("```\n", "\n```")
                    }
                    .help("Code block — wraps selection with ```code block```")

                    Spacer()

                    Toggle("⌘Return to send", isOn: $cmdEnterToSend)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(cmdEnterToSend
                            ? "⌘Return sends the message. Plain Return inserts a newline."
                            : "Return sends the message. Enable to require ⌘Return instead.")
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 2)

                // Text input + send button
                HStack(spacing: 8) {
                    TextField("Reply…", text: $replyText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .padding(8)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
                        .onKeyPress(keys: [.return]) { press in
                            let plainReturn = press.modifiers.isEmpty
                            let cmdReturn = press.modifiers.contains(.command)
                            // send on plain Return (default) or ⌘Return (when cmdEnterToSend is on)
                            if (!cmdEnterToSend && plainReturn) || cmdReturn {
                                if !replyText.isEmpty { sendReply() }
                                return .handled
                            }
                            return .ignored
                        }

                    Button {
                        sendReply()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(replyText.isEmpty ? Color.secondary : Color.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(replyText.isEmpty)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .padding(.top, 4)
            }
        }
        .navigationTitle(peerDisplayName)
        .onAppear { appState.markThreadRead(userID: userID) }
        .onChange(of: userID) { appState.markThreadRead(userID: userID) }
    }

    // MARK: - Helpers

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

    private func insertMarkdown(_ prefix: String, _ suffix: String) {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let range = textView.selectedRange()
        let selected = (textView.string as NSString).substring(with: range)
        textView.insertText("\(prefix)\(selected)\(suffix)", replacementRange: range)
    }

    // MARK: - Thread Messages

    private var peerDisplayName: String {
        if let user = appState.onlineUsers.first(where: { $0.id == userID }) {
            return user.displayName
        }
        if let msg = appState.receivedMessages.first(where: { $0.fromUser.id == userID }) {
            return msg.fromUser.displayName
        }
        return userID.logOnName
    }

    private var threadMessages: [ThreadItem] {
        var items: [ThreadItem] = []

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
    let packetNo: Int?
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
                renderedMessage
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

    @ViewBuilder
    private var renderedMessage: some View {
        if let attributed = try? AttributedString(
            markdown: item.message,
            options: .init(interpretedSyntax: .full)
        ) {
            Text(attributed)
        } else {
            Text(item.message)
        }
    }
}
