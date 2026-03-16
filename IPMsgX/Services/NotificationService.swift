// IPMsgX/Services/NotificationService.swift
// macOS notifications for incoming messages
// Uses UNUserNotificationCenter when available (proper .app bundle).
// For SPM executables without bundle identity, plays a system sound only
// (UNUserNotificationCenter and NSAppleScript both crash/fail without a bundle).

import Foundation
import UserNotifications
import AppKit

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private var center: UNUserNotificationCenter?
    private(set) var hasBannerSupport = false

    private override init() {
        super.init()
    }

    func requestPermission() {
        // UNUserNotificationCenter requires a proper .app bundle with a bundle identifier.
        // SPM executables don't have one — calling .current() crashes with an assertion.
        guard Bundle.main.bundleIdentifier != nil else {
            return
        }

        let c = UNUserNotificationCenter.current()
        c.delegate = self
        self.center = c
        hasBannerSupport = true
        c.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func postIncomingMessage(_ msg: ReceivedMessage) {
        // Always play a sound
        NSSound(named: "Ping")?.play()

        // Post banner only if UNUserNotificationCenter is available
        guard let center else { return }

        let content = UNMutableNotificationContent()
        content.title = msg.fromUser.displayName
        content.body = msg.isSealed ? "Sealed message" : String(msg.message.prefix(200))
        content.sound = .default
        content.userInfo = ["packetNo": msg.packetNo]

        let request = UNNotificationRequest(
            identifier: "msg-\(msg.packetNo)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func postSealOpened(by user: UserInfo, packetNo: Int) {
        NSSound(named: "Glass")?.play()

        guard let center else { return }

        let content = UNMutableNotificationContent()
        content.title = "Seal Opened"
        content.body = "\(user.displayName) opened your sealed message"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "seal-\(packetNo)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    // MARK: - Notification Removal

    func removeNotification(for packetNo: Int) {
        center?.removeDeliveredNotifications(withIdentifiers: ["msg-\(packetNo)"])
    }

    func removeNotifications(for packetNos: [Int]) {
        guard !packetNos.isEmpty else { return }
        center?.removeDeliveredNotifications(withIdentifiers: packetNos.map { "msg-\($0)" })
    }

    func removeAllMessageNotifications() {
        guard let center else { return }
        center.getDeliveredNotifications { notifications in
            let ids = notifications
                .filter { $0.request.identifier.hasPrefix("msg-") }
                .map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let settings = SettingsService.shared
        let isActive = await MainActor.run { NSApp.isActive }

        if !isActive {
            return [.banner, .sound]
        }

        if settings.useNotificationBanner || settings.nonPopup {
            return [.banner, .sound]
        }

        return []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let packetNo = userInfo["packetNo"] as? Int else { return }

        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(
                name: .showReceivedMessage,
                object: nil,
                userInfo: ["packetNo": packetNo]
            )
        }
    }
}
