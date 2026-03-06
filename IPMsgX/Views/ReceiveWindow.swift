// IPMsgX/Views/ReceiveWindow.swift
// Received message display with seal, reply, file download

import SwiftUI

struct ReceiveWindow: View {
    let message: ReceivedMessage
    @Environment(AppState.self) private var appState
    @State private var viewModel: ReceiveViewModel?

    var body: some View {
        Group {
            if let viewModel {
                ReceiveWindowContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ReceiveViewModel(message: message, appState: appState)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct ReceiveWindowContent: View {
    @Bindable var viewModel: ReceiveViewModel
    @Environment(\.dismiss) private var dismiss

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
                        Text(viewModel.message.message)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }

                    if !viewModel.isSealOpened {
                        SealCoverView {
                            Task {
                                await viewModel.openSeal()
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                // Attachments
                if viewModel.hasAttachments {
                    Divider()
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(viewModel.message.attachments, id: \.fileID) { attach in
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
                            Spacer()
                            Button("Cancel") {
                                viewModel.showReplyField = false
                                viewModel.replyText = ""
                            }
                            Button("Send Reply") {
                                Task {
                                    await viewModel.reply()
                                    dismiss()
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
                            dismiss()
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
    }
}
