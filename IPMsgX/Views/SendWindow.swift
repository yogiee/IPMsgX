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

/// Non-optional accessors so the Group/Version table columns are sortable via KeyPathComparator.
private extension UserInfo {
    var groupDisplay: String { groupName ?? "" }
    var versionDisplay: String { version ?? "" }
}

struct SendWindow: View {
    @Environment(AppState.self) private var appState
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
            // Always build fresh — onAppear fires after requestCompose has set the user,
            // so composePreselectedUser is guaranteed current here.
            viewModel = SendViewModel(appState: appState, preselectedUser: appState.composePreselectedUser)
        }
        .onDisappear {
            viewModel = nil
        }
        .onChange(of: appState.composeRequestToken) { _, _ in
            // Window already visible and a new request arrived — rebuild for new user.
            viewModel = SendViewModel(appState: appState, preselectedUser: appState.composePreselectedUser)
        }
        .frame(minWidth: 620, minHeight: 470)
    }
}

struct SendWindowContent: View {
    @Bindable var viewModel: SendViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cmdEnterToSend") private var cmdEnterToSend: Bool = false
    @State private var isTextAreaDropTargeted = false
    @State private var columnCustomization = TableColumnCustomization<UserInfo>()

    var body: some View {
        VStack(spacing: 0) {
            // Header — search, member count, refresh
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search users", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 280)

                Spacer()

                Text("\(viewModel.selectedUsers.count) of \(viewModel.filteredUsers.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    Task { await viewModel.refreshUsers() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh user list")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // User table — sortable columns, multi-select; right-click a header to
            // show/hide/reorder columns (Name/Group/Host/IP/Logon/Version).
            Table(of: UserInfo.self,
                  selection: $viewModel.selectedUsers,
                  sortOrder: $viewModel.sortOrder,
                  columnCustomization: $columnCustomization) {
                TableColumn("Name", value: \.displayName) { user in
                    HStack(spacing: 6) {
                        Image(systemName: user.inAbsence ? "person.fill.xmark" : "person.fill")
                            .foregroundStyle(user.inAbsence ? .orange : .blue)
                        Text(user.displayName).lineLimit(1)
                        if user.supportsEncrypt {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        if user.supportsAttachment {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .customizationID("name")

                TableColumn("Group", value: \.groupDisplay) { user in
                    Text(user.groupDisplay).foregroundStyle(.secondary).lineLimit(1)
                }
                .customizationID("group")

                TableColumn("Host", value: \.hostName) { user in
                    Text(user.hostName).lineLimit(1)
                }
                .customizationID("host")

                TableColumn("IP Address", value: \.ipAddress) { user in
                    Text(user.ipAddress).monospacedDigit().lineLimit(1)
                }
                .customizationID("ip")

                TableColumn("Logon", value: \.logOnName) { user in
                    Text(user.logOnName).lineLimit(1)
                }
                .customizationID("logon")

                TableColumn("Version", value: \.versionDisplay) { user in
                    Text(user.versionDisplay).foregroundStyle(.secondary).lineLimit(1)
                }
                .customizationID("version")
            } rows: {
                ForEach(viewModel.displayedUsers) { user in
                    TableRow(user)
                }
            }
            .frame(minHeight: 160)
            .onChange(of: viewModel.selectedUsers) { old, new in
                viewModel.reconcileSelection(previous: old, current: new)
            }

            Divider()

            // Message compose area
            VStack(spacing: 8) {
                // Formatting toolbar
                HStack(spacing: 1) {
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
                            // Close the send window after sending (matches the original).
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
                        // Close the send window after sending (matches the original).
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
