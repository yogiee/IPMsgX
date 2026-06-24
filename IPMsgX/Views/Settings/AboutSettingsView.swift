// IPMsgX/Views/Settings/AboutSettingsView.swift

import SwiftUI
import AppKit

enum About {
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
    static let repoURL = URL(string: "https://github.com/yogiee/IPMsgX")!
    static let ipmsgURL = URL(string: "https://ipmsg.org")!
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("IPMsgX")
                .font(.system(size: 28, weight: .semibold))
            Text("IP Messenger for macOS")
                .foregroundStyle(.secondary)
            Text("Version \(About.version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Text("A native macOS port of IP Messenger — fast LAN messaging with file transfer and end-to-end encryption, interoperable with Windows clients.")
                .font(.callout)
                .multilineTextAlignment(.center)
            Link("github.com/yogiee/IPMsgX", destination: About.repoURL)
                .font(.callout)

            Divider().padding(.vertical, 4)

            VStack(spacing: 3) {
                Text("Compatible with the IP Messenger protocol").font(.caption)
                Link("ipmsg.org", destination: About.ipmsgURL)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("© 2026 yogiee").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
