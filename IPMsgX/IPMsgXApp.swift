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
    @State private var showSendWindow = false
    @State private var currentReceiveMessage: ReceivedMessage?
    @State private var sendToUser: UserInfo?
    @State private var windowObserver = WindowObserver()

    var body: some Scene {
        // Main window (single instance — prevents duplicate windows)
        Window("IPMsgX", id: "main") {
            MainWindow()
                .environment(appState)
                .modelContainer(PersistenceController.sharedModelContainer)
                .task {
                    await appState.start()
                    NotificationService.shared.requestPermission()
                    windowObserver.start()
                    setAppIcon()
                    ClipboardImageManager.cleanupOldFiles()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openNewSendWindow)) { _ in
                    sendToUser = nil
                    showSendWindow = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .openSendWindowToUser)) { notification in
                    if let user = notification.userInfo?["user"] as? UserInfo {
                        sendToUser = user
                        showSendWindow = true
                    }
                }
                .sheet(isPresented: $showSendWindow, onDismiss: {
                    sendToUser = nil
                }) {
                    SendWindow(preselectedUser: sendToUser)
                        .environment(appState)
                        .frame(minWidth: 500, minHeight: 450)
                }
                .onReceive(NotificationCenter.default.publisher(for: .showReceivedMessage)) { notification in
                    guard let packetNo = notification.userInfo?["packetNo"] as? Int else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    appState.showMessage(packetNo: packetNo)
                }
                .onChange(of: appState.pendingReceiveCount) {
                    if let msg = appState.popPendingReceive() {
                        currentReceiveMessage = msg
                    }
                }
                .sheet(item: $currentReceiveMessage, onDismiss: {
                    appState.markMessageRead()
                    // Show next queued message if any
                    DispatchQueue.main.async {
                        if let next = appState.popPendingReceive() {
                            currentReceiveMessage = next
                        }
                    }
                }) { msg in
                    ReceiveWindow(message: msg)
                        .environment(appState)
                        .frame(minWidth: 400, minHeight: 300)
                }
        }
        .commands {
            IPMsgCommands(appState: appState)
        }
        .defaultSize(width: 800, height: 600)

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

/// Menu bar icon — uses Foundation notification to reliably update badge count
/// (MenuBarExtra label doesn't support @Observable tracking properly)
private struct MenuBarLabel: View {
    @State private var badge: Int = 0

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
            badge = note.userInfo?["count"] as? Int ?? 0
        }
    }

    @ViewBuilder
    private var menuBarImage: some View {
        if let img = Bundle.appResources.image(forResource: "MenuBarIcon") {
            Image(nsImage: img)
        } else if let img = NSImage(named: "MenuBarIcon") {
            Image(nsImage: img)
        } else {
            Image(systemName: "message.fill")
        }
    }
}
