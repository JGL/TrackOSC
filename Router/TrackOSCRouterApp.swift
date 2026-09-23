//
//  TrackOSCRouterApp.swift
//  TrackOSC Router (macOS)
//
//  Turns tracking events and values into MIDI, Shortcuts, key presses and
//  HTTP requests, by rules.
//

import SwiftUI

@main
struct TrackOSCRouterApp: App {
    @State private var store = RouterStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .commands {
            ReceiverCommands(model: store.model)
            CommandMenu("Rules") {
                Button("New Rule") { store.addBlankRule() }
                    .keyboardShortcut("n")
                Button("Duplicate Rule") { store.duplicateSelected() }
                    .keyboardShortcut("d")
                    .disabled(store.selectedRuleID == nil)
                Button("Delete Rule") { store.deleteSelected() }
                    .keyboardShortcut(.delete, modifiers: [.command])
                    .disabled(store.selectedRuleID == nil)
                Divider()
                Button("Import Rules…") { store.importRules() }
                Button("Export Rules…") { RuleStore.exportPanel(store.engine.rules) }
                Divider()
                Toggle("Dry Run (log only)", isOn: Binding(get: { store.engine.dryRun }, set: { store.engine.dryRun = $0 }))
                Button("Clear Activity") { store.engine.clearFeed() }
                    .keyboardShortcut("k")
            }
        }
    }
}
