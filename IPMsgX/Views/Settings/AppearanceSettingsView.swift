// IPMsgX/Views/Settings/AppearanceSettingsView.swift
// Appearance: color mode + message font (applies to compose and received content).

import SwiftUI
import AppKit

struct AppearanceSettingsView: View {
    // Backed by the same UserDefaults keys SettingsService reads.
    @AppStorage("appColorMode") private var appColorMode = "system"
    @AppStorage("messageFontName") private var messageFontName = ""
    @AppStorage("messageFontSize") private var messageFontSize = 13.0
    @AppStorage("messageLineHeight") private var messageLineHeight = 1.2

    private let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()

    private var previewFont: Font {
        messageFontName.isEmpty ? .system(size: messageFontSize) : .custom(messageFontName, size: messageFontSize)
    }

    private var previewLineSpacing: CGFloat {
        max(0, CGFloat(messageLineHeight - 1.0) * CGFloat(messageFontSize))
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Color mode", selection: $appColorMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .onChange(of: appColorMode) { AppearanceManager.apply() }
            }

            Section {
                Picker("Font", selection: $messageFontName) {
                    ForEach([""] + fontFamilies, id: \.self) { family in
                        Text(family.isEmpty ? "System" : family).tag(family)
                    }
                }

                LabeledContent("Size") {
                    HStack(spacing: 8) {
                        Text("\(Int(messageFontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Stepper("", value: $messageFontSize, in: 9...28, step: 1)
                            .labelsHidden()
                    }
                }

                LabeledContent("Line height") {
                    HStack(spacing: 8) {
                        Text(String(format: "%.1f×", messageLineHeight))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Stepper("", value: $messageLineHeight, in: 1.0...2.5, step: 0.1)
                            .labelsHidden()
                    }
                }
            } header: {
                Text("Message Font")
            } footer: {
                Text("Applies to both the compose field and received message content.")
            }

            Section("Preview") {
                Text("The quick brown fox jumps over the lazy dog.\nSphinx of black quartz, judge my vow.")
                    .font(previewFont)
                    .lineSpacing(previewLineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
