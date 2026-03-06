// IPMsgX/Networking/UDPTransport.swift
// UDP transport using BSD sockets for reliable broadcast support
// Network.framework NWConnection doesn't handle UDP broadcast well,
// so we use POSIX sockets which are proven for IPMSG protocol.

import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.ipmsgx", category: "UDPTransport")

actor UDPTransport {
    private var socketFD: Int32 = -1
    private let port: UInt16

    private var receiveTask: Task<Void, Never>?
    private var incomingContinuation: AsyncStream<(Data, NWEndpoint)>.Continuation?
    let incomingMessages: AsyncStream<(Data, NWEndpoint)>

    init(port: UInt16 = UInt16(IPMSG_DEFAULT_PORT)) {
        self.port = port

        var cont: AsyncStream<(Data, NWEndpoint)>.Continuation!
        self.incomingMessages = AsyncStream(bufferingPolicy: .bufferingNewest(256)) { continuation in
            cont = continuation
        }
        self.incomingContinuation = cont
    }

    // MARK: - Lifecycle

    func start() throws {
        guard socketFD == -1 else {
            logger.warning("UDPTransport already started")
            return
        }

        // Create UDP socket
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            let err = String(cString: strerror(errno))
            logger.error("socket() failed: \(err)")
            throw TransportError.socketCreationFailed(err)
        }

        // SO_BROADCAST — required for sending to broadcast addresses
        var broadcast: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))

        // SO_REUSEADDR — allow multiple IPMSG instances
        var reuseAddr: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        // SO_REUSEPORT — allow port sharing
        var reusePort: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reusePort, socklen_t(MemoryLayout<Int32>.size))

        // Receive buffer size
        var bufSize: Int32 = Int32(MAX_UDPBUF)
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufSize, socklen_t(MemoryLayout<Int32>.size))

        // Bind to INADDR_ANY:port
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            let err = String(cString: strerror(errno))
            close(fd)
            logger.error("bind() failed on port \(self.port): \(err)")
            throw TransportError.bindFailed(port, err)
        }

        self.socketFD = fd
        startReceiveLoop()
        logger.info("UDP transport started on port \(self.port)")
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil

        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }

        incomingContinuation?.finish()
        incomingContinuation = nil
        logger.info("UDP transport stopped")
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        let fd = self.socketFD
        let continuation = self.incomingContinuation

        receiveTask = Task.detached(priority: .userInitiated) {
            var buffer = [UInt8](repeating: 0, count: Int(MAX_UDPBUF))
            var senderAddr = sockaddr_in()
            var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            while !Task.isCancelled {
                let bytesRead = buffer.withUnsafeMutableBufferPointer { bufPtr in
                    withUnsafeMutablePointer(to: &senderAddr) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                            recvfrom(fd, bufPtr.baseAddress, bufPtr.count, 0, sockPtr, &senderLen)
                        }
                    }
                }

                guard bytesRead > 0 else {
                    if bytesRead < 0 {
                        let errNo = errno
                        if errNo == EAGAIN || errNo == EWOULDBLOCK {
                            continue
                        }
                        if errNo == EBADF || Task.isCancelled {
                            break // Socket closed
                        }
                        logger.error("recvfrom() error: \(String(cString: strerror(errNo)))")
                    }
                    continue
                }

                let data = Data(bytes: buffer, count: bytesRead)

                // Extract sender IP and port
                var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var inAddr = senderAddr.sin_addr
                inet_ntop(AF_INET, &inAddr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
                let senderIP = String(decoding: ipBuf.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
                let senderPort = UInt16(bigEndian: senderAddr.sin_port)

                // Build NWEndpoint for compatibility with existing code
                let endpoint = NWEndpoint.hostPort(
                    host: NWEndpoint.Host(senderIP),
                    port: NWEndpoint.Port(rawValue: senderPort) ?? .init(integerLiteral: 2425)
                )

                continuation?.yield((data, endpoint))
            }
        }
    }

    // MARK: - Sending

    func send(data: Data, to host: String, port: UInt16? = nil) async throws {
        guard socketFD >= 0 else {
            throw TransportError.notStarted
        }

        let targetPort = port ?? self.port
        let fd = self.socketFD

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = targetPort.bigEndian
        _ = host.withCString { cstr in
            inet_pton(AF_INET, cstr, &addr.sin_addr)
        }

        let result = data.withUnsafeBytes { bufPtr in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    sendto(fd, bufPtr.baseAddress, bufPtr.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        if result < 0 {
            let err = String(cString: strerror(errno))
            logger.error("sendto(\(host):\(targetPort)) failed: \(err)")
            throw TransportError.sendFailed(host, err)
        }
    }

    func broadcast(data: Data, toAddresses addresses: [String], port: UInt16? = nil) async {
        let targetPort = port ?? self.port

        // Send to each configured/discovered subnet broadcast address
        for address in addresses where address != "255.255.255.255" {
            do {
                try await send(data: data, to: address, port: targetPort)
            } catch {
                logger.error("Broadcast to \(address) failed: \(error)")
            }
        }

        // Fall back to limited broadcast only if no subnet addresses available
        if addresses.filter({ $0 != "255.255.255.255" }).isEmpty {
            do {
                try await send(data: data, to: "255.255.255.255", port: targetPort)
            } catch {
                logger.error("Broadcast to 255.255.255.255 failed: \(error)")
            }
        }
    }
}

// MARK: - Errors

enum TransportError: Error, LocalizedError {
    case socketCreationFailed(String)
    case bindFailed(UInt16, String)
    case notStarted
    case sendFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed(let msg): return "Socket creation failed: \(msg)"
        case .bindFailed(let port, let msg): return "Bind to port \(port) failed: \(msg)"
        case .notStarted: return "Transport not started"
        case .sendFailed(let host, let msg): return "Send to \(host) failed: \(msg)"
        }
    }
}
