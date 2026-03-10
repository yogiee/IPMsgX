// IPMsgX/Services/SettingsService.swift
// App settings — mirrors Config.h properties
// Uses UserDefaults directly (no @Observable to avoid @AppStorage conflict)

import Foundation

final class SettingsService: @unchecked Sendable {
    static let shared = SettingsService()

    private let defaults = UserDefaults.standard

    // MARK: - General

    var userName: String {
        get { defaults.string(forKey: "userName") ?? "" }
        set { defaults.set(newValue, forKey: "userName") }
    }

    var groupName: String {
        get { defaults.string(forKey: "groupName") ?? "" }
        set { defaults.set(newValue, forKey: "groupName") }
    }

    var password: String {
        get { defaults.string(forKey: "password") ?? "" }
        set { defaults.set(newValue, forKey: "password") }
    }

    var useStatusBar: Bool {
        get { defaults.object(forKey: "useStatusBar") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "useStatusBar") }
    }

    // MARK: - User List Display

    var showHostName: Bool {
        get { defaults.object(forKey: "showHostName") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showHostName") }
    }

    var showIPAddress: Bool {
        get { defaults.object(forKey: "showIPAddress") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showIPAddress") }
    }

    var showGroupName: Bool {
        get { defaults.object(forKey: "showGroupName") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showGroupName") }
    }

    var showLogOnName: Bool {
        get { defaults.object(forKey: "showLogOnName") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showLogOnName") }
    }

    // MARK: - Network

    var portNo: Int {
        get {
            let val = defaults.integer(forKey: "portNo")
            return val != 0 ? val : Int(IPMSG_DEFAULT_PORT)
        }
        set { defaults.set(newValue, forKey: "portNo") }
    }

    var dialup: Bool {
        get { defaults.bool(forKey: "dialup") }
        set { defaults.set(newValue, forKey: "dialup") }
    }

    var encryptionEnabled: Bool {
        get { defaults.object(forKey: "encryptionEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "encryptionEnabled") }
    }

    var broadcastAddresses: [String] {
        get { (defaults.array(forKey: "broadcastAddresses") as? [String]) ?? [] }
        set { defaults.set(newValue, forKey: "broadcastAddresses") }
    }

    // MARK: - Send

    var quoteString: String {
        get { defaults.string(forKey: "quoteString") ?? "> " }
        set { defaults.set(newValue, forKey: "quoteString") }
    }

    var openNewOnDockClick: Bool {
        get { defaults.object(forKey: "openNewOnDockClick") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "openNewOnDockClick") }
    }

    var sealCheckDefault: Bool {
        get { defaults.bool(forKey: "sealCheckDefault") }
        set { defaults.set(newValue, forKey: "sealCheckDefault") }
    }

    var hideReceiveWindowOnReply: Bool {
        get { defaults.object(forKey: "hideReceiveWindowOnReply") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "hideReceiveWindowOnReply") }
    }

    var noticeSealOpened: Bool {
        get { defaults.object(forKey: "noticeSealOpened") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "noticeSealOpened") }
    }

    var allowSendingToMultiUser: Bool {
        get { defaults.object(forKey: "allowSendingToMultiUser") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "allowSendingToMultiUser") }
    }

    // MARK: - Receive

    var receiveSoundName: String {
        get { defaults.string(forKey: "receiveSoundName") ?? "Submarine" }
        set { defaults.set(newValue, forKey: "receiveSoundName") }
    }

    var quoteCheckDefault: Bool {
        get { defaults.bool(forKey: "quoteCheckDefault") }
        set { defaults.set(newValue, forKey: "quoteCheckDefault") }
    }

    /// When true, show macOS notification banner instead of opening receive window
    var useNotificationBanner: Bool {
        get { defaults.object(forKey: "useNotificationBanner") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "useNotificationBanner") }
    }

    var nonPopup: Bool {
        get { defaults.bool(forKey: "nonPopup") }
        set { defaults.set(newValue, forKey: "nonPopup") }
    }

    var nonPopupWhenAbsence: Bool {
        get { defaults.object(forKey: "nonPopupWhenAbsence") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "nonPopupWhenAbsence") }
    }

    var iconBoundMode: Int {
        get { defaults.integer(forKey: "iconBoundMode") }
        set { defaults.set(newValue, forKey: "iconBoundMode") }
    }

    var useClickableURL: Bool {
        get { defaults.object(forKey: "useClickableURL") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "useClickableURL") }
    }

    // MARK: - Absence

    var absenceIndex: Int {
        get {
            let val = defaults.object(forKey: "absenceIndex") as? Int ?? -1
            return val
        }
        set { defaults.set(newValue, forKey: "absenceIndex") }
    }

    var inAbsence: Bool {
        absenceIndex >= 0
    }

    var absenceDefinitions: [AbsenceDefinition] {
        get {
            guard let data = defaults.data(forKey: "absenceDefinitions"),
                  let defs = try? JSONDecoder().decode([AbsenceDefinition].self, from: data) else {
                return Self.defaultAbsenceDefinitions
            }
            return defs
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "absenceDefinitions")
            }
        }
    }

    func absenceTitle(at index: Int) -> String? {
        guard index >= 0, index < absenceDefinitions.count else { return nil }
        return absenceDefinitions[index].title
    }

    func absenceMessage(at index: Int) -> String? {
        guard index >= 0, index < absenceDefinitions.count else { return nil }
        return absenceDefinitions[index].message
    }

    // MARK: - Log

    var standardLogEnabled: Bool {
        get { defaults.object(forKey: "standardLogEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "standardLogEnabled") }
    }

    var logChainedWhenOpen: Bool {
        get { defaults.bool(forKey: "logChainedWhenOpen") }
        set { defaults.set(newValue, forKey: "logChainedWhenOpen") }
    }

    var standardLogFile: String {
        get { defaults.string(forKey: "standardLogFile") ?? "~/Library/Logs/IPMsgX.log" }
        set { defaults.set(newValue, forKey: "standardLogFile") }
    }

    var alternateLogEnabled: Bool {
        get { defaults.bool(forKey: "alternateLogEnabled") }
        set { defaults.set(newValue, forKey: "alternateLogEnabled") }
    }

    var alternateLogFile: String {
        get { defaults.string(forKey: "alternateLogFile") ?? "~/Library/Logs/IPMsgX-important.log" }
        set { defaults.set(newValue, forKey: "alternateLogFile") }
    }

    // MARK: - RSA Key Cache

    var rsa2048PublicKeyExponent: Int {
        get { defaults.integer(forKey: "rsa2048PublicKeyExponent") }
        set { defaults.set(newValue, forKey: "rsa2048PublicKeyExponent") }
    }

    var rsa1024PublicKeyExponent: Int {
        get { defaults.integer(forKey: "rsa1024PublicKeyExponent") }
        set { defaults.set(newValue, forKey: "rsa1024PublicKeyExponent") }
    }

    var rsa2048PublicKeyModulus: Data? {
        get { defaults.data(forKey: "rsa2048PublicKeyModulus") }
        set { defaults.set(newValue, forKey: "rsa2048PublicKeyModulus") }
    }

    var rsa1024PublicKeyModulus: Data? {
        get { defaults.data(forKey: "rsa1024PublicKeyModulus") }
        set { defaults.set(newValue, forKey: "rsa1024PublicKeyModulus") }
    }

    // MARK: - Refuse Conditions

    var refuseConditions: [RefuseCondition] {
        get {
            guard let data = defaults.data(forKey: "refuseConditions"),
                  let conds = try? JSONDecoder().decode([RefuseCondition].self, from: data) else {
                return []
            }
            return conds
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "refuseConditions")
            }
        }
    }

    // MARK: - Defaults

    private static let defaultAbsenceDefinitions: [AbsenceDefinition] = [
        AbsenceDefinition(title: "Not at desk", message: "I'm not at my desk right now."),
        AbsenceDefinition(title: "In a meeting", message: "I'm currently in a meeting."),
        AbsenceDefinition(title: "Out to lunch", message: "I'm out to lunch right now."),
        AbsenceDefinition(title: "Away", message: "I'm away from my computer."),
    ]

    private init() {}
}

struct AbsenceDefinition: Codable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var message: String
}
