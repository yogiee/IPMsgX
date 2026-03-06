// IPMsgX/Utilities/PacketNumberGenerator.swift
// Thread-safe packet number generator
// Ported from MessageCenter.m:462-472

import Foundation

actor PacketNumberGenerator {
    static let shared = PacketNumberGenerator()

    private var counter: Int = 0

    private init() {
        counter = Int(Date.timeIntervalSinceReferenceDate)
    }

    func next() -> Int {
        let now = Int(Date.timeIntervalSinceReferenceDate)
        if now > counter {
            counter = now
        }
        let result = counter
        counter += 1
        return result
    }
}
