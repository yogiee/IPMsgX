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
        .frame(minWidth: 760, minHeight: 460)
    }
}

/// Compose window, macOS 27 style: online users fill an edge-to-edge glass sidebar; the message
/// editor fills the detail pane under a floating title + formatting pill, with the send controls
/// floating over the bottom edge (no bar behind them).
struct SendWindowContent: View {
    @Bindable var viewModel: SendViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cmdEnterToSend") private var cmdEnterToSend: Bool = false
    @State private var isTextAreaDropTargeted = false
    @State private var droppedImages: [URL] = []
    @State private var showDropChoice = false
    @State private var pillHeight: CGFloat = 0
    @State private var controlsHeight: CGFloat = 0

    /// Route dropped files: images offer an inline-vs-attachment choice; everything else attaches.
    private func handleDrop(_ urls: [URL]) {
        let images = urls.filter { SendViewModel.isImageFile($0) }
        for url in urls where !SendViewModel.isImageFile(url) {
            viewModel.addAttachment(url: url)
        }
        if !images.isEmpty {
            droppedImages = images
            showDropChoice = true
        }
    }

    /// Close the send window after sending (matches the original).
    private func sendAndClose() {
        guard viewModel.canSend else { return }
        Task {
            await viewModel.send()
            dismiss()
        }
    }

    /// "To:" line under the title in the pill.
    private var recipientSummary: String {
        let names = viewModel.displayedUsers
            .filter { viewModel.selectedUsers.contains($0.id) }
            .map(\.displayName)
        switch names.count {
        case 0:     return "Choose recipients from the sidebar"
        case 1...3: return "To: " + names.joined(separator: ", ")
        default:    return "To: \(names.prefix(2).joined(separator: ", ")) and \(names.count - 2) more"
        }
    }

    var body: some View {
        // Pin the sidebar visible — the user list is how recipients are chosen.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            userList
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 420)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            composer
        }
        .searchable(text: $viewModel.searchText, placement: .sidebar, prompt: "Search")
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
            return true
        }
        .confirmationDialog(
            droppedImages.count == 1 ? "Add this image" : "Add \(droppedImages.count) images",
            isPresented: $showDropChoice,
            titleVisibility: .visible
        ) {
            Button("Send Inline") {
                for url in droppedImages { viewModel.addInlineImage(url: url) }
                droppedImages = []
            }
            Button("Add as Attachment") {
                for url in droppedImages { viewModel.addAttachment(url: url) }
                droppedImages = []
            }
            Button("Cancel", role: .cancel) { droppedImages = [] }
        } message: {
            Text("Send inline to show the image in the message, or add it as a downloadable file attachment.")
        }
    }

    // MARK: - Sidebar

    /// One row per online user. Click selects, ⌘-click adds, Shift-click extends (standard List).
    private var userList: some View {
        List(selection: $viewModel.selectedUsers) {
            Section("On the network · \(viewModel.filteredUsers.count)") {
                ForEach(viewModel.displayedUsers) { user in
                    UserSidebarRow(user: user, isSelected: viewModel.selectedUsers.contains(user.id))
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: viewModel.selectedUsers) { old, new in
            viewModel.reconcileSelection(previous: old, current: new)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 8) {
                Text("\(viewModel.selectedUsers.count) of \(viewModel.filteredUsers.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button {
                    Task { await viewModel.refreshUsers() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh user list")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Detail

    private var composer: some View {
        ZStack {
            AttachmentTextEditor(
                text: $viewModel.messageText,
                cmdEnterToSend: cmdEnterToSend,
                onEnterSend: sendAndClose,
                onFileDrop: { urls in handleDrop(urls) },
                onPasteImage: { data, ext in viewModel.addPastedImage(data, fileExtension: ext) },
                isDropTargeted: $isTextAreaDropTargeted,
                topContentInset: pillHeight + 22,
                bottomContentInset: controlsHeight + 28
            )
            .padding(.horizontal, 22)

            // Scroll-edge fades keep text legible where it passes under the floating controls.
            VStack(spacing: 0) {
                LinearGradient(colors: [.editorBackground, .editorBackground.opacity(0)],
                               startPoint: .center, endPoint: .bottom)
                    .frame(height: pillHeight + 26)
                Spacer()
                LinearGradient(colors: [.editorBackground.opacity(0), .editorBackground],
                               startPoint: .top, endPoint: .center)
                    .frame(height: controlsHeight + 40)
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                pill
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pillHeight = $0 }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                Spacer()
                bottomControls
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
                    .padding(.leading, 26)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(Color.editorBackground)
        .ignoresSafeArea(.container, edges: .top)
        .overlay {
            if isTextAreaDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        Label("Drop to attach", systemImage: "paperclip")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(8)
            }
        }
        .onChange(of: viewModel.isSealed) { _, sealed in
            if !sealed { viewModel.isLocked = false }
        }
    }

    /// Floating elongated pill: window title + recipients, then the Markdown formatting buttons.
    private var pill: some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text("New Message")
                    .font(.headline)
                Text(recipientSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())  // title bar is hidden — drag the window by its title

            formatButton("Bold", "bold", "Bold — wraps selection with **bold**", "**", "**")
            formatButton("Italic", "italic", "Italic — wraps selection with *italic*", "*", "*")
            formatButton("Strikethrough", "strikethrough",
                         "Strikethrough — wraps selection with ~~strikethrough~~\n(Underline is not supported by Markdown)",
                         "~~", "~~")
            Divider().frame(height: 18).padding(.horizontal, 4)
            formatButton("Inline Code", "chevron.left.forwardslash.chevron.right",
                         "Inline code — wraps selection with `code`", "`", "`")
            formatButton("Code Block", "curlybraces",
                         "Code block — wraps selection with ```code block```", "```\n", "\n```")
            Divider().frame(height: 18).padding(.horizontal, 4)
            Toggle("⌘↩ to Send", isOn: $cmdEnterToSend)
                .toggleStyle(.button)
                .buttonStyle(.accessoryBar)
                .help(cmdEnterToSend
                    ? "⌘Return sends the message. Plain Return inserts a newline."
                    : "Return sends the message. Turn on to require ⌘Return instead.")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .floatingGlass(in: Capsule())
    }

    private func formatButton(_ title: String, _ systemImage: String, _ help: String,
                              _ prefix: String, _ suffix: String) -> some View {
        Button {
            insertMarkdownAroundSelection(prefix, suffix)
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.accessoryBar)
        .help(help)
    }

    /// Send controls floating over the editor — no bar behind them. Queued attachments sit above.
    private var bottomControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.attachmentURLs.isEmpty || !viewModel.inlineImageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(viewModel.attachmentURLs.enumerated()), id: \.offset) { idx, url in
                            AttachmentChip(url: url, isInline: false) {
                                viewModel.removeAttachment(at: idx)
                            }
                        }
                        ForEach(Array(viewModel.inlineImageURLs.enumerated()), id: \.offset) { idx, url in
                            AttachmentChip(url: url, isInline: true) {
                                viewModel.removeInlineImage(at: idx)
                            }
                        }
                    }
                    .padding(4)  // room for the chips' glass edge
                }
            }

            HStack(spacing: 16) {
                Toggle("Seal", isOn: $viewModel.isSealed)
                    .toggleStyle(.checkbox)
                    .help("Sealed — the recipient must open the message to read it")

                Toggle("Lock", isOn: $viewModel.isLocked)
                    .toggleStyle(.checkbox)
                    .disabled(!viewModel.isSealed)
                    .help("Locked — the recipient needs their password to open it (requires Seal)")

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
                .floatingButtonStyle()
                .help("Attach files")

                Spacer(minLength: 12)

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .floatingButtonStyle()

                Button(action: sendAndClose) {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .keyboardShortcut(.defaultAction)
                .floatingButtonStyle(prominent: true)
                .disabled(!viewModel.canSend)
            }
            .controlSize(.large)
        }
    }
}

