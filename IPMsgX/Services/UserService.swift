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
        if users[user.id] != nil {
            users[user.id] = user
            changeContinuation?.yield(.updated(user))
            logger.info("Updated user: \(user.summaryString)")
        } else {
            users[user.id] = user
            changeContinuation?.yield(.added(user))
            logger.info("Added user: \(user.summaryString)")
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
