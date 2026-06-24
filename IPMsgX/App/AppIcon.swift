// IPMsgX/App/AppIcon.swift
// Dock icon management — reflects availability (absence) state.

import AppKit

enum AppIcon {
    /// The base app icon, loaded once from the resource bundle.
    static let base: NSImage? = {
        if let url = Bundle.appResources.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSImage(named: "AppIcon")
    }()

    /// Update the Dock icon to reflect availability. When absent, the icon is tinted orange —
    /// a modern take on the original IP Messenger's red "away" Dock icon.
    @MainActor
    static func apply(absent: Bool) {
        guard let base else { return }
        NSApp.applicationIconImage = absent ? absenceTinted(base) : base
    }

    private static func absenceTinted(_ icon: NSImage) -> NSImage {
        let size = icon.size == .zero ? NSSize(width: 512, height: 512) : icon.size
        let result = NSImage(size: size)
        result.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size))
        // .sourceAtop overlays the tint only on the icon's opaque pixels.
        NSColor.systemOrange.withAlphaComponent(0.5).set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        result.unlockFocus()
        return result
    }
}
