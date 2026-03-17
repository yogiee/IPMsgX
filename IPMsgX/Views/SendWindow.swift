// IPMsgX/Views/SendWindow.swift
// Compose and send message window

import SwiftUI
import AppKit

@MainActor
private func insertMarkdownAroundSelection(_ prefix: String, _ suffix: String) {
    guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
    let range = textView.selectedRange()
    let selected = (textView.string as NSString).substring(with: range)
    textView.insertText("\(prefix)\(selected)\(suffix)", replacementRange: range)
}

private func isImageFile(_ url: URL) -> Bool {
    let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "webp"]
    return imageExtensions.contains(url.pathExtension.lowercased())
}

struct SendWindow: View {
    var preselectedUser: UserInfo? = nil
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SendViewModel?

    var body: some View {
        Group {
            if let viewModel {
                SendWindowContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            viewModel = SendViewModel(appState: appState, preselectedUser: preselectedUser)
        }
        .frame(minWidth: 500, minHeight: 450)
    }
}

struct SendWindowContent: View {
    @Bindable var viewModel: SendViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cmdEnterToSend") private var cmdEnterToSend: Bool = false
    @State private var emojiPickerShown = false
    @State private var isTextAreaDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // User list
            List(viewModel.filteredUsers, id: \.id) { user in
                HStack {
                    if viewModel.selectedUsers.contains(user.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    } else {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                    }
                    UserRow(user: user)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.toggleUser(user)
                }
                .listRowBackground(
                    viewModel.selectedUsers.contains(user.id)
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
                )
            }
            .searchable(text: $viewModel.searchText, prompt: "Search users")
            .frame(minHeight: 150)

            Divider()

            // Message compose area
            VStack(spacing: 8) {
                // Formatting toolbar
                HStack(spacing: 1) {
                    ComposeToolbarButton(systemImage: "face.smiling") {
                        emojiPickerShown = true
                    }
                    .help("Emoji picker")
                    .popover(isPresented: $emojiPickerShown, arrowEdge: .bottom) {
                        EmojiPickerView { emoji in
                            viewModel.messageText += emoji
                            emojiPickerShown = false
                        }
                    }

                    Divider().frame(height: 16).padding(.horizontal, 3)

                    ComposeToolbarButton(systemImage: "bold") {
                        insertMarkdownAroundSelection("**", "**")
                    }
                    .help("Bold — wraps selection with **bold**")

                    ComposeToolbarButton(systemImage: "italic") {
                        insertMarkdownAroundSelection("*", "*")
                    }
                    .help("Italic — wraps selection with *italic*")

                    ComposeToolbarButton(systemImage: "strikethrough") {
                        insertMarkdownAroundSelection("~~", "~~")
                    }
                    .help("Strikethrough — wraps selection with ~~strikethrough~~\n(Underline is not supported by Markdown)")

                    ComposeToolbarButton(systemImage: "chevron.left.forwardslash.chevron.right") {
                        insertMarkdownAroundSelection("`", "`")
                    }
                    .help("Inline code — wraps selection with `code`")

                    ComposeToolbarButton(systemImage: "curlybraces") {
                        insertMarkdownAroundSelection("```\n", "\n```")
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

                AttachmentTextEditor(
                    text: $viewModel.messageText,
                    cmdEnterToSend: cmdEnterToSend,
                    onEnterSend: {
                        if viewModel.canSend {
                            Task { await viewModel.send(); dismiss() }
                        }
                    },
                    onFileDrop: { urls in
                        for url in urls { viewModel.addAttachment(url: url) }
                    },
                    isDropTargeted: $isTextAreaDropTargeted
                )
                .frame(minHeight: 100)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if isTextAreaDropTargeted {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .background(
                                Color.accentColor.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay {
                                Label("Drop to attach", systemImage: "paperclip")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(Color.accentColor)
                            }
                    }
                }

                // Attachments
                if !viewModel.attachmentURLs.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(Array(viewModel.attachmentURLs.enumerated()), id: \.offset) { idx, url in
                                HStack(spacing: 4) {
                                    if isImageFile(url), let nsImage = NSImage(contentsOf: url) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 24, height: 24)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    } else {
                                        Image(systemName: "doc")
                                    }
                                    Text(url.lastPathComponent)
                                        .lineLimit(1)
                                    Button {
                                        viewModel.removeAttachment(at: idx)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.fill.tertiary, in: Capsule())
                                .font(.caption)
                            }
                        }
                    }
                }

                // Controls
                HStack {
                    Toggle("Seal", isOn: $viewModel.isSealed)
                        .toggleStyle(.checkbox)

                    if viewModel.isSealed {
                        Toggle("Lock", isOn: $viewModel.isLocked)
                            .toggleStyle(.checkbox)
                    }

                    Button {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = true
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK {
                            for url in panel.urls {
                                viewModel.addAttachment(url: url)
                            }
                        }
                    } label: {
                        Label("Attach", systemImage: "paperclip")
                    }

                    Spacer()

                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Send") {
                        Task {
                            await viewModel.send()
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canSend)
                }
            }
            .padding()
        }
        .navigationTitle("New Message")
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                viewModel.addAttachment(url: url)
            }
            return true
        }
    }
}
