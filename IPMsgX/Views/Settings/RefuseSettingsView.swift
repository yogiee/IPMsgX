// IPMsgX/Views/Settings/RefuseSettingsView.swift

import SwiftUI

struct RefuseSettingsView: View {
    @State private var conditions: [RefuseCondition] = {
        guard let data = UserDefaults.standard.data(forKey: "refuseConditions"),
              let conds = try? JSONDecoder().decode([RefuseCondition].self, from: data) else {
            return []
        }
        return conds
    }()

    @State private var editTarget: RefuseCondition.Target = .userName
    @State private var editString = ""
    @State private var editCondition: RefuseCondition.MatchType = .contains

    var body: some View {
        Form {
            Section("Block Conditions") {
                List {
                    ForEach(conditions) { cond in
                        HStack {
                            Text(cond.target.rawValue)
                                .frame(width: 80, alignment: .leading)
                            Text(cond.condition.rawValue)
                                .frame(width: 80, alignment: .leading)
                            Text(cond.string)
                        }
                        .font(.caption)
                    }
                    .onDelete { indices in
                        conditions.remove(atOffsets: indices)
                        save()
                    }
                }
                .frame(height: 120)
            }

            Section("Add Condition") {
                Picker("Target", selection: $editTarget) {
                    ForEach(RefuseCondition.Target.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                Picker("Match", selection: $editCondition) {
                    ForEach(RefuseCondition.MatchType.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                TextField("Value", text: $editString)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    guard !editString.isEmpty else { return }
                    conditions.append(RefuseCondition(
                        target: editTarget,
                        string: editString,
                        condition: editCondition
                    ))
                    save()
                    editString = ""
                }
                .disabled(editString.isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(conditions) {
            UserDefaults.standard.set(data, forKey: "refuseConditions")
        }
    }
}
