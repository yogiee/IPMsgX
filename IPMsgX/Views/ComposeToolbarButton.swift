// IPMsgX/Views/ComposeToolbarButton.swift
// Shared compact formatting toolbar button for compose areas

import SwiftUI

struct ComposeToolbarButton: View {
    let systemImage: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .background(hovered ? Color.secondary.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
