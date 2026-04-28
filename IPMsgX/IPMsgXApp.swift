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

@main
struct IPMsgXApp: App {
    @State private var appState = AppState()
    private let updaterService = UpdaterService.shared
    @State private var windowObserver = WindowObserver()

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
        // Main window (single instance — prevents duplicate windows)
        Window("IPMsgX", id: "main") {
            MainWindowProxy(appState: appState)
                .environment(appState)
                .modelContainer(PersistenceController.sharedModelContainer)
                .task {
                    await appState.start()
                    NotificationService.shared.requestPermission()
                    windowObserver.start()
                    setAppIcon()
                    ClipboardImageManager.cleanupOldFiles()
                }
        }
        .commands {
            IPMsgCommands(appState: appState)
        }
        .defaultSize(width: 800, height: 600)

        // Standalone receive window — shown by MenuBarView, never needs the main window
        Window("Message Received", id: "receive") {
            ReceiveWindowContainer()
                .environment(appState)
                .modelContainer(PersistenceController.sharedModelContainer)
        }
        .defaultSize(width: 480, height: 380)

        // Compose window — standalone, opens without bringing the main window to front
        Window("New Message", id: "compose") {
            SendWindow()
                .environment(appState)
        }
        .defaultSize(width: 500, height: 450)

        // Message History window
        Window("Message History", id: "message-history") {
            MessageHistoryView()
                .modelContainer(PersistenceController.sharedModelContainer)
        }
        .defaultSize(width: 700, height: 500)
        .keyboardShortcut("h", modifiers: [.command, .shift])

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

    /// Set the app icon programmatically for task switcher (SPM doesn't auto-apply AppIcon from asset catalog)
    private func setAppIcon() {
        // Load standalone PNG from resource bundle (asset catalog imagesets aren't reliable in SPM)
        if let url = Bundle.appResources.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
}

/// Wraps MainWindow so that `.openNewSendWindow` and `.openSendWindowToUser` notifications
/// can call `openWindow(id: "compose")` — `@Environment(\.openWindow)` is only available
/// inside a View, not directly in the App body.
private struct MainWindowProxy: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MainWindow()
            .onReceive(NotificationCenter.default.publisher(for: .openNewSendWindow)) { _ in
                appState.requestCompose(user: nil)
                openWindow(id: "compose")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSendWindowToUser)) { notification in
                if let user = notification.userInfo?["user"] as? UserInfo {
                    appState.requestCompose(user: user)
                    openWindow(id: "compose")
                }
            }
    }
}

/// Standalone receive window container — manages sequential display of pending messages.
/// Lives in its own Window scene so it never requires the main window to be visible.
private struct ReceiveWindowContainer: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismissWindow
    @State private var currentMessage: ReceivedMessage?
    @State private var lastPacketNo: Int?

    var body: some View {
        Group {
            if let msg = currentMessage {
                ReceiveWindow(message: msg, onClose: handleClose)
            } else {
                Color.clear.frame(width: 480, height: 380)
            }
        }
        .onAppear { showNext() }
        .onChange(of: appState.pendingReceiveCount) { showNext() }
    }

    private func showNext() {
        guard currentMessage == nil else { return }
        if let msg = appState.popPendingReceive() {
            currentMessage = msg
            lastPacketNo = msg.packetNo
        } else {
            dismissWindow()
        }
    }

    private func handleClose() {
        if let pn = lastPacketNo {
            appState.markRead(packetNo: pn)
        }
        currentMessage = nil
        // Yield to the run loop so SwiftUI removes the old view before loading the next
        DispatchQueue.main.async { showNext() }
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
