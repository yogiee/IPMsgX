// IPMsgX/Networking/TCPFileServer.swift
// TCP listener for incoming file download requests

import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.ipmsgx", category: "TCPFileServer")

actor TCPFileServer {
    private var listener: NWListener?
    private let port: NWEndpoint.Port
    private var connectionHandler: ((NWConnection) -> Void)?

    init(port: UInt16 = UInt16(IPMSG_DEFAULT_PORT)) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start(handler: @escaping @Sendable (NWConnection) -> Void) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: port)
        self.connectionHandler = handler

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                logger.info("TCP file server ready on port \(self.port.rawValue)")
            case .failed(let error):
                logger.error("TCP file server failed: \(error)")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in
                await self?.handleConnection(connection)
            }
        }

        listener.start(queue: .global(qos: .utility))
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connectionHandler?(connection)
    }
}
