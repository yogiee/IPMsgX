// IPMsgX/Networking/FileDownloader.swift
// Downloads files from IPMSG peers via TCP

import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.ipmsgx", category: "FileDownloader")

struct DownloadProgress: Sendable {
    let fileName: String
    let totalSize: UInt64
    let downloadedSize: UInt64
    let fileCount: Int
    let isComplete: Bool
    let error: String?

    var fractionComplete: Double {
        totalSize > 0 ? Double(downloadedSize) / Double(totalSize) : 0
    }
}

actor FileDownloader {
    private var isCancelled = false

    private var progressContinuation: AsyncStream<DownloadProgress>.Continuation?
    let progress: AsyncStream<DownloadProgress>

    init() {
        var cont: AsyncStream<DownloadProgress>.Continuation!
        self.progress = AsyncStream { continuation in
            cont = continuation
        }
        self.progressContinuation = cont
    }

    func cancel() {
        isCancelled = true
    }

    func downloadFile(
        from user: UserInfo,
        packetNo: Int,
        fileID: Int,
        fileName: String,
        fileSize: UInt64,
        savePath: URL,
        selfLogOnName: String,
        selfHostName: String
    ) async -> Bool {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(user.ipAddress),
            port: NWEndpoint.Port(rawValue: user.port)!
        )

        let connection = NWConnection(to: endpoint, using: .tcp)

        return await withCheckedContinuation { continuation in
            connection.start(queue: .global(qos: .utility))

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    Task {
                        let pktNo = await PacketNumberGenerator.shared.next()
                        let request = IPMsgPacketBuilder.buildGetFileData(
                            packetNo: pktNo,
                            logOnUser: selfLogOnName,
                            hostName: selfHostName,
                            targetPacketNo: packetNo,
                            fileID: fileID
                        )

                        connection.send(content: request, completion: .contentProcessed { _ in })

                        // Receive file data
                        let success = await self.receiveFileData(
                            connection: connection,
                            fileName: fileName,
                            fileSize: fileSize,
                            savePath: savePath
                        )

                        connection.cancel()
                        continuation.resume(returning: success)
                    }
                case .failed:
                    connection.cancel()
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
        }
    }

    private func receiveFileData(
        connection: NWConnection,
        fileName: String,
        fileSize: UInt64,
        savePath: URL
    ) async -> Bool {
        let filePath = savePath.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: filePath.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: filePath.path) else {
            return false
        }
        defer { try? handle.close() }

        var downloaded: UInt64 = 0
        let bufferSize = 65536

        while downloaded < fileSize && !isCancelled {
            let remaining = Int(min(UInt64(bufferSize), fileSize - downloaded))

            guard let data = await readData(from: connection, length: remaining) else {
                break
            }

            try? handle.write(contentsOf: data)
            downloaded += UInt64(data.count)

            progressContinuation?.yield(DownloadProgress(
                fileName: fileName,
                totalSize: fileSize,
                downloadedSize: downloaded,
                fileCount: 1,
                isComplete: false,
                error: nil
            ))
        }

        let success = downloaded >= fileSize
        progressContinuation?.yield(DownloadProgress(
            fileName: fileName,
            totalSize: fileSize,
            downloadedSize: downloaded,
            fileCount: 1,
            isComplete: true,
            error: success ? nil : "Download incomplete"
        ))
        progressContinuation?.finish()

        return success
    }

    private func readData(from connection: NWConnection, length: Int) async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: length) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
