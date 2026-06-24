// IPMsgX/Views/Settings/AbsenceSettingsView.swift

import SwiftUI

struct AbsenceSettingsView: View {
    private let settings = SettingsService.shared
    // Local source of truth so the list updates immediately (SettingsService isn't observable).
    @State private var defs: [AbsenceDefinition] = SettingsService.shared.absenceDefinitions
    @State private var selectedID: AbsenceDefinition.ID?
    @State private var editTitle = ""
    @State private var editMessage = ""

    var body: some View {
        Form {
            Section("Absence Modes") {
                // A ScrollView (not a List) — a List nested in a Form won't scroll independently.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(defs.enumerated()), id: \.element.id) { idx, def in
                            let isSelected = selectedID == def.id
                            Button {
                                selectedID = def.id
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(def.title)
                                        .fontWeight(.medium)
                                    Text(def.message)
                                        .font(.caption)
                                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(isSelected ? Color.accentColor : Color.clear)

                            if idx < defs.count - 1 { Divider() }
                        }
                    }
                }
                .frame(height: 200)
            }

            Section("Edit") {
                TextField("Title", text: $editTitle)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $editMessage)
                    .frame(height: 60)

                HStack {
                    Button("Add") {
                        guard !editTitle.isEmpty else { return }
                        let new = AbsenceDefinition(title: editTitle, message: editMessage)
                        defs.append(new)
                        persist()
                        selectedID = new.id
                    }
                    .disabled(editTitle.isEmpty)

                    Button("Update") {
                        guard let idx = selectedIndex, !editTitle.isEmpty else { return }
                        defs[idx].title = editTitle
                        defs[idx].message = editMessage
                        persist()
                    }
                    .disabled(selectedID == nil || editTitle.isEmpty)

                    Button("Remove", role: .destructive) {
                        guard let id = selectedID else { return }
                        defs.removeAll { $0.id == id }
                        persist()
                        clearForm()
                    }
                    .disabled(selectedID == nil)

                    Button {
                        move(by: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled((selectedIndex ?? 0) <= 0)
                    .help("Move up")

                    Button {
                        move(by: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(selectedIndex == nil || selectedIndex == defs.count - 1)
                    .help("Move down")

                    Spacer()

                    Button("Reset to Defaults") {
                        defs = AbsenceSettingsView.defaultModes
                        persist()
                        clearForm()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: selectedID) { _, id in
            if let id, let def = defs.first(where: { $0.id == id }) {
                editTitle = def.title
                editMessage = def.message
            }
        }
    }

    private var selectedIndex: Int? {
        guard let id = selectedID else { return nil }
        return defs.firstIndex { $0.id == id }
    }

    private func move(by offset: Int) {
        guard let i = selectedIndex else { return }
        let j = i + offset
        guard j >= 0, j < defs.count else { return }
        defs.swapAt(i, j)
        persist()
    }

    private func persist() {
        settings.absenceDefinitions = defs
    }

    private func clearForm() {
        selectedID = nil
        editTitle = ""
        editMessage = ""
    }

    static let defaultModes: [AbsenceDefinition] = [
        AbsenceDefinition(title: "Not at desk", message: "I'm not at my desk right now."),
        AbsenceDefinition(title: "In a meeting", message: "I'm currently in a meeting."),
        AbsenceDefinition(title: "Out to lunch", message: "I'm out to lunch right now."),
        AbsenceDefinition(title: "Away", message: "I'm away from my computer."),
    ]
}
