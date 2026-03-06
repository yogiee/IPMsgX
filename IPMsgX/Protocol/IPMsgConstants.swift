// IPMsgX/Protocol/IPMsgConstants.swift
// IPMSG Protocol Constants — ported from MessageCenter.m lines 53-310

import Foundation

// MARK: - Protocol Version & Defaults

let IPMSG_VERSION: UInt32 = 0x0001
let IPMSG_NEW_VERSION: UInt32 = 0x0003
let IPMSG_DEFAULT_PORT: UInt16 = 0x0979  // 2425
let MAX_UDPBUF: Int = 32768
let IPMSG_VER_MAC_TYPE: UInt32 = 0x00020000

let FILELIST_SEPARATOR: Character = "\u{07}"  // \a (BEL)
let HOSTLIST_SEPARATOR: Character = "\u{07}"
let MESSAGE_SEPARATOR: Character = ":"

// MARK: - Command Modes

enum IPMsgCommand: UInt32 {
    case noOperation        = 0x00000000
    case brEntry            = 0x00000001
    case brExit             = 0x00000002
    case ansEntry           = 0x00000003
    case brAbsence          = 0x00000004
    case brIsGetList        = 0x00000010
    case okGetList          = 0x00000011
    case getList            = 0x00000012
    case ansList            = 0x00000013
    case ansListDict        = 0x00000014
    case brIsGetList2       = 0x00000018
    case sendMsg            = 0x00000020
    case recvMsg            = 0x00000021
    case readMsg            = 0x00000030
    case delMsg             = 0x00000031
    case ansReadMsg         = 0x00000032
    case getInfo            = 0x00000040
    case sendInfo           = 0x00000041
    case getAbsenceInfo     = 0x00000050
    case sendAbsenceInfo    = 0x00000051
    case getFileData        = 0x00000060
    case releaseFiles       = 0x00000061
    case getDirFiles        = 0x00000062
    case getPubKey          = 0x00000072
    case ansPubKey          = 0x00000073
}

// MARK: - Option Flags (for all commands)

struct IPMsgOption: OptionSet, Sendable {
    let rawValue: UInt32

    // General options
    static let absenceOpt       = IPMsgOption(rawValue: 0x00000100)
    static let serverOpt        = IPMsgOption(rawValue: 0x00000200)
    static let dialupOpt        = IPMsgOption(rawValue: 0x00010000)
    static let fileAttachOpt    = IPMsgOption(rawValue: 0x00200000)
    static let encryptOpt       = IPMsgOption(rawValue: 0x00400000)
    static let utf8Opt          = IPMsgOption(rawValue: 0x00800000)
    static let capUtf8Opt       = IPMsgOption(rawValue: 0x01000000)
    static let encExtMsgOpt     = IPMsgOption(rawValue: 0x04000000)
    static let clipboardOpt     = IPMsgOption(rawValue: 0x08000000)
    static let capFileEncOpt    = IPMsgOption(rawValue: 0x00040000)
    static let capIPDictOpt     = IPMsgOption(rawValue: 0x02000000)
    static let dirMaster        = IPMsgOption(rawValue: 0x10000000)

    // SENDMSG-specific options
    static let sendCheckOpt     = IPMsgOption(rawValue: 0x00000100)
    static let secretOpt        = IPMsgOption(rawValue: 0x00000200)
    static let broadcastOpt     = IPMsgOption(rawValue: 0x00000400)
    static let multicastOpt     = IPMsgOption(rawValue: 0x00000800)
    static let autoRetOpt       = IPMsgOption(rawValue: 0x00002000)
    static let retryOpt         = IPMsgOption(rawValue: 0x00004000)
    static let passwordOpt      = IPMsgOption(rawValue: 0x00008000)
    static let noLogOpt         = IPMsgOption(rawValue: 0x00020000)
    static let noAddListOpt     = IPMsgOption(rawValue: 0x00080000)
    static let readCheckOpt     = IPMsgOption(rawValue: 0x00100000)

    static let secretExOpt: IPMsgOption = [.readCheckOpt, .secretOpt]

    // File transfer options
    static let encFileOpt       = IPMsgOption(rawValue: 0x00000800)

    // Full capability spec for entry/absence broadcasts
    static let allStat: IPMsgOption = [
        .absenceOpt, .serverOpt, .dialupOpt, .fileAttachOpt,
        .clipboardOpt, .encryptOpt, .capUtf8Opt,
        .encExtMsgOpt, .capFileEncOpt, .capIPDictOpt, .dirMaster
    ]
}

// MARK: - Encryption Flags

struct IPMsgEncFlag: OptionSet, Sendable {
    let rawValue: UInt32

    static let rsa1024          = IPMsgEncFlag(rawValue: 0x00000002)
    static let rsa2048          = IPMsgEncFlag(rawValue: 0x00000004)
    static let rsa4096          = IPMsgEncFlag(rawValue: 0x00000008)
    static let blowfish128      = IPMsgEncFlag(rawValue: 0x00020000)
    static let aes256           = IPMsgEncFlag(rawValue: 0x00100000)
    static let packetNoIV       = IPMsgEncFlag(rawValue: 0x00800000)
    static let encodeBase64     = IPMsgEncFlag(rawValue: 0x01000000)
    static let signSHA1         = IPMsgEncFlag(rawValue: 0x20000000)
    static let signSHA256       = IPMsgEncFlag(rawValue: 0x40000000)

    static let commonKeys: IPMsgEncFlag = [.blowfish128, .aes256]
}

// MARK: - File Types

enum IPMsgFileType: UInt32, Sendable {
    case regular        = 0x00000001
    case directory      = 0x00000002
    case retParent      = 0x00000003
    case symlink        = 0x00000004
    case clipboard      = 0x00000020
}

// MARK: - File Attribute Options

struct IPMsgFileAttr: OptionSet, Sendable {
    let rawValue: UInt32

    static let readOnly         = IPMsgFileAttr(rawValue: 0x00000100)
    static let hidden           = IPMsgFileAttr(rawValue: 0x00001000)
    static let exHidden         = IPMsgFileAttr(rawValue: 0x00002000)
    static let archive          = IPMsgFileAttr(rawValue: 0x00004000)
    static let system           = IPMsgFileAttr(rawValue: 0x00008000)
}

// MARK: - Extended File Attributes

enum IPMsgFileExtAttr: UInt32, Sendable {
    case uid            = 0x00000001
    case userName       = 0x00000002
    case gid            = 0x00000003
    case groupName      = 0x00000004
    case clipboardPos   = 0x00000008
    case perm           = 0x00000010
    case ctime          = 0x00000013
    case mtime          = 0x00000014
    case atime          = 0x00000015
    case createTime     = 0x00000016
    case creator        = 0x00000020
    case fileType       = 0x00000021
    case finderInfo     = 0x00000022
}

// MARK: - Helper Functions

func getMode(_ command: UInt32) -> UInt32 {
    command & 0x000000FF
}

func getOpt(_ command: UInt32) -> UInt32 {
    command & 0xFFFFFF00
}
