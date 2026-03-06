// IPMsgX/Models/RefuseCondition.swift
// Block condition for refusing user notifications

import Foundation

struct RefuseCondition: Codable, Identifiable, Sendable {
    var id = UUID()
    var target: Target
    var string: String
    var condition: MatchType

    enum Target: String, Codable, CaseIterable, Sendable {
        case userName = "User Name"
        case groupName = "Group"
        case hostName = "Host"
        case logOnName = "LogOn"
        case ipAddress = "IP Address"
    }

    enum MatchType: String, Codable, CaseIterable, Sendable {
        case contains = "Contains"
        case equals = "Equals"
        case startsWith = "Starts With"
        case endsWith = "Ends With"
    }

    func matches(user: UserInfo) -> Bool {
        let value: String
        switch target {
        case .userName: value = user.userName
        case .groupName: value = user.groupName ?? ""
        case .hostName: value = user.hostName
        case .logOnName: value = user.logOnName
        case .ipAddress: value = user.ipAddress
        }

        let lowValue = value.lowercased()
        let lowString = string.lowercased()

        switch condition {
        case .contains: return lowValue.contains(lowString)
        case .equals: return lowValue == lowString
        case .startsWith: return lowValue.hasPrefix(lowString)
        case .endsWith: return lowValue.hasSuffix(lowString)
        }
    }
}
