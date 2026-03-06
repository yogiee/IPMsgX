// IPMsgX/Protocol/IPMsgPacketBuilder.swift
// Build IPMSG wire-format packets
// Format: "1:packetNo:logOnUser:hostName:command:appendix"

import Foundation

enum IPMsgPacketBuilder {

    // MARK: - Core Builder

    static func buildPacket(
        packetNo: Int,
        logOnUser: String,
        hostName: String,
        command: UInt32,
        appendixData: Data? = nil
    ) -> Data {
        let useUTF8 = (command & IPMsgOption.utf8Opt.rawValue) != 0

        // Build header: "1:packetNo:logOnUser:hostName:command:"
        let header = "\(IPMSG_VERSION):\(packetNo):\(logOnUser):\(hostName):\(command):"

        var data: Data
        if useUTF8 {
            data = Data(header.utf8)
        } else {
            data = StringEncoding.encode(string: header, utf8: false) ?? Data(header.utf8)
        }

        if let appendixData {
            data.append(appendixData)
        }

        return data
    }

    // MARK: - Entry / Exit Broadcasts

    static func buildEntry(
        packetNo: Int,
        logOnUser: String,
        hostName: String,
        command: UInt32,
        userName: String,
        groupName: String?,
        absenceTitle: String?
    ) -> Data {
        // Build the appendix: userName[absenceTitle]\0groupName\0\nUN:logOnUser\nHN:hostName\nNN:userName\nGN:groupName\n\0
        var appendixData = Data()

        // Nickname (may include absence suffix)
        var nickName = userName
        if let absenceTitle, !absenceTitle.isEmpty {
            nickName += "[\(absenceTitle)]"
        }

        // Encode nickname in legacy encoding
        if let nickData = StringEncoding.encode(string: nickName, utf8: false) {
            appendixData.append(nickData)
        }

        // Group separator
        appendixData.append(0)

        // Group name in legacy encoding
        if let group = groupName, !group.isEmpty,
           let groupData = StringEncoding.encode(string: group, utf8: false) {
            appendixData.append(groupData)
        }

        // UTF-8 extension separator: \0\n
        appendixData.append(contentsOf: [0, 0x0A])

        // UTF-8 key-value pairs
        var utf8Section = "UN:\(logOnUser)\n"
        utf8Section += "HN:\(hostName)\n"
        utf8Section += "NN:\(nickName)\n"
        if let group = groupName, !group.isEmpty {
            utf8Section += "GN:\(group)\n"
        }
        appendixData.append(Data(utf8Section.utf8))
        appendixData.append(0)

        return buildPacket(
            packetNo: packetNo,
            logOnUser: logOnUser,
            hostName: hostName,
            command: command,
            appendixData: appendixData
        )
    }

    // MARK: - Message Sending

    static func buildSendMsg(
        packetNo: Int,
        logOnUser: String,
        hostName: String,
        command: UInt32,
        message: String,
        optionData: Data? = nil,
        useUTF8: Bool
    ) -> Data {
        var appendixData: Data

        if useUTF8 {
            appendixData = Data(message.utf8)
        } else {
            appendixData = StringEncoding.encode(string: message, utf8: false) ?? Data(message.utf8)
        }
        appendixData.append(0) // NULL terminate message

        if let optionData {
            appendixData.append(optionData)
        }

        return buildPacket(
            packetNo: packetNo,
            logOnUser: logOnUser,
            hostName: hostName,
            command: command,
            appendixData: appendixData
        )
    }

    // MARK: - Encrypted Message

    static func buildEncryptedMsg(
        packetNo: Int,
        logOnUser: String,
        hostName: String,
        command: UInt32,
        encryptedAppendix: String,
        plainOption: Data?,
        encExtMsg: Bool,
        useUTF8: Bool
    ) -> Data {
        // Encrypted appendix: "spec:encKey:encBody[:signature]"
        var appendixData: Data

        if useUTF8 {
            appendixData = Data(encryptedAppendix.utf8)
        } else {
            appendixData = StringEncoding.encode(string: encryptedAppendix, utf8: false)
                ?? Data(encryptedAppendix.utf8)
        }
        appendixData.append(0) // NULL terminate

        // If option data exists and is NOT encrypted as part of the message body
        if let plainOption, !encExtMsg {
            appendixData.append(plainOption)
        }

        return buildPacket(
            packetNo: packetNo,
            logOnUser: logOnUser,
            hostName: hostName,
            command: command,
            appendixData: appendixData
        )
    }

