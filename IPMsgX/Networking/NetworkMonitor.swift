// IPMsgX/Networking/NetworkMonitor.swift
// NWPathMonitor wrapper for network status changes

import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.ipmsgx", category: "NetworkMonitor")

enum NetworkStatus: Sendable {
    case connected
    case disconnected
    case requiresConnection
}

@Observable
final class NetworkMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.ipmsgx.networkmonitor")

    private(set) var status: NetworkStatus = .disconnected
    private(set) var isConnected: Bool = false
    private(set) var interfaceType: NWInterface.InterfaceType?

    private var statusContinuation: AsyncStream<NetworkStatus>.Continuation?
    let statusStream: AsyncStream<NetworkStatus>

    init() {
        var cont: AsyncStream<NetworkStatus>.Continuation!
        self.statusStream = AsyncStream { continuation in
            cont = continuation
        }
        self.statusContinuation = cont
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let newStatus: NetworkStatus
            switch path.status {
            case .satisfied:
                newStatus = .connected
            case .unsatisfied:
                newStatus = .disconnected
            case .requiresConnection:
                newStatus = .requiresConnection
            @unknown default:
                newStatus = .disconnected
            }

            Task { @MainActor in
                self.status = newStatus
                self.isConnected = (newStatus == .connected)
                self.interfaceType = path.availableInterfaces.first?.type
            }
            self.statusContinuation?.yield(newStatus)
            logger.info("Network status: \(String(describing: newStatus))")
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
        statusContinuation?.finish()
    }
}
