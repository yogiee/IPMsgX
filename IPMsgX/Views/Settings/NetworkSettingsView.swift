// IPMsgX/Views/Settings/NetworkSettingsView.swift

import SwiftUI

struct NetworkSettingsView: View {
    @State private var settings = SettingsService.shared
    @State private var newBroadcastAddress = ""

    var body: some View {
        Form {
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
}
