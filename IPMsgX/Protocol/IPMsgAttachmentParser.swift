// IPMsgX/Protocol/IPMsgAttachmentParser.swift
// Parse IPMSG attachment format: "fileID:fileName:fileSize(hex):modTime(hex):fileAttr(hex):extAttr:\a"
// Ported from MessageCenter.m attachment parsing

import Foundation

enum IPMsgAttachmentParser {

    struct ParsedAttachment: Sendable {
        let fileID: Int
        let fileName: String
        let fileSize: UInt64
        let modifyTime: Date?
        let fileType: IPMsgFileType
        let fileAttributes: UInt32
        let clipboardPosition: Int?
    }

    static func parseAttachmentList(_ attachMessage: String) -> [ParsedAttachment] {
        var results: [ParsedAttachment] = []

        // Split by ":\a" separator (may be ":\a:" or ":\a")
        let parts = attachMessage.components(separatedBy: ":\u{07}")
        for var part in parts {
            guard !part.isEmpty else { continue }

            // Strip leading colon if separator was ":\a:"
            if part.hasPrefix(":") {
                part = String(part.dropFirst())
            }
            guard !part.isEmpty else { continue }

            if let attachment = parseSingleAttachment(part) {
                results.append(attachment)
            }
        }

        return results
    }

    static func parseSingleAttachment(_ attachStr: String) -> ParsedAttachment? {
        // Format: "fileID:fileName:fileSize:modTime:fileAttr[:extAttr...]"
        let components = attachStr.components(separatedBy: ":")
        guard components.count >= 5 else { return nil }

        guard let fileID = Int(components[0]) else { return nil }

        let fileName = components[1]

        guard let fileSize = UInt64(components[2], radix: 16) else { return nil }

        let modTime: Date?
        if let modTimestamp = UInt32(components[3], radix: 16), modTimestamp > 0 {
            modTime = Date(timeIntervalSince1970: TimeInterval(modTimestamp))
        } else {
            modTime = nil
        }

        let fileAttrRaw = UInt32(components[4], radix: 16) ?? 0
        let fileTypeMask = fileAttrRaw & 0xFF
        let fileType = IPMsgFileType(rawValue: fileTypeMask) ?? .regular

        // Parse extended attributes if present
        var clipboardPos: Int?
        if components.count > 5 {
            for i in 5..<components.count {
                let ext = components[i]
                // Extended attrs are in format: "type=value"
                let kvParts = ext.components(separatedBy: "=")
                guard kvParts.count == 2,
                      let attrType = UInt32(kvParts[0], radix: 16) else { continue }

                if attrType == IPMsgFileExtAttr.clipboardPos.rawValue {
                    clipboardPos = Int(kvParts[1], radix: 16)
                }
            }
        }

        return ParsedAttachment(
            fileID: fileID,
            fileName: fileName,
            fileSize: fileSize,
            modifyTime: modTime,
            fileType: fileType,
            fileAttributes: fileAttrRaw,
            clipboardPosition: clipboardPos
        )
    }
}
