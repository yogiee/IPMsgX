// IPMsgX/Views/Settings/AbsenceSettingsView.swift

import SwiftUI

struct AbsenceSettingsView: View {
    @State private var settings = SettingsService.shared
    @State private var selectedIndex: Int?
    @State private var editTitle = ""
    @State private var editMessage = ""

    var body: some View {
        Form {
            Section("Absence Modes") {
                List(selection: $selectedIndex) {
                    ForEach(Array(settings.absenceDefinitions.enumerated()), id: \.offset) { idx, def in
                        VStack(alignment: .leading) {
                            Text(def.title)
                                .fontWeight(.medium)
                            Text(def.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .tag(idx)
                    }
                    .onMove { from, to in
                        var defs = settings.absenceDefinitions
                        defs.move(fromOffsets: from, toOffset: to)
                        settings.absenceDefinitions = defs
                    }
                    .onDelete { indices in
                        var defs = settings.absenceDefinitions
                        defs.remove(atOffsets: indices)
                        settings.absenceDefinitions = defs
                    }
                }
                .frame(height: 150)
            }

            Section("Edit") {
                TextField("Title", text: $editTitle)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $editMessage)
                    .frame(height: 60)

                HStack {
                    Button("Add") {
                        guard !editTitle.isEmpty else { return }
                        var defs = settings.absenceDefinitions
                        defs.append(AbsenceDefinition(title: editTitle, message: editMessage))
                        settings.absenceDefinitions = defs
                        editTitle = ""
                        editMessage = ""
                    }
                    .disabled(editTitle.isEmpty)

                    Button("Update") {
                        guard let idx = selectedIndex, !editTitle.isEmpty else { return }
                        var defs = settings.absenceDefinitions
                        defs[idx] = AbsenceDefinition(title: editTitle, message: editMessage)
                        settings.absenceDefinitions = defs
                    }
                    .disabled(selectedIndex == nil || editTitle.isEmpty)

                    Button("Reset to Defaults") {
                        settings.absenceDefinitions = [
                            AbsenceDefinition(title: "Not at desk", message: "I'm not at my desk right now."),
                            AbsenceDefinition(title: "In a meeting", message: "I'm currently in a meeting."),
                            AbsenceDefinition(title: "Out to lunch", message: "I'm out to lunch right now."),
                            AbsenceDefinition(title: "Away", message: "I'm away from my computer."),
                        ]
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: selectedIndex) { _, newIdx in
            if let newIdx, newIdx < settings.absenceDefinitions.count {
                editTitle = settings.absenceDefinitions[newIdx].title
                editMessage = settings.absenceDefinitions[newIdx].message
            }
        }
    }
}
