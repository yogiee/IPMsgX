// IPMsgX/App/WindowObserver.swift
// Manages NSApp activation policy based on visible windows

@preconcurrency import AppKit

@MainActor
final class WindowObserver {
    private var observers: [any NSObjectProtocol] = []

    func start() {
        let nc = NotificationCenter.default

        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.updateActivationPolicy()
            }
        }

        let delayedHandler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self?.updateActivationPolicy()
            }
        }

        observers.append(nc.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil, queue: .main, using: handler
        ))

        observers.append(nc.addObserver(
            forName: NSWindow.didDeminiaturizeNotification,
            object: nil, queue: .main, using: handler
        ))

        observers.append(nc.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: nil, queue: .main, using: delayedHandler
        ))

        observers.append(nc.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil, queue: .main, using: delayedHandler
        ))
    }

    private func updateActivationPolicy() {
        let hasVisibleWindow = NSApp.windows.contains { window in
            window.isVisible &&
            !window.isMiniaturized &&
            window.level == .normal &&
            window.className != "NSStatusBarWindow" &&
            !window.className.contains("MenuBarExtra")
        }

        let desired: NSApplication.ActivationPolicy = hasVisibleWindow ? .regular : .accessory
        if NSApp.activationPolicy() != desired {
            NSApp.setActivationPolicy(desired)
            if desired == .regular {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
