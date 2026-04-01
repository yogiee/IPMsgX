// IPMsgX/Views/Settings/SettingsView.swift
// macOS Settings with tabs

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsView()
            }

            Tab("Network", systemImage: "network") {
                NetworkSettingsView()
            }

            Tab("Send", systemImage: "paperplane") {
                SendSettingsView()
            }

            Tab("Receive", systemImage: "envelope") {
                ReceiveSettingsView()
            }

            Tab("Absence", systemImage: "clock") {
                AbsenceSettingsView()
            }

            Tab("Refuse", systemImage: "hand.raised") {
                RefuseSettingsView()
            }

            Tab("Log", systemImage: "doc.text") {
                LogSettingsView()
            }

            Tab("Updates", systemImage: "arrow.down.circle") {
                UpdatesSettingsView()
            }
        }
        .frame(width: 500)
    }
}
