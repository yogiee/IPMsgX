// IPMsgX/Views/Settings/NetworkSettingsView.swift

import SwiftUI

struct NetworkSettingsView: View {
    @State private var settings = SettingsService.shared
    @State private var broadcastAddresses: [String] = SettingsService.shared.broadcastAddresses
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
                if broadcastAddresses.isEmpty {
                    Text("No custom broadcast addresses.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(broadcastAddresses.enumerated()), id: \.offset) { idx, addr in
                        HStack {
                            Text(addr)
                            Spacer()
                            Button {
                                broadcastAddresses.remove(at: idx)
                                settings.broadcastAddresses = broadcastAddresses
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remove")
                        }
                    }
                }

                HStack {
                    TextField("IP Address", text: $newBroadcastAddress)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addBroadcast() }
                    Button("Add") { addBroadcast() }
                        .disabled(newBroadcastAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Connection") {
                Toggle("Dialup connection", isOn: $settings.dialup)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func addBroadcast() {
        let addr = newBroadcastAddress.trimmingCharacters(in: .whitespaces)
        guard !addr.isEmpty, !broadcastAddresses.contains(addr) else { return }
        broadcastAddresses.append(addr)
        settings.broadcastAddresses = broadcastAddresses
        newBroadcastAddress = ""
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
