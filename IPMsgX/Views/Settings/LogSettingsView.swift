// IPMsgX/Views/Settings/LogSettingsView.swift

import SwiftUI

struct LogSettingsView: View {
    @State private var settings = SettingsService.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable message log", isOn: $settings.standardLogEnabled)
                Toggle("Log sealed messages on open", isOn: $settings.logChainedWhenOpen)
                    .disabled(!settings.standardLogEnabled)
                TextField("Log file", text: $settings.standardLogFile)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!settings.standardLogEnabled)
            } header: {
                Text("Message Log")
            } footer: {
                Text("Appends every sent and received message to a plain-text log file.")
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
    @AppStorage("receiveSoundName") private var receiveSoundName = "Submarine"

    private let systemSounds: [String] = {
        let dir = "/System/Library/Sounds"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
    }()

    var body: some View {
        Form {
            Section("Incoming Messages") {
                Toggle("Show notification banner instead of opening message", isOn: $settings.useNotificationBanner)
                    .help("When enabled, incoming messages show as macOS notification banners. When disabled, the message window opens directly.")
                Toggle("Non-popup when absent", isOn: $settings.nonPopupWhenAbsence)
                    .help("Use notification banners instead of opening message window while in absence mode.")
            }

            Section("Receive") {
                Picker("Sound", selection: $receiveSoundName) {
                    Text("None").tag("")
                    ForEach(systemSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .onChange(of: receiveSoundName) {
                    if !receiveSoundName.isEmpty { NSSound(named: receiveSoundName)?.play() }
                }
                Toggle("Quote by default when replying", isOn: $settings.quoteCheckDefault)
                Toggle("Use clickable URLs", isOn: $settings.useClickableURL)
            }

            Section("File Downloads") {
                LabeledContent("Save to") {
                    HStack(spacing: 8) {
                        Text(settings.downloadLocation.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { chooseDownloadFolder() }
                    }
                }
                Toggle("Always prompt for location", isOn: $settings.alwaysPromptSaveLocation)
                    .help("When on, a save dialog opens at the folder above for each download. When off, files save straight into that folder.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.downloadLocation
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadLocation = url
        }
    }
}
