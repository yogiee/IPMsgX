// IPMsgX/Networking/BroadcastAddressResolver.swift
// Discover interface broadcast addresses using getifaddrs()

import Foundation

enum BroadcastAddressResolver {

    struct InterfaceInfo: Sendable {
        let name: String
        let ipAddress: String
        let broadcastAddress: String
        let netmask: String
    }

    static func discoverBroadcastAddresses() -> [InterfaceInfo] {
        var results: [InterfaceInfo] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return results }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }

            // Only IPv4
            guard ifa.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: ifa.pointee.ifa_name)
            // Skip loopback
            guard name != "lo0" else { continue }

            // Check IFF_BROADCAST flag
            let flags = Int32(ifa.pointee.ifa_flags)
            guard (flags & IFF_BROADCAST) != 0 else { continue }
            guard ifa.pointee.ifa_dstaddr != nil else { continue }

            // Extract IP address
            var ipAddr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            ifa.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                var addr = sin.pointee.sin_addr
                inet_ntop(AF_INET, &addr, &ipAddr, socklen_t(INET_ADDRSTRLEN))
            }

            // Extract broadcast address
            var bcastAddr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            ifa.pointee.ifa_dstaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                var addr = sin.pointee.sin_addr
                inet_ntop(AF_INET, &addr, &bcastAddr, socklen_t(INET_ADDRSTRLEN))
            }

            // Extract netmask
            var maskAddr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if let netmask = ifa.pointee.ifa_netmask {
                netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                    var addr = sin.pointee.sin_addr
                    inet_ntop(AF_INET, &addr, &maskAddr, socklen_t(INET_ADDRSTRLEN))
                }
            }

            results.append(InterfaceInfo(
                name: name,
                ipAddress: String(decoding: ipAddr.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self),
                broadcastAddress: String(decoding: bcastAddr.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self),
                netmask: String(decoding: maskAddr.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
            ))
        }

        return results
    }

    static var allBroadcastAddresses: [String] {
        discoverBroadcastAddresses().map(\.broadcastAddress)
    }
}
