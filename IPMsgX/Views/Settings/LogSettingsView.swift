// IPMsgX/Views/Settings/LogSettingsView.swift

import SwiftUI

struct LogSettingsView: View {
    @State private var settings = SettingsService.shared

    var body: some View {
        Form {
            Section("Standard Log") {
                Toggle("Enable standard log", isOn: $settings.standardLogEnabled)
                Toggle("Log sealed messages on open", isOn: $settings.logChainedWhenOpen)
                    .disabled(!settings.standardLogEnabled)
                TextField("Log file", text: $settings.standardLogFile)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!settings.standardLogEnabled)
            }

            Section("Important Log") {
                Toggle("Enable important log", isOn: $settings.alternateLogEnabled)
                TextField("Log file", text: $settings.alternateLogFile)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!settings.alternateLogEnabled)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// Send/Receive settings stubs (combined since they're simple)
struct SendSettingsView: View {
    @State private var settings = SettingsService.shared

    var body: some View {
        Form {
            Section("Compose") {
                TextField("Quote prefix", text: $settings.quoteString)
                    .textFieldStyle(.roundedBorder)
                Toggle("Seal messages by default", isOn: $settings.sealCheckDefault)
                Toggle("Allow sending to multiple users", isOn: $settings.allowSendingToMultiUser)
            }

            Section("Behavior") {
                Toggle("Open new message on Dock click", isOn: $settings.openNewOnDockClick)
                Toggle("Close receive window on reply", isOn: $settings.hideReceiveWindowOnReply)
                Toggle("Notify when seal is opened", isOn: $settings.noticeSealOpened)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ReceiveSettingsView: View {
    @State private var settings = SettingsService.shared

    var body: some View {
        Form {
            Section("Incoming Messages") {
                Toggle("Show notification banner instead of opening message", isOn: $settings.useNotificationBanner)
                    .help("When enabled, incoming messages show as macOS notification banners. When disabled, the message window opens directly.")
                Toggle("Non-popup when absent", isOn: $settings.nonPopupWhenAbsence)
                    .help("Use notification banners instead of opening message window while in absence mode.")
            }

            Section("Receive") {
                TextField("Sound", text: $settings.receiveSoundName)
                    .textFieldStyle(.roundedBorder)
                Toggle("Quote by default when replying", isOn: $settings.quoteCheckDefault)
                Toggle("Use clickable URLs", isOn: $settings.useClickableURL)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
