// IPMsgX/Views/MenuBarView.swift
// MenuBarExtra with status icon and quick actions

import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section 1: Status
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isAbsent ? .orange : .green)
                        .frame(width: 8, height: 8)
                    Text(appState.isAbsent ? "Absence Mode" : "Online")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }

                HStack(spacing: 12) {
                    if appState.unreadCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "envelope.badge")
                                .font(.caption2)
                            Text("\(appState.unreadCount) unread")
                                .font(.caption)
                        }
                        .foregroundStyle(.orange)
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "person.2")
                            .font(.caption2)
                        Text("\(appState.onlineUsers.count) online")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                // Absence picker
                Menu {
                    Button("Normal (Not Absent)") {
                        appState.toggleAbsence(index: nil)
                    }
                    Divider()
                    let defs = SettingsService.shared.absenceDefinitions
                    ForEach(Array(defs.enumerated()), id: \.offset) { idx, def in
                        Button(def.title) {
                            appState.toggleAbsence(index: idx)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.fill")
                            .font(.caption2)
                        Text(absenceLabel)
                            .font(.caption)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            // Section 2: Unread messages (single clickable row)
            if appState.unreadCount > 0 {
                MenuItemRow(
                    icon: "envelope.badge.fill",
                    title: appState.unreadCount == 1
                        ? "1 Unread Message"
                        : "\(appState.unreadCount) Unread Messages"
                ) {
                    openUnreadMessages()
                }
                .padding(.vertical, 4)

                Divider()
            }

            // Section 3: Menu items
            VStack(spacing: 1) {
                MenuItemRow(icon: "square.and.pencil", title: "New Message", shortcut: "N") {
                    appState.requestCompose(user: nil)
                    openWindow(id: "compose")
                }

                MenuItemRow(icon: "macwindow", title: "Main Window") {
                    showMainWindow()
                }

                MenuItemRow(icon: "clock.arrow.circlepath", title: "Message History", shortcut: "H") {
                    openWindow(id: "message-history")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .padding(.vertical, 4)

            Divider()

            // Quit
            MenuItemRow(icon: "power", title: "Quit IPMsgX", shortcut: "Q") {
                Task {
                    await appState.stop()
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 220)
        // Open receive window when new messages arrive (auto-popup path)
        .onChange(of: appState.pendingReceiveCount) { _, count in
            guard count > 0 else { return }
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "receive")
        }
        // Handle notification banner taps — MenuBarView always exists so this always fires
        .onReceive(NotificationCenter.default.publisher(for: .showReceivedMessage)) { notification in
            guard let packetNo = notification.userInfo?["packetNo"] as? Int else { return }
            appState.showMessage(packetNo: packetNo)
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "receive")
        }
    }

    // MARK: - Actions

    /// Open all unread messages (queues them for sequential display)
    private func openUnreadMessages() {
        ensureMainWindowExists()
        NSApp.activate(ignoringOtherApps: true)
        appState.queueAllUnreadForDisplay()
    }

    /// Bring the single main window to front (Window scene is single-instance)
    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Ensure the main window exists (idempotent for Window scenes)
    private func ensureMainWindowExists() {
        openWindow(id: "main")
    }

    private var absenceLabel: String {
        if appState.isAbsent {
            let idx = SettingsService.shared.absenceIndex
            return SettingsService.shared.absenceTitle(at: idx) ?? "Absent"
        }
        return "Set Absence"
    }
}

// MARK: - Native-looking menu item row

private struct MenuItemRow: View {
    let icon: String
    let title: String
    var shortcut: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(isHovered ? .white : .secondary)
                Text(title)
                    .font(.subheadline)
                Spacer()
                if let shortcut {
                    Text("\u{2318}\(shortcut)")
                        .font(.caption)
                        .foregroundStyle(isHovered ? Color.white.opacity(0.7) : Color.secondary.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(isHovered ? .white : .primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
