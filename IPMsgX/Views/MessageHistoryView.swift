// IPMsgX/Views/MessageHistoryView.swift
// Conversation-based message history with chat bubble layout

import SwiftUI
import SwiftData

struct MessageHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = MessageHistoryViewModel()

    @Query(sort: \MessageRecord.date, order: .reverse)
    private var allMessages: [MessageRecord]

    var body: some View {
        NavigationSplitView {
            HistoryConversationList(
                conversations: viewModel.conversations(from: allMessages),
                selectedPeer: $viewModel.selectedPeer
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if viewModel.selectedPeer != nil {
                HistoryThreadView(
                    viewModel: viewModel,
                    messages: viewModel.threadMessages(from: allMessages)
                )
            } else {
                ContentUnavailableView(
                    "Select a Conversation",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Choose a contact from the sidebar to view message history.")
                )
            }
        }
        .navigationTitle("Message History")
        .frame(minWidth: 600, minHeight: 400)
    }
}

// MARK: - Conversation Sidebar

private struct HistoryConversationList: View {
    let conversations: [ConversationInfo]
    @Binding var selectedPeer: String?

    var body: some View {
        List(selection: $selectedPeer) {
            if conversations.isEmpty {
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "tray",
                    description: Text("Messages will appear here after you send or receive them.")
                )
            } else {
                ForEach(conversations) { conv in
                    HistoryConversationRow(conversation: conv)
                        .tag(conv.peerName)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct HistoryConversationRow: View {
    let conversation: ConversationInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(conversation.peerName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(conversation.lastDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 2) {
                    if conversation.lastDirection == .sent {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                    Text(conversation.lastMessagePreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text("\(conversation.messageCount) messages")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Chat Thread View

private struct HistoryThreadView: View {
    @Bindable var viewModel: MessageHistoryViewModel
    let messages: [MessageRecord]

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    TextField("Search in conversation...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                }
                .padding(6)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))

                Picker("", selection: $viewModel.filterDirection) {
                    Text("All").tag(MessageDirection?.none)
                    Image(systemName: "arrow.down.left").tag(MessageDirection?.some(.received))
                    Image(systemName: "arrow.up.right").tag(MessageDirection?.some(.sent))
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Chat bubbles
            if messages.isEmpty {
                Spacer()
                ContentUnavailableView.search(text: viewModel.searchText)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, record in
                                let showDate = shouldShowDateHeader(at: index, in: messages)
                                if showDate {
                                    Text(record.date, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 12)
                                        .padding(.bottom, 4)
                                }
                                HistoryChatBubble(record: record)
                                    .id(record.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .onAppear {
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .navigationTitle(viewModel.selectedPeer ?? "")
    }

    private func shouldShowDateHeader(at index: Int, in msgs: [MessageRecord]) -> Bool {
        guard index > 0 else { return true }
        let cal = Calendar.current
        return !cal.isDate(msgs[index].date, inSameDayAs: msgs[index - 1].date)
    }
}

// MARK: - Chat Bubble

private struct HistoryChatBubble: View {
    let record: MessageRecord
    private var isSent: Bool { record.direction == .sent }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isSent { Spacer(minLength: 80) }

            VStack(alignment: isSent ? .trailing : .leading, spacing: 3) {
                // Message body
                Text(record.messageBody)
                    .textSelection(.enabled)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isSent
                            ? Color.accentColor.opacity(0.15)
                            : Color.secondary.opacity(0.1),
                        in: ChatBubbleShape(isSent: isSent)
                    )

                // Metadata row
                HStack(spacing: 5) {
                    if isSent {
                        metaBadges
                    }

                    Text(record.date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if !isSent {
                        metaBadges
                    }
                }
            }

            if !isSent { Spacer(minLength: 80) }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var metaBadges: some View {
        if record.isSealed || record.secureLevel > 0 {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
                .foregroundStyle(.green)
        }
        if record.hasAttachments {
            HStack(spacing: 1) {
                Image(systemName: "paperclip")
                    .font(.system(size: 9))
                if let names = record.attachmentNames {
                    Text(names)
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        if record.isBroadcast {
            Image(systemName: "megaphone.fill")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Chat Bubble Shape

private struct ChatBubbleShape: Shape {
    let isSent: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 12
        let tail: CGFloat = 4

        var path = Path()

        if isSent {
            // Rounded rect with bottom-right tail
            path.addRoundedRect(
                in: CGRect(x: rect.minX, y: rect.minY, width: rect.width - tail, height: rect.height),
                cornerSize: CGSize(width: r, height: r)
            )
            // Small tail
            path.move(to: CGPoint(x: rect.maxX - tail, y: rect.maxY - r))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - tail - r, y: rect.maxY))
        } else {
            // Rounded rect with bottom-left tail
            path.addRoundedRect(
                in: CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height),
                cornerSize: CGSize(width: r, height: r)
            )
            // Small tail
            path.move(to: CGPoint(x: rect.minX + tail, y: rect.maxY - r))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + tail + r, y: rect.maxY))
        }

        return path
    }
}
