// IPMsgX/Services/UpdaterService.swift
// Sparkle auto-update wrapper (schedule-based, matching the WallP/Typa/MINT pattern).

@preconcurrency import Sparkle
import Foundation

/// How often IPMsgX checks the appcast for a newer release.
enum UpdateCheckSchedule: Int, CaseIterable, Identifiable {
    case daily = 86400
    case weekly = 604800
    case manual = 0

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .daily:  "Every day"
        case .weekly: "Every week"
        case .manual: "Manual only"
        }
    }
}

/// Thin wrapper around Sparkle's `SPUStandardUpdaterController`. A single shared instance drives
/// auto-update for every window. The schedule persists in UserDefaults and is applied to the live
/// updater whenever it changes.
@Observable
@MainActor
final class UpdaterService {
    static let shared = UpdaterService()

    private static let scheduleKey = "ipmsgx.updateCheckSchedule"

    private let controller: SPUStandardUpdaterController

    var updateCheckSchedule: UpdateCheckSchedule {
        get {
            let raw = UserDefaults.standard.integer(forKey: Self.scheduleKey)
            return UpdateCheckSchedule(rawValue: raw) ?? .weekly
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.scheduleKey)
            applySchedule(newValue)
        }
    }

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let raw = UserDefaults.standard.integer(forKey: Self.scheduleKey)
        applySchedule(UpdateCheckSchedule(rawValue: raw) ?? .weekly)
    }

    /// Manual "Check for Updates…" — always shows UI, even on the Manual schedule.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    private func applySchedule(_ schedule: UpdateCheckSchedule) {
        let updater = controller.updater
        switch schedule {
        case .daily, .weekly:
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = true
            updater.updateCheckInterval = TimeInterval(schedule.rawValue)
        case .manual:
            updater.automaticallyChecksForUpdates = false
            updater.automaticallyDownloadsUpdates = false
        }
    }
}