/// Sidebar row: display name large and bold; below it the details chosen in
/// Settings › General (IP · login · host · group). Hover shows everything.
private struct UserSidebarRow: View {
    let user: UserInfo
    /// Selected rows recolor the orange/green accents to `.primary`, which the List
    /// renders in the selection's contrasting color (white on the accent highlight).
    let isSelected: Bool
    // Same keys/defaults as SettingsService — @AppStorage so Settings changes apply live.
    @AppStorage("showIPAddress") private var showIP = false
    @AppStorage("showLogOnName") private var showLogin = false
    @AppStorage("showHostName") private var showHost = true
    @AppStorage("showGroupName") private var showGroup = false

    private var details: String {
        [
            showIP ? user.ipAddress : nil,
            showLogin ? user.logOnName : nil,
            showHost ? user.hostName : nil,
            showGroup ? user.groupName : nil,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "  ·  ")
    }

    private var tooltip: String {
        func value(_ s: String?) -> String { (s?.isEmpty ?? true) ? "—" : s! }
        return """
        \(user.displayName)
        Group: \(value(user.groupName))
        Host: \(value(user.hostName))
        IP Address: \(user.ipAddress)
        Login: \(value(user.logOnName))
        Version: \(value(user.version))
        Encryption: \(user.supportsEncrypt ? "Supported" : "Not supported")
        File Transfer: \(user.supportsAttachment ? "Supported" : "Not supported")
        Status: \(user.inAbsence ? "Away" : "Available")
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(user.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                if user.inAbsence {
                    Text("AWAY")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.orange))
                }
                Spacer(minLength: 4)
                if user.supportsEncrypt {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.green))
                        .accessibilityLabel("Encryption supported")
                }
            }
            if !details.isEmpty {
                Text(details)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 3)
        .help(tooltip)
    }
}

/// A chip for a queued attachment or inline image, with a remove button.
private struct AttachmentChip: View {
    let url: URL
    let isInline: Bool
    let onRemove: () -> Void

    var body: some View {
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
            Text(isInline ? "inline image" : url.lastPathComponent)
                .lineLimit(1)
            if isInline {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundStyle(.blue)
                    .help("Sent inline")
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .floatingGlass(in: Capsule())
        .font(.caption)
    }
}
