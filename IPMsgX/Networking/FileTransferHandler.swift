// IPMsgX/Networking/FileTransferHandler.swift
// Handles inbound TCP connections for file serving (uploads to requester)

import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.ipmsgx", category: "FileTransfer")

actor FileTransferHandler {
    private let attachmentStore: AttachmentStore

    init(attachmentStore: AttachmentStore) {
        self.attachmentStore = attachmentStore
    }

    func handleConnection(_ connection: NWConnection) async {
        // Read the request
        guard let requestData = await readData(from: connection, length: 1024) else {
            connection.cancel()
            return
        }

        guard let _ = String(data: requestData, encoding: .utf8) else {
            connection.cancel()
            return
        }

        // Parse the request (format: "1:packetNo:logOnUser:hostName:command:targetPacketNo:fileID:offset")
        guard let packet = IPMsgPacketParser.parse(data: requestData) else {
            connection.cancel()
            return
        }

        let commandMode = getMode(packet.command)
        let parts = packet.appendix.components(separatedBy: ":")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }

        let targetPacketNo = Int(parts[0], radix: 16) ?? 0
        let fileID = Int(parts[1], radix: 16) ?? 0

        if commandMode == IPMsgCommand.getFileData.rawValue {
            await sendFile(connection: connection, packetNo: targetPacketNo, fileID: fileID)
        } else if commandMode == IPMsgCommand.getDirFiles.rawValue {
            await sendDirectory(connection: connection, packetNo: targetPacketNo, fileID: fileID)
        }

        connection.cancel()
    }

    private func sendFile(connection: NWConnection, packetNo: Int, fileID: Int) async {
        guard let attachment = await attachmentStore.findAttachment(packetNo: packetNo, fileID: fileID) else {
            logger.error("Attachment not found: pkt=\(packetNo), fid=\(fileID)")
            return
        }

        guard let fileHandle = FileHandle(forReadingAtPath: attachment.path.path) else {
            logger.error("Cannot open file: \(attachment.path.path)")
            return
        }
        defer { try? fileHandle.close() }

        let bufferSize = 32768
        while true {
            guard let chunk = try? fileHandle.read(upToCount: bufferSize), !chunk.isEmpty else {
                break
            }
            await sendData(connection: connection, data: chunk)
        }

        logger.info("File sent: \(attachment.path.lastPathComponent)")
    }

    private func sendDirectory(connection: NWConnection, packetNo: Int, fileID: Int) async {
        guard let attachment = await attachmentStore.findAttachment(packetNo: packetNo, fileID: fileID) else {
            return
        }

        let fm = FileManager.default
        let basePath = attachment.path

        // Recursively enumerate and send with headerSize:header framing
        await sendDirectoryContents(connection: connection, dirPath: basePath, fm: fm)

        // Send RETPARENT to signal end
        let retParentHeader = buildDirFileHeader(
            name: ".",
            size: 0,
            fileType: .retParent,
            modTime: Date()
        )
        await sendFramedHeader(connection: connection, header: retParentHeader)
    }

    private func sendDirectoryContents(connection: NWConnection, dirPath: URL, fm: FileManager) async {
        guard let contents = try? fm.contentsOfDirectory(at: dirPath, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]) else {
            return
        }

        for item in contents {
            let attrs = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            let isDir = attrs?.isDirectory ?? false
            let size = UInt64(attrs?.fileSize ?? 0)
            let modTime = attrs?.contentModificationDate ?? Date()

            if isDir {
                // Directory header
                let header = buildDirFileHeader(
                    name: item.lastPathComponent,
                    size: 0,
                    fileType: .directory,
                    modTime: modTime
                )
                await sendFramedHeader(connection: connection, header: header)

                // Recurse
                await sendDirectoryContents(connection: connection, dirPath: item, fm: fm)

                // Return parent
                let retHeader = buildDirFileHeader(
                    name: ".",
                    size: 0,
                    fileType: .retParent,
                    modTime: Date()
                )
                await sendFramedHeader(connection: connection, header: retHeader)
            } else {
                // File header
                let header = buildDirFileHeader(
                    name: item.lastPathComponent,
                    size: size,
                    fileType: .regular,
                    modTime: modTime
                )
                await sendFramedHeader(connection: connection, header: header)

                // Send file data
                if let handle = FileHandle(forReadingAtPath: item.path) {
                    defer { try? handle.close() }
                    while let chunk = try? handle.read(upToCount: 32768), !chunk.isEmpty {
                        await sendData(connection: connection, data: chunk)
                    }
                }
            }
        }
    }

    private func buildDirFileHeader(name: String, size: UInt64, fileType: IPMsgFileType, modTime: Date) -> String {
        let modTimestamp = UInt32(modTime.timeIntervalSince1970)
        return String(format: "%@:%llX:%X:%X:", name, size, modTimestamp, fileType.rawValue)
    }

    private func sendFramedHeader(connection: NWConnection, header: String) async {
        let headerData = Data(header.utf8)
        let headerSize = String(format: "%04X", headerData.count + 4) // +4 for the size field itself
        let frame = Data((headerSize + ":").utf8) + headerData
        await sendData(connection: connection, data: frame)
    }

    // MARK: - I/O Helpers

    private func readData(from connection: NWConnection, length: Int) async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: length) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func sendData(connection: NWConnection, data: Data) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }
}
