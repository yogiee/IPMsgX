// IPMsgX/Views/Settings/NetworkSettingsView.swift

import SwiftUI

struct NetworkSettingsView: View {
    @State private var settings = SettingsService.shared
    @State private var newBroadcastAddress = ""
    @State private var showKeyResetConfirm = false
    @State private var keyResetDone = false

    var body: some View {
        Form {
            Section("Encryption") {
                Toggle("Enable message encryption", isOn: $settings.encryptionEnabled)
                Text("When enabled, messages are encrypted end-to-end using RSA + AES-256. Disable if Windows clients cannot decrypt your messages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reset Encryption Keys…") {
                    showKeyResetConfirm = true
                }
                .confirmationDialog(
                    "Reset encryption keys?",
                    isPresented: $showKeyResetConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Reset Keys", role: .destructive) {
                        resetEncryptionKeys()
                        keyResetDone = true
                    }
                } message: {
                    Text("This deletes your RSA key files. New keys will be generated on next launch. Windows clients will detect the new fingerprint and re-exchange keys automatically.")
                }
                .alert("Keys reset", isPresented: $keyResetDone) {
                    Button("OK") { }
                } message: {
                    Text("RSA key files deleted. Restart IPMsgX to generate new keys and trigger automatic re-exchange with Windows clients.")
                }

                Text("Use \"Reset Encryption Keys\" if Windows clients consistently fail to decrypt your messages (stale key in Windows registry). After reset, restart the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Port") {
                TextField("Port Number", value: $settings.portNo, format: .number)
                    .textFieldStyle(.roundedBorder)
                Text("Default: 2425. Restart required after change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Broadcast Addresses") {
                List {
                    ForEach(settings.broadcastAddresses, id: \.self) { addr in
                        Text(addr)
                    }
                    .onDelete { indices in
                        var addrs = settings.broadcastAddresses
                        addrs.remove(atOffsets: indices)
                        settings.broadcastAddresses = addrs
                    }
                }
                .frame(height: 100)

                HStack {
                    TextField("IP Address", text: $newBroadcastAddress)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        guard !newBroadcastAddress.isEmpty else { return }
                        var addrs = settings.broadcastAddresses
                        addrs.append(newBroadcastAddress)
                        settings.broadcastAddresses = addrs
                        newBroadcastAddress = ""
                    }
                }
            }

            Section("Connection") {
                Toggle("Dialup connection", isOn: $settings.dialup)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func resetEncryptionKeys() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let keyDir = appSupport.appendingPathComponent("IPMsgX")
        for keyFile in ["rsa2048_private.key", "rsa1024_private.key"] {
            let url = keyDir.appendingPathComponent(keyFile)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
