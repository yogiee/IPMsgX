// IPMsgX/ViewModels/SendViewModel.swift
// View model for compose/send window

import SwiftUI

@Observable
@MainActor
final class SendViewModel {
    var selectedUsers: Set<UserIdentifier> = []
    var messageText: String = ""
    var attachmentURLs: [URL] = []
    var isSealed: Bool = false
    var isLocked: Bool = false
    var searchText: String = ""

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

    var groupedUsers: [(String, [UserInfo])] {
        let grouped = Dictionary(grouping: filteredUsers) { $0.groupName ?? "" }
        return grouped.sorted { $0.key < $1.key }
    }

    var canSend: Bool {
        !selectedUsers.isEmpty && (!messageText.isEmpty || !attachmentURLs.isEmpty)
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

    func send() async {
        let users = appState.onlineUsers.filter { selectedUsers.contains($0.id) }
        guard !users.isEmpty, (!messageText.isEmpty || !attachmentURLs.isEmpty) else { return }

        _ = await appState.sendMessage(
            to: users,
            message: messageText,
            isSealed: isSealed,
            isLocked: isLocked,
            attachments: attachmentURLs
        )

        // Reset
        messageText = ""
        attachmentURLs = []
    }
}
