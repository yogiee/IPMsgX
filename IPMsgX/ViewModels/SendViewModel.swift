// IPMsgX/ViewModels/SendViewModel.swift
// View model for compose/send window

import SwiftUI

@Observable
@MainActor
final class SendViewModel {
    var selectedUsers: Set<UserIdentifier> = []
    var messageText: String = ""
    var attachmentURLs: [URL] = []
    /// Images to send inline (clipboard position) rather than as file attachments.
    var inlineImageURLs: [URL] = []
    var isSealed: Bool = false
    var isLocked: Bool = false
    var searchText: String = ""

    /// Sort order for the user table columns.
    var sortOrder: [KeyPathComparator<UserInfo>] = [KeyPathComparator(\UserInfo.displayName)]

    private let appState: AppState

    init(appState: AppState, preselectedUser: UserInfo? = nil) {
        self.appState = appState
        self.isSealed = SettingsService.shared.sealCheckDefault
        if let user = preselectedUser {
            self.selectedUsers = [user.id]
        }
    }

    var filteredUsers: [UserInfo] {
        let users = appState.onlineUsers
        if searchText.isEmpty {
            return users
        }
        let query = searchText.lowercased()
        return users.filter { user in
            user.displayName.lowercased().contains(query) ||
            user.hostName.lowercased().contains(query) ||
            user.logOnName.lowercased().contains(query) ||
            (user.groupName?.lowercased().contains(query) ?? false)
        }
    }

    /// Users shown in the table — filtered by search, then sorted by the active column order.
    var displayedUsers: [UserInfo] {
        filteredUsers.sorted(using: sortOrder)
    }

    var groupedUsers: [(String, [UserInfo])] {
        let grouped = Dictionary(grouping: filteredUsers) { $0.groupName ?? "" }
        return grouped.sorted { $0.key < $1.key }
    }

    var canSend: Bool {
        !selectedUsers.isEmpty && (!messageText.isEmpty || !attachmentURLs.isEmpty || !inlineImageURLs.isEmpty)
    }

    func toggleUser(_ user: UserInfo) {
        if selectedUsers.contains(user.id) {
            selectedUsers.remove(user.id)
        } else {
            if !SettingsService.shared.allowSendingToMultiUser {
                selectedUsers.removeAll()
            }
            selectedUsers.insert(user.id)
        }
    }

    func addAttachment(url: URL) {
        if !attachmentURLs.contains(url) {
            attachmentURLs.append(url)
        }
    }

    func removeAttachment(at index: Int) {
        guard index >= 0, index < attachmentURLs.count else { return }
        attachmentURLs.remove(at: index)
    }

    func addInlineImage(url: URL) {
        if !inlineImageURLs.contains(url) {
            inlineImageURLs.append(url)
        }
    }

    func removeInlineImage(at index: Int) {
        guard index >= 0, index < inlineImageURLs.count else { return }
        inlineImageURLs.remove(at: index)
    }

    /// Save pasted clipboard image data to a temp file and queue it as an inline image.
    func addPastedImage(_ data: Data, fileExtension: String) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("IPMsgX-send", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("pasted-\(UUID().uuidString).\(fileExtension)")
        do {
            try data.write(to: url)
            addInlineImage(url: url)
        } catch {
            // ignore — paste simply does nothing if the temp write fails
        }
    }

    /// Whether a dropped file is an image (used to offer the inline-vs-attachment choice).
    static func isImageFile(_ url: URL) -> Bool {
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "webp"]
        return imageExts.contains(url.pathExtension.lowercased())
    }

    /// Re-broadcast presence to refresh the online user list.
    func refreshUsers() async {
        await appState.messageService?.refreshUserList()
    }

    /// Enforce single-recipient selection when multi-user sending is disabled.
    /// Called from the table's selection onChange with the previous and new selection.
    func reconcileSelection(previous: Set<UserIdentifier>, current: Set<UserIdentifier>) {
        guard !SettingsService.shared.allowSendingToMultiUser, current.count > 1 else { return }
        let added = current.subtracting(previous)
        selectedUsers = Set((added.isEmpty ? Array(current.prefix(1)) : Array(added.prefix(1))))
    }

    func send() async {
        let users = appState.onlineUsers.filter { selectedUsers.contains($0.id) }
        guard !users.isEmpty, canSend else { return }

        _ = await appState.sendMessage(
            to: users,
            message: messageText,
            isSealed: isSealed,
            isLocked: isLocked,
            attachments: attachmentURLs,
            inlineImages: inlineImageURLs
        )

        // Reset
        messageText = ""
        attachmentURLs = []
        inlineImageURLs = []
    }
}
