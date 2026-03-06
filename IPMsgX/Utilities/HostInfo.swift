// IPMsgX/Utilities/HostInfo.swift
// Host name and IP address resolution

import Foundation

enum HostInfo {

    static var hostName: String {
        var buffer = [CChar](repeating: 0, count: 256)
        gethostname(&buffer, buffer.count)
        return String(decoding: buffer.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
    }

    static var logOnUser: String {
        NSUserName()
    }

    static var primaryIPv4Address: String? {
        var result: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let ifa = ptr {
            let sa = ifa.pointee.ifa_addr
            if sa?.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: ifa.pointee.ifa_name)
                // Prefer en0 (Wi-Fi/Ethernet), skip loopback
                if name != "lo0" {
                    var addr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    sa?.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                        var sinAddr = sin.pointee.sin_addr
                        inet_ntop(AF_INET, &sinAddr, &addr, socklen_t(INET_ADDRSTRLEN))
                    }
                    let ip = String(decoding: addr.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
                    if result == nil || name.hasPrefix("en") {
                        result = ip
                    }
                }
            }
            ptr = ifa.pointee.ifa_next
        }

        return result
    }

    static var primaryIPv4AddressNumeric: UInt32 {
        guard let ip = primaryIPv4Address else { return 0 }
        return inet_addr(ip).bigEndian
    }
}
