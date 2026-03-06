// IPMsgX/Protocol/IPMsgPacketParser.swift
// Parse raw IPMSG packet data into IPMsgPacket
// Wire format: "1:packetNo:logOnUser:hostName:command:appendix"
// Ported from MessageCenter.m:1582-1712

import Foundation
import Network

enum IPMsgPacketParser {

    static func parse(data: Data, from endpoint: NWEndpoint? = nil) -> IPMsgPacket? {
        // Work with a mutable copy for NULL handling
        var bytes = Array(data)

        // Strip trailing NULLs to find real length
        while !bytes.isEmpty && bytes.last == 0 {
            bytes.removeLast()
        }
        guard !bytes.isEmpty else { return nil }

        // Find the NULL-separated option sections BEFORE tokenizing
        // The data may contain: mainPacket\0option1\0\noption2\0
        bytes.append(0) // ensure null termination for C-string ops

        let fullData = Data(bytes)

        // Find first NULL separator (separates appendix from option1)
        var option1String: String?
        var option2String: String?

        // Scan for option sections after the main packet
        if let mainEnd = fullData.firstIndex(of: 0) {
            let afterMain = fullData.index(after: mainEnd)
            if afterMain < fullData.endIndex {
                let optionData = fullData[afterMain...]
                // option1 extends until the next NULL
                if let opt1End = optionData.firstIndex(of: 0) {
                    let opt1Data = optionData[afterMain..<opt1End]
                    if !opt1Data.isEmpty {
                        option1String = String(data: Data(opt1Data), encoding: .utf8)
                            ?? String(data: Data(opt1Data), encoding: .shiftJIS)
                    }
                    // After option1\0, there may be \n then UTF-8 option2
                    let afterOpt1 = optionData.index(after: opt1End)
                    if afterOpt1 < optionData.endIndex {
                        // Skip the \n separator if present
                        var opt2Start = afterOpt1
                        if optionData[opt2Start] == 0x0A { // \n
                            opt2Start = optionData.index(after: opt2Start)
                        }
                        if opt2Start < optionData.endIndex {
                            // option2 extends to the next NULL
                            if let opt2End = optionData[opt2Start...].firstIndex(of: 0) {
                                let opt2Data = optionData[opt2Start..<opt2End]
                                if !opt2Data.isEmpty {
                                    option2String = String(data: Data(opt2Data), encoding: .utf8)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Now parse the main colon-separated packet
        // Take only up to the first NULL for the main packet string
        let mainBytes: Data
        if let nullIndex = fullData.firstIndex(of: 0) {
            mainBytes = fullData[fullData.startIndex..<nullIndex]
        } else {
            mainBytes = fullData
        }

        guard let mainString = String(data: mainBytes, encoding: .utf8)
                ?? String(data: mainBytes, encoding: .shiftJIS) else {
            return nil
        }

        // Split by colon, but only the first 5 colons (appendix may contain colons)
        let parts = mainString.splitFirst(separator: ":", maxSplits: 5)
        guard parts.count >= 5 else { return nil }

        // Version
        guard let version = UInt32(parts[0]) else { return nil }
        guard version == IPMSG_VERSION else { return nil }

        // Packet number
        guard let packetNo = Int(parts[1]) else { return nil }

        // Command
        guard let command = UInt32(parts[4]) else { return nil }

        let useUTF8 = (command & IPMsgOption.utf8Opt.rawValue) != 0

        // LogOn user and host name
        let logOnUser: String
        let hostName: String
        if useUTF8 {
            logOnUser = parts[2]
            hostName = parts[3]
        } else {
            logOnUser = StringEncoding.decode(data: Data(parts[2].utf8), utf8: false) ?? parts[2]
            hostName = StringEncoding.decode(data: Data(parts[3].utf8), utf8: false) ?? parts[3]
        }

        // Appendix (everything after the 5th colon)
        var appendix = parts.count > 5 ? parts[5] : ""

        // For ENTRY packets, process UTF-8 override from option2
        let commandMode = getMode(command)
        var finalLogOnUser = logOnUser
        var finalHostName = hostName
        var finalAppendixOption = option1String

        if (commandMode == IPMsgCommand.brEntry.rawValue ||
            commandMode == IPMsgCommand.brAbsence.rawValue ||
            commandMode == IPMsgCommand.ansEntry.rawValue),
           (command & IPMsgOption.capUtf8Opt.rawValue) != 0,
           let utf8Str = option2String {
            let lines = utf8Str.components(separatedBy: "\n")
            for line in lines where !line.isEmpty {
                let kv = line.split(separator: ":", maxSplits: 1)
                guard kv.count == 2 else { continue }
                let key = String(kv[0])
                let val = String(kv[1])
                switch key {
                case "UN": finalLogOnUser = val
                case "HN": finalHostName = val
                case "NN": appendix = val
                case "GN": finalAppendixOption = val
                default: break
                }
            }
        }

        return IPMsgPacket(
            version: version,
            packetNo: packetNo,
            logOnUser: finalLogOnUser,
            hostName: finalHostName,
            command: command,
            appendix: appendix,
            appendixOption: finalAppendixOption,
            utf8Option: option2String
        )
    }
}

// MARK: - String Splitting Helper

private extension String {
    func splitFirst(separator: Character, maxSplits: Int) -> [String] {
        var result: [String] = []
        var current = self.startIndex
        var splits = 0

        while current < self.endIndex && splits < maxSplits {
            if let sepIndex = self[current...].firstIndex(of: separator) {
                result.append(String(self[current..<sepIndex]))
                current = self.index(after: sepIndex)
                splits += 1
            } else {
                break
            }
        }
        // Append remaining string
        if current <= self.endIndex {
            result.append(String(self[current...]))
        }

        return result
    }
}
