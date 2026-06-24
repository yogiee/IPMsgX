// IPMsgX/Views/Settings/SettingsView.swift
// macOS Settings — sidebar layout (scales to many categories, like System Settings)

import SwiftUI

struct SettingsView: View {
    @State private var selection: SettingsCategory = .general

    var body: some View {
        // Pin the sidebar visible — it's the only navigation in Settings.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsCategory.allCases, selection: $selection) { category in
                Label(category.title, systemImage: category.icon)
                    .tag(category)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            selection.view
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationTitle(selection.title)
        }
        .frame(width: 760, height: 560)
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, appearance, network, send, receive, absence, refuse, log, updates, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:    return "General"
        case .appearance: return "Appearance"
        case .network:    return "Network"
        case .send:       return "Send"
        case .receive:    return "Receive"
        case .absence:    return "Absence"
        case .refuse:     return "Refuse"
        case .log:        return "Log"
        case .updates:    return "Updates"
        case .about:      return "About"
        }
    }

    var icon: String {
        switch self {
        case .general:    return "gear"
        case .appearance: return "paintpalette"
        case .network:    return "network"
        case .send:       return "paperplane"
        case .receive:    return "envelope"
        case .absence:    return "clock"
        case .refuse:     return "hand.raised"
        case .log:        return "doc.text"
        case .updates:    return "arrow.down.circle"
        case .about:      return "info.circle"
        }
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .general:    GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .network:    NetworkSettingsView()
        case .send:       SendSettingsView()
        case .receive:    ReceiveSettingsView()
        case .absence:    AbsenceSettingsView()
        case .refuse:     RefuseSettingsView()
        case .log:        LogSettingsView()
        case .updates:    UpdatesSettingsView()
        case .about:      AboutSettingsView()
        }
    }
}
