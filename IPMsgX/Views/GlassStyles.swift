// IPMsgX/Views/GlassStyles.swift
// Shared floating-glass treatments for the compose and receive windows —
// Liquid Glass on macOS 26+, materials/bordered fallbacks on macOS 15.

import SwiftUI
import AppKit

extension Color {
    /// Message pane background — the editor draws none, so this is what the fades blend into.
    static let editorBackground = Color(nsColor: .textBackgroundColor)
}

extension View {
    @ViewBuilder
    func floatingGlass(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }

    /// Floating action button — always a capsule. Apply before `.disabled(_:)` so a disabled
    /// prominent button drops its tint.
    func floatingButtonStyle(prominent: Bool = false) -> some View {
        modifier(FloatingButtonStyle(prominent: prominent))
    }
}

/// `.glassProminent` ignores `.buttonBorderShape(.capsule)` (renders a rounded rectangle), so the
/// prominent variant is plain `.glass` tinted with the accent color — same capsule as its neighbours.
private struct FloatingButtonStyle: ViewModifier {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if prominent && isEnabled {
                content
                    .buttonStyle(.glass)
                    .tint(.accentColor)
                    .foregroundStyle(.white)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            Group {
                if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
            }
            .buttonBorderShape(.capsule)
        }
    }
}
