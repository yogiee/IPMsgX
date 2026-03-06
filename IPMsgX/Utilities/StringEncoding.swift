// IPMsgX/Utilities/StringEncoding.swift
// Legacy string encoding support for IPMSG protocol interop
// Ported from NSString+IPMessenger.m

import Foundation

enum StringEncoding {

    // Language-dependent legacy encoding for non-UTF8 clients
    static let legacyEncoding: String.Encoding = {
        guard let lang = Locale.preferredLanguages.first else {
            return .shiftJIS
        }
        if lang.hasPrefix("zh-Hans") {
            // Simplified Chinese: CP936 (GBK)
            let enc = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.dosChineseSimplif.rawValue)
            )
            return String.Encoding(rawValue: enc)
        } else if lang.hasPrefix("zh-Hant") {
            // Traditional Chinese: CP950 (Big5)
            let enc = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.dosChineseTrad.rawValue)
            )
            return String.Encoding(rawValue: enc)
        } else if lang.hasPrefix("ko") {
            // Korean: CP949 (UHC)
            let enc = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.dosKorean.rawValue)
            )
            return String.Encoding(rawValue: enc)
        } else {
            // Japanese: CP932 (Windows-31J / Shift_JIS)
            let enc = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)
            )
            return String.Encoding(rawValue: enc)
        }
    }()

    // Encode a Swift string to Data for wire transmission
    static func encode(string: String, utf8: Bool, nullTerminate: Bool = false) -> Data? {
        let encoding: String.Encoding = utf8 ? .utf8 : legacyEncoding

        var data: Data
        if !utf8 && legacyEncoding == .shiftJIS {
            // For SJIS, replace ¥ with \ to avoid garbling
            let replaced = string.replacingOccurrences(of: "¥", with: "\\")
            guard let d = replaced.data(using: encoding, allowLossyConversion: true) else { return nil }
            data = d
        } else {
            guard let d = string.data(using: encoding, allowLossyConversion: true) else { return nil }
            data = d
        }

        if nullTerminate {
            data.append(0)
        }

        return data
    }

    // Encode with max length, respecting character boundaries
    static func encode(string: String, utf8: Bool, nullTerminate: Bool, maxLength: Int) -> Data? {
        guard var data = encode(string: string, utf8: utf8, nullTerminate: false) else { return nil }

        let nullSize = nullTerminate ? 1 : 0
        if data.count > maxLength - nullSize {
            // Truncate at character boundary
            var pos = maxLength - 1
            let bytes = Array(data)

            if utf8 {
                // UTF-8: find character boundary (leading byte has bits 0xxxxxxx or 11xxxxxx)
                while pos > 0 && (bytes[pos] & 0xC0) == 0x80 {
                    pos -= 1
                }
            }
            data = Data(bytes[0..<pos])
        }

        if nullTerminate {
            data.append(0)
        }

        return data
    }

    // Decode Data to Swift string
    static func decode(data: Data, utf8: Bool) -> String? {
        let encoding: String.Encoding = utf8 ? .utf8 : legacyEncoding
        return String(data: data, encoding: encoding)
    }

    // Decode a C-string (null-terminated bytes)
    static func decodeBytes(_ bytes: UnsafePointer<UInt8>, length: Int, utf8: Bool) -> String? {
        let data = Data(bytes: bytes, count: length)
        return decode(data: data, utf8: utf8)
    }
}
