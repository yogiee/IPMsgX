// IPMsgX/App/Appearance.swift
// App color-mode application + message font helpers derived from settings.

import SwiftUI
import AppKit

enum AppearanceManager {
    /// Apply the configured color mode to the whole app. nil appearance follows the system.
    @MainActor
    static func apply() {
        switch SettingsService.shared.appColorMode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil
        }
    }
}

extension SettingsService {
    /// SwiftUI font for message/compose text from the configured family + size.
    var messageFont: Font {
        messageFontName.isEmpty
            ? .system(size: messageFontSize)
            : .custom(messageFontName, size: messageFontSize)
    }

    /// AppKit font for the compose NSTextView.
    var messageNSFont: NSFont {
        if !messageFontName.isEmpty,
           let f = NSFontManager.shared.font(withFamily: messageFontName, traits: [], weight: 5, size: messageFontSize) {
            return f
        }
        return .systemFont(ofSize: messageFontSize)
    }

    /// SwiftUI `.lineSpacing` value (additional spacing) approximating the line-height multiple.
    var messageLineSpacing: CGFloat {
        max(0, CGFloat(messageLineHeight - 1.0) * CGFloat(messageFontSize))
    }
}
