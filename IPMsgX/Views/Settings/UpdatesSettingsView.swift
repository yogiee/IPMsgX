// IPMsgX/Views/Settings/UpdatesSettingsView.swift

import SwiftUI

struct UpdatesSettingsView: View {
    @State private var updater = UpdaterService.shared

    var body: some View {
        Form {
            Section("Automatic Updates") {
                Picker("Update behavior", selection: $updater.updateMode) {
                    Text("Auto-update (recommended)").tag(0)
                    Text("Download updates, ask before installing").tag(1)
                    Text("Disabled").tag(2)
                }
                .pickerStyle(.radioGroup)
            }

            Section {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
