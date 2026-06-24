// IPMsgX/Views/ReceiveWindow.swift
// Received message display with seal, reply, file download

import SwiftUI

struct ReceiveWindow: View {
    let message: ReceivedMessage
    var onClose: (() -> Void)? = nil
    @Environment(AppState.self) private var appState
    @State private var viewModel: ReceiveViewModel?

    var body: some View {
        Group {
            if let viewModel {
                ReceiveWindowContent(viewModel: viewModel, onClose: onClose)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ReceiveViewModel(message: message, appState: appState)
            }
        }
        .onDisappear {
            // Inline images are one-time — discard the temp files when the window closes.
            viewModel?.cleanupInlineTemp()
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct ReceiveWindowContent: View {
    @Bindable var viewModel: ReceiveViewModel
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private func closeWindow() {
        if let onClose { onClose() } else { dismiss() }
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading) {
                            Text(viewModel.senderDisplayName)
                                .font(.headline)
                            Text(viewModel.senderInfo)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let badge = viewModel.securityBadge {
                            Label(badge, systemImage: "lock.fill")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.15), in: Capsule())
                                .foregroundStyle(.green)
                        }

                        if viewModel.message.doubt {
                            Label("Unverified", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(viewModel.dateString)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if viewModel.message.isBroadcast {
                        Label("Broadcast", systemImage: "megaphone")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if viewModel.message.isAbsenceReply {
                        Label("Auto-reply (Absence)", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

                Divider()

                // Message body (with seal overlay)
                ZStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            let sanitized = MessageRenderer.sanitize(viewModel.message.message)
                            if !sanitized.isEmpty {
                                Text(MessageRenderer.render(viewModel.message.message))
                                    .font(SettingsService.shared.messageFont)
                                    .lineSpacing(SettingsService.shared.messageLineSpacing)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else if viewModel.inlineImages.isEmpty, viewModel.hasFileAttachments {
                                Label(
                                    viewModel.fileAttachments.count == 1
                                        ? "1 attachment" : "\(viewModel.fileAttachments.count) attachments",
                                    systemImage: "paperclip"
                                )
                                .foregroundStyle(.secondary)
                            }

                            // Inline images — stacked, animated (GIF), click for Quick Look.
                            ForEach(viewModel.inlineImages, id: \.fileID) { img in
                                InlineImageCell(viewModel: viewModel, attachment: img)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }

                    if !viewModel.isSealOpened {
                        SealCoverView(isLocked: viewModel.message.isLocked) {
                            viewModel.attemptOpenSeal()
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .task(id: viewModel.isSealOpened) {
                    // Load inline images once the content is visible (not while sealed).
                    if viewModel.isSealOpened { await viewModel.loadInlineImages() }
                }

                // File attachments (inline images are excluded — they show in the body)
                if viewModel.hasFileAttachments {
                    Divider()
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(viewModel.fileAttachments, id: \.fileID) { attach in
                                Button {
                                    viewModel.downloadAttachment(attach)
                                } label: {
                                    Label(attach.fileName, systemImage: attach.fileType == .directory ? "folder" : "doc")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .help("\(ReceiveViewModel.formattedSize(attach.fileSize)) — Click to download")
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }

                    if let error = viewModel.downloadError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                    }
                }

                Divider()

                // Reply area
                if viewModel.showReplyField {
                    VStack(spacing: 8) {
                        TextEditor(text: $viewModel.replyText)
                            .font(.body)
                            .frame(height: 80)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

                        HStack {
                            Toggle("Quote", isOn: $viewModel.quoteEnabled)
                                .toggleStyle(.checkbox)
                                .font(.caption)
                                .help("Include the original message, quoted, in your reply")
                            Spacer()
                            Button("Cancel") {
                                viewModel.showReplyField = false
                                viewModel.replyText = ""
                            }
                            Button("Send Reply") {
                                Task {
                                    await viewModel.reply()
                                    closeWindow()
                                }
                            }
                            .keyboardShortcut(.defaultAction)
                            .disabled(viewModel.replyText.isEmpty)
                        }
                    }
                    .padding()
                } else {
                    HStack {
                        Spacer()
                        Button("Reply") {
                            viewModel.showReplyField = true
                        }
                        .keyboardShortcut("r", modifiers: .command)

                        Button("Close") {
                            closeWindow()
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                    .padding()
                }
            }

            // Download progress overlay
            if viewModel.isDownloading, let progress = viewModel.downloadProgress {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                DownloadProgressView(
                    fileName: progress.fileName,
                    progress: progress.fractionComplete,
                    downloadedSize: ReceiveViewModel.formattedSize(progress.downloadedSize),
                    totalSize: ReceiveViewModel.formattedSize(progress.totalSize),
                    onCancel: { viewModel.cancelDownload() }
                )
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle("From \(viewModel.senderDisplayName)")
        .sheet(isPresented: $viewModel.showImagePreview) {
            if let url = viewModel.downloadedFileURL {
                ImagePreviewView(url: url)
            }
        }
        .sheet(isPresented: $viewModel.showPasswordPrompt) {
            PasswordPromptView(viewModel: viewModel)
        }
        .sheet(item: $viewModel.quickLookItem) { item in
            QuickLookSheet(url: item.url)
        }
    }
}

/// One inline image in the message body — animated, tap for Quick Look, right-click to save.
private struct InlineImageCell: View {
    @Bindable var viewModel: ReceiveViewModel
    let attachment: IPMsgAttachmentParser.ParsedAttachment

    var body: some View {
        if let url = viewModel.inlineImageURLs[attachment.fileID] {
            let size = viewModel.inlineImageSizes[attachment.fileID] ?? CGSize(width: 200, height: 200)
            AnimatedImageView(url: url)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                .contentShape(Rectangle())
                .onTapGesture { viewModel.showQuickLook(fileID: attachment.fileID) }
                .contextMenu {
                    Button("Quick Look") { viewModel.showQuickLook(fileID: attachment.fileID) }
                    Button("Save…") { viewModel.saveInline(fileID: attachment.fileID) }
                }
                .help("Click for Quick Look · right-click to save")
        } else if viewModel.inlineLoading.contains(attachment.fileID) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading image…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(height: 48)
        } else {
            Label("Couldn’t load \(attachment.fileName)", systemImage: "photo.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Password entry for opening a locked message. Validates against the receiver's own password.
private struct PasswordPromptView: View {
    @Bindable var viewModel: ReceiveViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Locked Message", systemImage: "lock.fill")
                .font(.headline)

            Text("This message is locked. Enter your password to open it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Password", text: $viewModel.passwordInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit { viewModel.submitPassword() }

            if viewModel.passwordError {
                Label("Incorrect password", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.showPasswordPrompt = false
                    viewModel.passwordInput = ""
                    viewModel.passwordError = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Open") {
                    viewModel.submitPassword()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.passwordInput.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
    }
}
