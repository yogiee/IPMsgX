// IPMsgX/Models/UserInfo.swift
// Online user information — ported from UserInfo.h

import Foundation

struct UserIdentifier: Hashable, Sendable {
    let logOnName: String
    let ipAddress: String
}

struct UserInfo: Identifiable, Hashable, Sendable {
    let id: UserIdentifier
    let hostName: String
    let logOnName: String
    let ipAddress: String
    let port: UInt16

    var userName: String
    var groupName: String?
    var version: String?
    var inAbsence: Bool
    var lastSeen: Date = Date()
    var dialupConnect: Bool
    var supportsAttachment: Bool
    var supportsEncrypt: Bool
    var supportsEncExtMsg: Bool
    var supportsUTF8: Bool
    var cryptoCapability: CryptoCapability?
    var publicKey: RSAPublicKeyInfo?
    var fingerPrint: Data?

    init(
        hostName: String,
        logOnName: String,
        ipAddress: String,
        port: UInt16 = UInt16(IPMSG_DEFAULT_PORT)
    ) {
        self.id = UserIdentifier(logOnName: logOnName, ipAddress: ipAddress)
        self.hostName = hostName
        self.logOnName = logOnName
        self.ipAddress = ipAddress
        self.port = port
        self.userName = logOnName
        self.inAbsence = false
        self.dialupConnect = false
        self.supportsAttachment = false
        self.supportsEncrypt = false
        self.supportsEncExtMsg = false
        self.supportsUTF8 = false
    }

    var displayName: String {
        if !userName.isEmpty && userName != logOnName {
            return userName
        }
        return logOnName
    }

    var summaryString: String {
        "\(displayName) (\(hostName))"
    }

    // Hashable based on identity
    static func == (lhs: UserInfo, rhs: UserInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// RSA public key info stored with user
struct RSAPublicKeyInfo: Sendable, Hashable {
    let exponent: UInt32
    let modulus: Data
    var keySizeInBits: Int {
        // Strip leading zeros to get actual bit length
        // (modulus may include ASN.1 sign byte making it 257 bytes for 2048-bit key)
        var mod = modulus[modulus.startIndex...]
        while mod.count > 1 && mod.first == 0 {
            mod = mod.dropFirst()
        }
        return mod.count * 8
    }
}
