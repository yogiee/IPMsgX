// IPMsgX/Services/UpdaterService.swift
// Sparkle auto-update wrapper

@preconcurrency import Sparkle
import Foundation

/// Observable wrapper around SPUStandardUpdaterController.
///
/// Update modes (stored in SettingsService):
///   0 = Auto-update: check + download + install automatically
///   1 = Download updates, ask before installing
///   2 = Disabled: no automatic checking
@Observable
@MainActor
final class UpdaterService {
    @MainActor static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController

    var updateMode: Int {
        get { SettingsService.shared.updateMode }
        set {
            SettingsService.shared.updateMode = newValue
            applyUpdateMode(newValue)
        }
    }

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        applyUpdateMode(SettingsService.shared.updateMode)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    private func applyUpdateMode(_ mode: Int) {
        let updater = controller.updater
        switch mode {
        case 0:  // Auto-update
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = true
        case 1:  // Download, ask to install
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = false
        default: // Disabled
            updater.automaticallyChecksForUpdates = false
            updater.automaticallyDownloadsUpdates = false
        }
    }
}
