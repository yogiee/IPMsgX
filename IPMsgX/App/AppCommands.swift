// IPMsgX/App/AppCommands.swift
// Menu commands for IPMsgX

import SwiftUI

struct IPMsgCommands: Commands {
    let appState: AppState

    var body: some Commands {
        // Replace default New Window
        CommandGroup(replacing: .newItem) {
            Button("New Message") {
                openNewMessageWindow()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("Refresh User List") {
                Task {
                    await appState.messageService?.refreshUserList()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        // Updates
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                UpdaterService.shared.checkForUpdates()
            }
        }

        // Absence Mode — checkmarks show the active state (Toggle renders a checkmark when on).
        CommandMenu("Absence") {
            Toggle("Available", isOn: Binding(
                get: { !appState.isAbsent },
                set: { if $0 { appState.toggleAbsence(index: nil) } }
            ))

            Divider()

            let defs = SettingsService.shared.absenceDefinitions
            ForEach(Array(defs.enumerated()), id: \.offset) { idx, def in
                Toggle(def.title, isOn: Binding(
                    get: { appState.isAbsent && appState.absenceIndex == idx },
                    set: { if $0 { appState.toggleAbsence(index: idx) } }
                ))
            }
        }
    }

    private func openNewMessageWindow() {
        NotificationCenter.default.post(name: .openNewSendWindow, object: nil)
    }
}

extension Notification.Name {
    static let openNewSendWindow = Notification.Name("com.ipmsgx.openNewSendWindow")
    static let openHistoryWindow = Notification.Name("com.ipmsgx.openHistoryWindow")
    static let absenceChanged = Notification.Name("com.ipmsgx.absenceChanged")
    static let showReceivedMessage = Notification.Name("com.ipmsgx.showReceivedMessage")
    static let openSendWindowToUser = Notification.Name("com.ipmsgx.openSendWindowToUser")
    static let badgeCountChanged = Notification.Name("com.ipmsgx.badgeCountChanged")
}

/// Wrapper used as the `.sheet(item:)` identity for the send window.
/// Using `item:` instead of `isPresented:` ensures the preselectedUser
/// is available the instant SwiftUI evaluates the sheet content.
struct SendRequest: Identifiable {
    let id = UUID()
    let preselectedUser: UserInfo?
}
