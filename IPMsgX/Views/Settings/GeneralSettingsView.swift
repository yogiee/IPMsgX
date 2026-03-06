// IPMsgX/Views/Settings/GeneralSettingsView.swift

import SwiftUI

struct GeneralSettingsView: View {
    @State private var settings = SettingsService.shared

    var body: some View {
        Form {
            Section("Identity") {
                TextField("User Name", text: $settings.userName)
                    .textFieldStyle(.roundedBorder)
                TextField("Group Name", text: $settings.groupName)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password (for locked messages)", text: $settings.password)
                    .textFieldStyle(.roundedBorder)
            }

            Section("User List Display") {
                Toggle("Hostname", isOn: $settings.showHostName)
                Toggle("IP Address", isOn: $settings.showIPAddress)
                Toggle("Group Name", isOn: $settings.showGroupName)
                Toggle("Login Name", isOn: $settings.showLogOnName)
            }

            Section("Menu Bar") {
                Toggle("Show status bar icon", isOn: $settings.useStatusBar)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
