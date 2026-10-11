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

            Section {
                Toggle("IP Address", isOn: $settings.showIPAddress)
                Toggle("Login Name", isOn: $settings.showLogOnName)
                Toggle("Hostname", isOn: $settings.showHostName)
                Toggle("Group Name", isOn: $settings.showGroupName)
            } header: {
                Text("User List Details")
            } footer: {
                Text("Shown under each name in the New Message sidebar. Hover over a name to see all details.")
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar") {
                Toggle("Show status bar icon", isOn: $settings.useStatusBar)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
