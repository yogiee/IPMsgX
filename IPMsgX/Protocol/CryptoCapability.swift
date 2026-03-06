// IPMsgX/Protocol/CryptoCapability.swift
// Encryption capability negotiation
// Ported from CryptoCapability.h/m

import Foundation

struct CryptoCapability: Sendable, CustomStringConvertible {
    var supportBlowfish128: Bool = false
    var supportAES256: Bool = false
    var supportRSA1024: Bool = false
    var supportRSA2048: Bool = false
    var supportPacketNoIV: Bool = false
    var supportEncodeBase64: Bool = false
    var supportSignSHA1: Bool = false
    var supportSignSHA256: Bool = false

    var supportEncryption: Bool {
        (supportAES256 || supportBlowfish128) && (supportRSA2048 || supportRSA1024)
    }

    var supportFingerPrint: Bool {
        supportRSA2048 && supportSignSHA1
    }

    // Encode to protocol flags
    func encode() -> UInt32 {
        var flags: UInt32 = 0
        if supportRSA1024       { flags |= IPMsgEncFlag.rsa1024.rawValue }
        if supportRSA2048       { flags |= IPMsgEncFlag.rsa2048.rawValue }
        if supportBlowfish128   { flags |= IPMsgEncFlag.blowfish128.rawValue }
        if supportAES256        { flags |= IPMsgEncFlag.aes256.rawValue }
        if supportPacketNoIV    { flags |= IPMsgEncFlag.packetNoIV.rawValue }
        if supportEncodeBase64  { flags |= IPMsgEncFlag.encodeBase64.rawValue }
        if supportSignSHA1      { flags |= IPMsgEncFlag.signSHA1.rawValue }
        if supportSignSHA256    { flags |= IPMsgEncFlag.signSHA256.rawValue }
        return flags
    }

    // Decode from protocol flags
    static func decode(_ flags: UInt32) -> CryptoCapability {
        CryptoCapability(
            supportBlowfish128: (flags & IPMsgEncFlag.blowfish128.rawValue) != 0,
            supportAES256:      (flags & IPMsgEncFlag.aes256.rawValue) != 0,
            supportRSA1024:     (flags & IPMsgEncFlag.rsa1024.rawValue) != 0,
            supportRSA2048:     (flags & IPMsgEncFlag.rsa2048.rawValue) != 0,
            supportPacketNoIV:  (flags & IPMsgEncFlag.packetNoIV.rawValue) != 0,
            supportEncodeBase64:(flags & IPMsgEncFlag.encodeBase64.rawValue) != 0,
            supportSignSHA1:    (flags & IPMsgEncFlag.signSHA1.rawValue) != 0,
            supportSignSHA256:  (flags & IPMsgEncFlag.signSHA256.rawValue) != 0
        )
    }

    // Find mutually supported capabilities
    func matched(with other: CryptoCapability) -> CryptoCapability {
        CryptoCapability(
            supportBlowfish128: supportBlowfish128 && other.supportBlowfish128,
            supportAES256:      supportAES256 && other.supportAES256,
            supportRSA1024:     supportRSA1024 && other.supportRSA1024,
            supportRSA2048:     supportRSA2048 && other.supportRSA2048,
            supportPacketNoIV:  supportPacketNoIV && other.supportPacketNoIV,
            supportEncodeBase64:supportEncodeBase64 && other.supportEncodeBase64,
            supportSignSHA1:    supportSignSHA1 && other.supportSignSHA1,
            supportSignSHA256:  supportSignSHA256 && other.supportSignSHA256
        )
    }

    var description: String {
        "CryptoCapability[enc=\(supportEncryption),fp=\(supportFingerPrint)](" +
        "AES256=\(supportAES256),BF128=\(supportBlowfish128)," +
        "RSA2048=\(supportRSA2048),RSA1024=\(supportRSA1024)," +
        "pktIV=\(supportPacketNoIV),b64=\(supportEncodeBase64)," +
        "sha256=\(supportSignSHA256),sha1=\(supportSignSHA1))"
    }
}
