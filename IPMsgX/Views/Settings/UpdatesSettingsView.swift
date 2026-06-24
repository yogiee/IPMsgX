// IPMsgX/Views/Settings/UpdatesSettingsView.swift

import SwiftUI

struct UpdatesSettingsView: View {
    @State private var schedule = UpdaterService.shared.updateCheckSchedule

    var body: some View {
        Form {
            Section("Automatic Updates") {
                Picker("Check for updates", selection: $schedule) {
                    ForEach(UpdateCheckSchedule.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: schedule) { _, newValue in
                    UpdaterService.shared.updateCheckSchedule = newValue
                }
                Text("Updates are downloaded and verified automatically, then installed on quit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Check for Updates Now…") {
                    UpdaterService.shared.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
