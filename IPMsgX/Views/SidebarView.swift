// IPMsgX/Views/SidebarView.swift
// User list sidebar with search, grouped by group name

import SwiftUI

struct SidebarView: View {
    @Binding var selectedUser: UserIdentifier?
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""

    var body: some View {
        let filteredUsers = filteredOnlineUsers

        List(selection: $selectedUser) {
            if filteredUsers.isEmpty {
                ContentUnavailableView(
                    "No Users Online",
                    systemImage: "person.slash",
                    description: Text(searchText.isEmpty
                        ? "Waiting for users to appear on the network..."
                        : "No users match your search.")
                )
            } else {
                let grouped = Dictionary(grouping: filteredUsers) {
                    $0.groupName ?? ""
                }.sorted { $0.key < $1.key }

                ForEach(grouped, id: \.key) { group, users in
                    Section(group.isEmpty ? "No Group" : group) {
                        ForEach(users, id: \.id) { user in
                            UserRow(user: user)
                                .tag(user.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    openSendWindow(to: user)
                                }
                                .onTapGesture(count: 1) {
                                    selectedUser = user.id
                                }
                                .contextMenu {
                                    Button("Send Message") {
                                        openSendWindow(to: user)
                                    }
                                }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search users")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    NotificationCenter.default.post(name: .openNewSendWindow, object: nil)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Message")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    openWindow(id: "message-history")
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .help("Message History")
            }
        }
    }

    private func openSendWindow(to user: UserInfo) {
        appState.composePreselectedUser = user
        openWindow(id: "compose")
    }

    private var filteredOnlineUsers: [UserInfo] {
        if searchText.isEmpty {
            return appState.onlineUsers
        }
        let query = searchText.lowercased()
        return appState.onlineUsers.filter { user in
            user.displayName.lowercased().contains(query) ||
            user.hostName.lowercased().contains(query) ||
            user.logOnName.lowercased().contains(query) ||
            (user.groupName?.lowercased().contains(query) ?? false)
        }
    }
}

struct UserRow: View {
    let user: UserInfo
    private let settings = SettingsService.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: user.inAbsence ? "person.fill.xmark" : "person.fill")
                .foregroundStyle(user.inAbsence ? .orange : .blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .lineLimit(1)
                if !detailParts.isEmpty {
                    Text(detailParts.joined(separator: " | "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 4) {
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
        .padding(.vertical, 2)
    }

    private var detailParts: [String] {
        var parts: [String] = []
        if settings.showHostName {
            parts.append(user.hostName)
        }
        if settings.showIPAddress {
            parts.append(user.ipAddress)
        }
        if settings.showGroupName, let group = user.groupName, !group.isEmpty {
            parts.append(group)
        }
        if settings.showLogOnName {
            parts.append(user.logOnName)
        }
        return parts
    }
}
