// IPMsgX/IPMsgXApp.swift
// @main App — SwiftUI lifecycle, scenes, commands

import SwiftUI
import SwiftData

/// Safe resource bundle accessor — Bundle.main for .app bundles, Bundle.module for SPM debug
extension Bundle {
    static var appResources: Bundle {
        // In a proper .app bundle, bundleIdentifier is set from Info.plist
        // In SPM debug mode, it's nil and we need Bundle.module (SPM's resource bundle)
        if Bundle.main.bundleIdentifier != nil {
            return .main
        }
        return .module
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState else { return .terminateNow }
        Task { @MainActor in
            await appState.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // NOTE: we intentionally do NOT implement applicationShouldHandleReopen. That callback fires
    // on Dock clicks AND on notification-toast clicks, so spawning a Send window there would
    // wrongly pop a Send window on top of an opened message. The default reopen behavior (bring
    // existing windows forward) is what we want. Start a new message via ⌘N, the menu bar, or
    // the Dock right-click menu.

    /// Dock right-click / click-and-hold menu. macOS appends the standard items (Options,
    /// Quit) below ours automatically, so we only add the app-specific actions.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let send = NSMenuItem(title: "Send Message", action: #selector(dockSendMessage), keyEquivalent: "")
        send.target = self
        menu.addItem(send)

        let history = NSMenuItem(title: "Show History", action: #selector(dockShowHistory), keyEquivalent: "")
        history.target = self
        menu.addItem(history)

        return menu
    }

    @objc private func dockSendMessage() {
        NotificationCenter.default.post(name: .openNewSendWindow, object: nil)
    }

    @objc private func dockShowHistory() {
        NotificationCenter.default.post(name: .openHistoryWindow, object: nil)
    }
}

@main
struct IPMsgXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    private let updaterService = UpdaterService.shared

    init() {
        // Redirect stderr to a log file so NSLog output is visible even in release builds.
        // NSLog writes to both the unified logging system (where strings become <private>)
        // AND to raw stderr (fd=2). By dup2-ing stderr to a file before any logging fires,
        // all [CRYPTO] and other NSLog messages land in ~/Library/Logs/IPMsgX/debug.log
        // with full text, unaffected by the privacy system.
        // Usage: tail -f ~/Library/Logs/IPMsgX/debug.log
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Logs/IPMsgX")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logFile = logsDir.appendingPathComponent("debug.log")
        // Rotate: keep last session only (truncate on launch)
        try? "=== IPMsgX session started: \(Date()) ===\n".write(to: logFile, atomically: true, encoding: .utf8)
        if let cPath = logFile.path.cString(using: .utf8) {
            let fd = open(cPath, O_WRONLY | O_APPEND, 0o644)
            if fd >= 0 {
                dup2(fd, STDERR_FILENO)
                close(fd)
            }
        }
    }

    var body: some Scene {
        // PRIMARY interface — the Send window. This is the FIRST scene, so SwiftUI opens
        // it at launch, mirroring the original IP Messenger where the send window is the hub.
        Window("New Message", id: "compose") {
            SendWindow()
                .environment(appState)
                .task { await bootstrap() }
        }
        .defaultSize(width: 680, height: 560)
        .commands {
            IPMsgCommands(appState: appState)
        }

        // History window — persisted conversations (SwiftData/SQLite) grouped by peer, with
        // search and per-conversation chat threads. Survives quit/relaunch.
        Window("History", id: "main") {
            MessageHistoryView()
                .environment(appState)
                .modelContainer(PersistenceController.sharedModelContainer)
                .task { await bootstrap() }
        }
        .defaultSize(width: 820, height: 600)
        .keyboardShortcut("h", modifiers: [.command, .shift])

        // Receive windows — one per message, keyed by packet number. Opening multiple distinct
        // packets yields multiple windows (macOS cascades them); re-opening the same packet just
        // brings its existing window forward.
        WindowGroup(id: "receive", for: Int.self) { $packetNo in
            ReceiveWindowHost(packetNo: packetNo)
                .environment(appState)
                .modelContainer(PersistenceController.sharedModelContainer)
        }
        .defaultSize(width: 480, height: 380)
        .restorationBehavior(.disabled)  // don't resurrect stale message windows on relaunch

        // Menu bar extra
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        // Settings
        Settings {
            SettingsView()
        }
    }

    /// One-time app bootstrap, attached to whichever window opens first. Idempotent.
    private func bootstrap() async {
        appDelegate.appState = appState
        await appState.bootstrap()
        setAppIcon()
    }

    /// Set the app icon programmatically for task switcher (SPM doesn't auto-apply AppIcon from asset catalog)
    private func setAppIcon() {
        // Load standalone PNG from resource bundle (asset catalog imagesets aren't reliable in SPM)
        if let url = Bundle.appResources.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
}

/// Hosts a single received message in its own window, looked up by packet number.
/// Opening a window for a packet marks that message read.
private struct ReceiveWindowHost: View {
    let packetNo: Int?
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var message: ReceivedMessage? {
        guard let packetNo else { return nil }
        return appState.receivedMessages.first { $0.packetNo == packetNo }
    }

    var body: some View {
        Group {
            if let message {
                ReceiveWindow(message: message)
                    .onAppear { appState.markRead(packetNo: message.packetNo) }
            } else {
                // Cold launch from a notification, or message culled — not in memory.
                ContentUnavailableView(
                    "Message Unavailable",
                    systemImage: "envelope.open",
                    description: Text("This message is no longer available. Open History to review past messages.")
                )
                .frame(width: 380, height: 220)
            }
        }
    }
}

/// Menu bar icon — uses Foundation notification to reliably update badge count
/// (MenuBarExtra label doesn't support @Observable tracking properly)
///
/// Notification behaviour:
///   • New message arrives → 2-loop outline ↔ fill animation, then settles on
///                           message.fill while unread > 0
///   • All messages read   → reverts to custom branded icon
private struct MenuBarLabel: View {
    @State private var badge: Int = 0
    @State private var showFilled: Bool = false
    @State private var animationTask: Task<Void, Never>? = nil

    var body: some View {
        HStack(spacing: 2) {
            menuBarImage
            if badge > 0 {
                Text("\(badge)")
                    .font(.caption2)
                    .monospacedDigit()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .badgeCountChanged)) { note in
            let newBadge = note.userInfo?["count"] as? Int ?? 0
            let increased = newBadge > badge
            badge = newBadge

            if increased {
                animationTask?.cancel()
                animationTask = Task { await animateArrival() }
            } else if badge == 0 {
                animationTask?.cancel()
                showFilled = false
            }
        }
    }

    @ViewBuilder
    private var menuBarImage: some View {
        if badge > 0 || showFilled {
            Image(systemName: showFilled ? "message.fill" : "message")
        } else {
            if let img = Bundle.appResources.image(forResource: "MenuBarIcon") {
                Image(nsImage: img)
            } else if let img = NSImage(named: "MenuBarIcon") {
                Image(nsImage: img)
            } else {
                Image(systemName: "message.fill")
            }
        }
    }

    /// Toggles outline ↔ fill 4 times (2 full loops) at 350 ms per half-cycle,
    /// then settles on filled while there are unread messages.
    private func animateArrival() async {
        showFilled = false
        for _ in 0..<4 {
            showFilled.toggle()
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                break
            }
        }
        showFilled = badge > 0
    }
}
