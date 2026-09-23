//
//  RulesPanel.swift
//  TrackOSC Router (macOS)
//

import SwiftUI

struct RulesPanel: View {
    @Bindable var store: RouterStore

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                HStack {
                    Menu {
                        Button("Blank rule") { store.addBlankRule() }
                        Divider()
                        ForEach(RuleStore.presets) { preset in
                            Button(preset.name) { store.add(preset) }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .fixedSize()
                    Button {
                        store.deleteSelected()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(store.selectedRuleID == nil)
                    Spacer()
                    Button("Import…") { store.importRules() }.controlSize(.small)
                    Button("Export…") { RuleStore.exportPanel(store.engine.rules) }.controlSize(.small)
                }
                .padding(8)
                List(selection: $store.selectedRuleID) {
                    ForEach(store.engine.rules) { rule in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { rule.isEnabled },
                                set: { var r = rule; r.isEnabled = $0; store.update(r) }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.name).lineLimit(1)
                                Text("\(rule.trigger.summary) → \(rule.action.summary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(rule.id)
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }
                .listStyle(.inset)
            }
            .frame(minHeight: 160)

            if let rule = store.selectedRule {
                ScrollView {
                    RuleEditor(store: store, rule: rule)
                        .padding()
                }
                .frame(minHeight: 260)
            } else {
                Text("Select a rule, or add one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }
}