    // MARK: - Simple Reply Packets

    static func buildRecvMsg(
        packetNo: Int,
        logOnUser: String,
        hostName: String,
        replyPacketNo: Int
    ) -> Data {
        let appendix = "\(replyPacketNo)"
        return buildPacket(
            packetNo: packetNo,
            logOnUser: logOnUser,
            hostName: hostName,
            command: IPMsgCommand.recvMsg.rawValue,
            appendixData: Data(appendix.utf8)
        )
    }

    static func buildReadMsg(
        packetNo: Int,
        logOnUser: String,
        hostName: String,
        command: UInt32,
        replyPacketNo: Int
    ) -> Data {
        let appendix = "\(replyPacketNo)"
        return buildPacket(
            packetNo: packetNo,
            logOnUser: logOnUser,
            hostName: hostName,
            command: command,
            appendixData: Data(appendix.utf8)
        )
    }

    static func buildInfoResponse(
        packetNo: Int,
        logOnUser: String,
        hostName: String,
        versionInfo: String
    ) -> Data {
        return buildPacket(
            packetNo: packetNo,
            logOnUser: logOnUser,
            hostName: hostName,
            command: IPMsgCommand.sendInfo.rawValue,
            appendixData: Data(versionInfo.utf8)
        )
    }

    static func buildPubKeyResponse(
        packetNo: Int,
        logOnUser: String,
        hostName: String,
        capability: UInt32,
        exponent: UInt32,
        modulusHex: String
    ) -> Data {
        let appendix = String(format: "%X:%X-%@", capability, exponent, modulusHex)
        return buildPacket(
            packetNo: packetNo,
            logOnUser: logOnUser,
            hostName: hostName,
            command: IPMsgCommand.ansPubKey.rawValue,
            appendixData: Data(appendix.utf8)
        )
    }

    static func buildGetPubKey(
        packetNo: Int,
        logOnUser: String,
        hostName: String,
        capability: UInt32
    ) -> Data {
        let appendix = String(format: "%X", capability)
        return buildPacket(
            packetNo: packetNo,
            logOnUser: logOnUser,
            hostName: hostName,
            command: IPMsgCommand.getPubKey.rawValue,
            appendixData: Data(appendix.utf8)
        )
    }

    // MARK: - File Transfer Request

    static func buildGetFileData(
        packetNo: Int,
        logOnUser: String,
        hostName: String,
        targetPacketNo: Int,
        fileID: Int,
        offset: Int = 0
    ) -> Data {
        let appendix = String(format: "%lx:%x:%lx", targetPacketNo, fileID, offset)
        return buildPacket(
            packetNo: packetNo,
            logOnUser: logOnUser,
            hostName: hostName,
            command: IPMsgCommand.getFileData.rawValue,
            appendixData: Data(appendix.utf8)
        )
    }

    static func buildGetDirFiles(
        packetNo: Int,
        logOnUser: String,
        hostName: String,
        targetPacketNo: Int,
        fileID: Int
    ) -> Data {
        let appendix = String(format: "%lx:%x", targetPacketNo, fileID)
        return buildPacket(
            packetNo: packetNo,
            logOnUser: logOnUser,
            hostName: hostName,
            command: IPMsgCommand.getDirFiles.rawValue,
            appendixData: Data(appendix.utf8)
        )
    }

    static func buildReleaseFiles(
        packetNo: Int,
        logOnUser: String,
        hostName: String,
        targetPacketNo: Int
    ) -> Data {
        let appendix = "\(targetPacketNo)"
        return buildPacket(
            packetNo: packetNo,
            logOnUser: logOnUser,
            hostName: hostName,
            command: IPMsgCommand.releaseFiles.rawValue,
            appendixData: Data(appendix.utf8)
        )
    }
}
