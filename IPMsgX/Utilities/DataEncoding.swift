// IPMsgX/Utilities/DataEncoding.swift
// Hex/Base64 encoding and byte manipulation for IPMSG protocol
// Ported from NSData+IPMessenger.m

import Foundation

extension Data {

    // MARK: - Hex Encoding

    private static let hexEncTable: [UInt8] = Array("0123456789abcdef".utf8)

    private static let hexDecTable: [UInt8] = {
        var table = [UInt8](repeating: 0xFF, count: 128)
        for i: UInt8 in 0...9 {
            table[Int(Character("\(i)").asciiValue!)] = i
        }
        table[Int(Character("a").asciiValue!)] = 10
        table[Int(Character("b").asciiValue!)] = 11
        table[Int(Character("c").asciiValue!)] = 12
        table[Int(Character("d").asciiValue!)] = 13
        table[Int(Character("e").asciiValue!)] = 14
        table[Int(Character("f").asciiValue!)] = 15
        table[Int(Character("A").asciiValue!)] = 10
        table[Int(Character("B").asciiValue!)] = 11
        table[Int(Character("C").asciiValue!)] = 12
        table[Int(Character("D").asciiValue!)] = 13
        table[Int(Character("E").asciiValue!)] = 14
        table[Int(Character("F").asciiValue!)] = 15
        return table
    }()

    var hexEncodedString: String {
        var chars: [UInt8] = []
        chars.reserveCapacity(count * 2)
        for byte in self {
            chars.append(Self.hexEncTable[Int(byte >> 4)])
            chars.append(Self.hexEncTable[Int(byte & 0x0F)])
        }
        return String(bytes: chars, encoding: .ascii)!
    }

    init?(hexString: String) {
        let ascii = Array(hexString.utf8)
        guard ascii.count % 2 == 0 else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(ascii.count / 2)

        for i in stride(from: 0, to: ascii.count, by: 2) {
            guard ascii[i] < 128, ascii[i + 1] < 128 else { return nil }
            let hi = Self.hexDecTable[Int(ascii[i])]
            let lo = Self.hexDecTable[Int(ascii[i + 1])]
            guard hi <= 15, lo <= 15 else { return nil }
            bytes.append((hi << 4) | lo)
        }

        self.init(bytes)
    }

    // MARK: - Binary String Encoding (Hex or Base64)

    func binaryEncodedString(base64: Bool) -> String {
        if base64 {
            return self.base64EncodedString()
        } else {
            return hexEncodedString
        }
    }

    init?(binaryEncodedString string: String, base64: Bool) {
        if base64 {
            guard let data = Data(base64Encoded: string) else { return nil }
            self = data
        } else {
            guard let data = Data(hexString: string) else { return nil }
            self = data
        }
    }

    // MARK: - Byte Reversal

    var reversedBytes: Data {
        Data(self.reversed())
    }

    func reversedBytes(in range: Range<Int>) -> Data {
        guard range.lowerBound >= 0, range.upperBound <= count else { return self }
        var result = self
        let slice = Array(self[range]).reversed()
        for (i, byte) in slice.enumerated() {
            result[range.lowerBound + i] = byte
        }
        return result
    }
}
