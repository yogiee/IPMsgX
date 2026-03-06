// IPMsgX/Crypto/RSAPublicKey.swift
// RSA public key with manual ASN.1 DER encode/decode
// Replaces deprecated SecAsn1Coder from RSAPublicKey.m

import Foundation
import Security

enum RSAPublicKeyHelper {

    // MARK: - ASN.1 DER Manual Encoding

    // Encode exponent + modulus -> PKCS#1 DER -> SecKey
    static func createSecKey(exponent: UInt32, modulus: Data) -> SecKey? {
        // Build ASN.1 DER: SEQUENCE { INTEGER modulus, INTEGER exponent }
        let expBytes = withUnsafeBytes(of: exponent.bigEndian) { Array($0) }
        let derData = buildDERSequence(modulus: Array(modulus), exponent: expBytes)

        // Normalize modulus size: strip leading zeros to get actual key bit size
        // (modulus from some clients may include ASN.1 sign byte making it 257 bytes for 2048-bit)
        var normalizedModulus = modulus
        while normalizedModulus.count > 1 && normalizedModulus.first == 0 {
            normalizedModulus = normalizedModulus.dropFirst()
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: normalizedModulus.count * 8,
            kSecAttrIsPermanent as String: false,
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(
            Data(derData) as CFData,
            attributes as CFDictionary,
            &error
        ) else {
            return nil
        }

        return key
    }

    // Extract exponent + modulus from SecKey
    static func extractComponents(from key: SecKey) -> (exponent: UInt32, modulus: Data)? {
        var error: Unmanaged<CFError>?
        guard let derData = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            return nil
        }

        return parseDERSequence(derData)
    }

    // MARK: - DER Building

    private static func buildDERSequence(modulus: [UInt8], exponent: [UInt8]) -> [UInt8] {
        let modInteger = buildDERInteger(modulus)
        let expInteger = buildDERInteger(exponent)

        var sequence: [UInt8] = []
        sequence.append(0x30) // SEQUENCE tag
        let contentLength = modInteger.count + expInteger.count
        sequence.append(contentsOf: encodeDERLength(contentLength))
        sequence.append(contentsOf: modInteger)
        sequence.append(contentsOf: expInteger)

        return sequence
    }

    private static func buildDERInteger(_ bytes: [UInt8]) -> [UInt8] {
        var value = bytes

        // Strip leading zeros (but keep at least one byte)
        while value.count > 1 && value.first == 0 {
            value.removeFirst()
        }

        // If high bit is set, prepend 0x00 (positive integer)
        if let first = value.first, first & 0x80 != 0 {
            value.insert(0, at: 0)
        }

        var result: [UInt8] = [0x02] // INTEGER tag
        result.append(contentsOf: encodeDERLength(value.count))
        result.append(contentsOf: value)

        return result
    }

    private static func encodeDERLength(_ length: Int) -> [UInt8] {
        if length < 128 {
            return [UInt8(length)]
        } else if length < 256 {
            return [0x81, UInt8(length)]
        } else if length < 65536 {
            return [0x82, UInt8(length >> 8), UInt8(length & 0xFF)]
        } else {
            return [0x83, UInt8(length >> 16), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
        }
    }

    // MARK: - DER Parsing

    private static func parseDERSequence(_ data: Data) -> (exponent: UInt32, modulus: Data)? {
        let bytes = Array(data)
        var offset = 0

        // SEQUENCE tag
        guard offset < bytes.count, bytes[offset] == 0x30 else { return nil }
        offset += 1

        // Skip sequence length
        guard let _ = parseDERLength(bytes, offset: &offset) else { return nil }

        // First INTEGER: modulus
        guard let modulus = parseDERInteger(bytes, offset: &offset) else { return nil }

        // Second INTEGER: exponent
        guard let expBytes = parseDERInteger(bytes, offset: &offset) else { return nil }

        // Convert exponent bytes to UInt32
        var exp: UInt32 = 0
        for byte in expBytes {
            exp = (exp << 8) | UInt32(byte)
        }

        return (exp, Data(modulus))
    }

    private static func parseDERLength(_ bytes: [UInt8], offset: inout Int) -> Int? {
        guard offset < bytes.count else { return nil }
        let first = bytes[offset]
        offset += 1

        if first < 128 {
            return Int(first)
        }

        let numBytes = Int(first & 0x7F)
        guard offset + numBytes <= bytes.count else { return nil }

        var length = 0
        for i in 0..<numBytes {
            length = (length << 8) | Int(bytes[offset + i])
        }
        offset += numBytes
        return length
    }

    private static func parseDERInteger(_ bytes: [UInt8], offset: inout Int) -> [UInt8]? {
        guard offset < bytes.count, bytes[offset] == 0x02 else { return nil }
        offset += 1

        guard let length = parseDERLength(bytes, offset: &offset) else { return nil }
        guard offset + length <= bytes.count else { return nil }

        var value = Array(bytes[offset..<(offset + length)])
        offset += length

        // Remove leading zero padding
        while value.count > 1 && value.first == 0 {
            value.removeFirst()
        }

        return value
    }
}
