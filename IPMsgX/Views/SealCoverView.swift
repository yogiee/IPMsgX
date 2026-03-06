// IPMsgX/Views/SealCoverView.swift
// Glass blur overlay for sealed messages

import SwiftUI

struct SealCoverView: View {
    let onOpen: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            VStack(spacing: 16) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Sealed Message")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Click to open the seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Seal") {
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
