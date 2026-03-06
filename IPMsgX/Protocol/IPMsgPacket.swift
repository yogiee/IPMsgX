// IPMsgX/Protocol/IPMsgPacket.swift
// Parsed IPMSG packet representation

import Foundation

struct IPMsgPacket: Sendable {
    let version: UInt32
    let packetNo: Int
    let logOnUser: String
    let hostName: String
    let command: UInt32
    let appendix: String
    let appendixOption: String?
    let utf8Option: String?

    var mode: UInt32 {
        getMode(command)
    }

    var options: UInt32 {
        getOpt(command)
    }

    func hasFlag(_ flag: UInt32) -> Bool {
        (command & flag) != 0
    }

    var hasUTF8Opt: Bool {
        hasFlag(IPMsgOption.utf8Opt.rawValue)
    }

    var hasCapUTF8Opt: Bool {
        hasFlag(IPMsgOption.capUtf8Opt.rawValue)
    }

    var hasEncryptOpt: Bool {
        hasFlag(IPMsgOption.encryptOpt.rawValue)
    }

    var hasFileAttachOpt: Bool {
        hasFlag(IPMsgOption.fileAttachOpt.rawValue)
    }

    var hasSendCheckOpt: Bool {
        hasFlag(IPMsgOption.sendCheckOpt.rawValue)
    }

    var hasSecretOpt: Bool {
        hasFlag(IPMsgOption.secretOpt.rawValue)
    }

    var hasPasswordOpt: Bool {
        hasFlag(IPMsgOption.passwordOpt.rawValue)
    }

    var hasBroadcastOpt: Bool {
        hasFlag(IPMsgOption.broadcastOpt.rawValue)
    }

    var hasMulticastOpt: Bool {
        hasFlag(IPMsgOption.multicastOpt.rawValue)
    }

    var hasAutoRetOpt: Bool {
        hasFlag(IPMsgOption.autoRetOpt.rawValue)
    }

    var hasReadCheckOpt: Bool {
        hasFlag(IPMsgOption.readCheckOpt.rawValue)
    }

    var hasAbsenceOpt: Bool {
        hasFlag(IPMsgOption.absenceOpt.rawValue)
    }

    var hasDialupOpt: Bool {
        hasFlag(IPMsgOption.dialupOpt.rawValue)
    }

    var hasEncExtMsgOpt: Bool {
        hasFlag(IPMsgOption.encExtMsgOpt.rawValue)
    }

    var hasNoAddListOpt: Bool {
        hasFlag(IPMsgOption.noAddListOpt.rawValue)
    }
}
