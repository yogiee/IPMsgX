// IPMsgX/Services/RetryService.swift
// Manages pending message confirmations
// Ported from retry logic in MessageCenter.m:1088-1130

import Foundation

struct RetryInfo: Sendable {
    let packetNo: Int
    let command: UInt32
    let toUser: UserIdentifier
    let message: String
    let option: String?
    var retryCount: Int = 0
}

actor RetryService {
    // Key: "packetNo:logOnName@ipAddress"
    private var pending: [String: RetryInfo] = [:]

    private func key(packetNo: Int, toUser: UserIdentifier) -> String {
        "\(packetNo):\(toUser.logOnName)@\(toUser.ipAddress)"
    }

    func addPending(_ info: RetryInfo) {
        let k = key(packetNo: info.packetNo, toUser: info.toUser)
        pending[k] = info
    }

    func confirmReceived(packetNo: Int, from userId: UserIdentifier) {
        let k = key(packetNo: packetNo, toUser: userId)
        pending.removeValue(forKey: k)
    }

    func isPending(packetNo: Int, toUser: UserIdentifier) -> Bool {
        let k = key(packetNo: packetNo, toUser: toUser)
        return pending[k] != nil
    }

    func removePending(packetNo: Int, toUser: UserIdentifier) {
        let k = key(packetNo: packetNo, toUser: toUser)
        pending.removeValue(forKey: k)
    }

    func pendingMessages(for userId: UserIdentifier) -> [RetryInfo] {
        pending.values.filter { $0.toUser == userId }
    }

    func incrementRetry(packetNo: Int, toUser: UserIdentifier) -> Int {
        let k = key(packetNo: packetNo, toUser: toUser)
        guard var info = pending[k] else { return 0 }
        info.retryCount += 1
        pending[k] = info
        return info.retryCount
    }
}
