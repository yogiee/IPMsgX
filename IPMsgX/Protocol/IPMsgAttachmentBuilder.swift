// IPMsgX/Protocol/IPMsgAttachmentBuilder.swift
// Build IPMSG attachment appendix strings
// Format: "fileID:fileName:fileSize(hex):modTime(hex):fileAttr(hex)[:extAttr]:\a"

import Foundation

enum IPMsgAttachmentBuilder {

    struct AttachmentEntry: Sendable {
        let fileID: Int
        let fileName: String
        let fileSize: UInt64
        let modifyTime: Date
        let isDirectory: Bool
        let isReadOnly: Bool
        let isHidden: Bool
        let isExtensionHidden: Bool
        let posixPermissions: Int16?
    }

    static func buildAttachmentAppendix(entries: [AttachmentEntry]) -> String {
        var buffer = ""
        for entry in entries {
            buffer += buildSingleEntry(entry)
            buffer += "\u{07}" // \a separator
        }
        return buffer
    }

    static func buildSingleEntry(_ entry: AttachmentEntry) -> String {
        var fileAttr: UInt32 = 0

        if entry.isDirectory {
            fileAttr |= IPMsgFileType.directory.rawValue
        } else {
            fileAttr |= IPMsgFileType.regular.rawValue
        }

        if entry.isReadOnly {
            fileAttr |= IPMsgFileAttr.readOnly.rawValue
        }
        if entry.isHidden {
            fileAttr |= IPMsgFileAttr.hidden.rawValue
        }
        if entry.isExtensionHidden {
            fileAttr |= IPMsgFileAttr.exHidden.rawValue
        }

        let modTimestamp = UInt32(entry.modifyTime.timeIntervalSince1970)

        var result = String(
            format: "%d:%@:%llX:%X:%X:",
            entry.fileID,
            entry.fileName,
            entry.fileSize,
            modTimestamp,
            fileAttr
        )

        // Extended attributes
        if let perm = entry.posixPermissions {
            result += String(format: "%X=%X:", IPMsgFileExtAttr.perm.rawValue, UInt32(bitPattern: Int32(perm)))
        }

        return result
    }

    static func buildClipboardEntry(fileID: Int, dataSize: UInt64, position: Int) -> String {
        let fileAttr = IPMsgFileType.clipboard.rawValue
        let extAttr = String(format: "%X=%X", IPMsgFileExtAttr.clipboardPos.rawValue, position)
        return String(format: "%d:clipboard:%llX:0:%X:%@:", fileID, dataSize, fileAttr, extAttr)
    }
}
