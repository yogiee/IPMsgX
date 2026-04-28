// IPMsgX/Services/UserService.swift
// Actor managing online user list

import Foundation
import os

private let logger = Logger(subsystem: "com.ipmsgx", category: "UserService")

enum UserListChange: Sendable {
    case added(UserInfo)
    case updated(UserInfo)
    case removed(UserIdentifier)
    case cleared
}

actor UserService {
    private var users: [UserIdentifier: UserInfo] = [:]

    private var changeContinuation: AsyncStream<UserListChange>.Continuation?
    let changes: AsyncStream<UserListChange>

    init() {
        var cont: AsyncStream<UserListChange>.Continuation!
        self.changes = AsyncStream { continuation in
            cont = continuation
        }
        self.changeContinuation = cont
    }

    func addOrUpdate(_ user: UserInfo) {
        var seen = user
        seen.lastSeen = Date()
        if users[seen.id] != nil {
            users[seen.id] = seen
            changeContinuation?.yield(.updated(seen))
            logger.info("Updated user: \(seen.summaryString)")
        } else {
            users[seen.id] = seen
            changeContinuation?.yield(.added(seen))
            logger.info("Added user: \(seen.summaryString)")
        }
    }

    /// Remove users whose lastSeen timestamp predates `cutoff`.
    func removeStale(before cutoff: Date) {
        let staleIDs = users.filter { $0.value.lastSeen < cutoff }.map { $0.key }
        for id in staleIDs {
            users.removeValue(forKey: id)
            changeContinuation?.yield(.removed(id))
            logger.info("Removed stale user: \(id.logOnName)@\(id.ipAddress)")
        }
        if !staleIDs.isEmpty {
            logger.info("Stale user sweep removed \(staleIDs.count) user(s)")
        }
    }

    func remove(id: UserIdentifier) {
        if users.removeValue(forKey: id) != nil {
            changeContinuation?.yield(.removed(id))
            logger.info("Removed user: \(id.logOnName)@\(id.ipAddress)")
        }
    }

    func removeAll() {
        users.removeAll()
        changeContinuation?.yield(.cleared)
    }

    func user(for id: UserIdentifier) -> UserInfo? {
        users[id]
    }

    func user(logOnName: String, ipAddress: String) -> UserInfo? {
        users[UserIdentifier(logOnName: logOnName, ipAddress: ipAddress)]
    }

    func allUsers() -> [UserInfo] {
        Array(users.values)
    }

    var userCount: Int {
        users.count
    }

    func updatePublicKey(for id: UserIdentifier, key: RSAPublicKeyInfo, capability: CryptoCapability, fingerPrint: Data?) {
        guard var user = users[id] else { return }
        user.publicKey = key
        user.cryptoCapability = capability
        user.fingerPrint = fingerPrint
        users[id] = user
        changeContinuation?.yield(.updated(user))
    }

    func updateVersion(for id: UserIdentifier, version: String) {
        guard var user = users[id] else { return }
        user.version = version
        users[id] = user
    }
}
