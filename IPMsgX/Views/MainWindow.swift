// IPMsgX/Views/MainWindow.swift
// Main window with NavigationSplitView — sidebar + content

import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @State private var selectedUser: UserIdentifier?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedUser: $selectedUser)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if selectedUser != nil {
                ConversationDetailView(userID: selectedUser)
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select a user from the sidebar or press Cmd+N to compose a new message.")
                )
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle("IPMsgX")
    }
}

struct ConversationDetailView: View {
    let userID: UserIdentifier?
    @Environment(AppState.self) private var appState

    var body: some View {
        if let userID {
            MessageThreadView(userID: userID)
                .environment(appState)
        } else {
            ContentUnavailableView(
                "No Messages",
                systemImage: "bubble.left",
                description: Text("Select a user to view the conversation.")
            )
        }
    }
}
