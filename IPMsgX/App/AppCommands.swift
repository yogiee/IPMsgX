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

        // Absence Mode
        CommandMenu("Absence") {
            Button("Normal (Not Absent)") {
                appState.toggleAbsence(index: nil)
            }
            .disabled(!appState.isAbsent)

            Divider()

            let defs = SettingsService.shared.absenceDefinitions
            ForEach(Array(defs.enumerated()), id: \.offset) { idx, def in
                Button(def.title) {
                    appState.toggleAbsence(index: idx)
                }
            }
        }
    }

    private func openNewMessageWindow() {
        NotificationCenter.default.post(name: .openNewSendWindow, object: nil)
    }
}

extension Notification.Name {
    static let openNewSendWindow = Notification.Name("com.ipmsgx.openNewSendWindow")
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
