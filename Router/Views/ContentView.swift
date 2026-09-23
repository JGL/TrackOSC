//
//  ContentView.swift
//  TrackOSC Router (macOS)
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: RouterStore

    var body: some View {
        ReceiverWindow(model: store.model) {
            ActivityStage(store: store)
        } controls: {
            TabView {
                Tab("Rules", systemImage: "list.bullet") {
                    RulesPanel(store: store)
                }
                Tab("Sources", systemImage: "gauge.with.dots.needle.33percent") {
                    SourcesPanel(store: store)
                }
                Tab("Outputs", systemImage: "cable.connector") {
                    ScrollView { OutputsPanel(store: store).padding() }
                }
                Tab("Status", systemImage: "waveform.path.ecg") {
                    ReceiverStatusView(model: store.model)
                }
            }
        } toolbar: {
            ToolbarItemGroup(placement: .automatic) {
                Toggle(isOn: Binding(get: { store.engine.dryRun }, set: { store.setDryRun($0) })) {
                    Label("Dry run", systemImage: "eye")
                }
                .help("Log what would happen without sending anything")
            }
        }
    }
}
