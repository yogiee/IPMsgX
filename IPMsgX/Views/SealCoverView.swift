// IPMsgX/Views/SealCoverView.swift
// Glass blur overlay for sealed messages

import SwiftUI

struct SealCoverView: View {
    var isLocked: Bool = false
    let onOpen: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            VStack(spacing: 16) {
                Image(systemName: isLocked ? "lock.fill" : "envelope.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text(isLocked ? "Locked Message" : "Sealed Message")
                    .font(.title2)
                    .fontWeight(.medium)

                Text(isLocked ? "A password is required to open this message" : "Click to open the seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(isLocked ? "Open (Locked)…" : "Open Seal") {
                    onOpen()
                }
                .controlSize(.large)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
    }
}
