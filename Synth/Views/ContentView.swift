//
//  ContentView.swift
//  TrackOSC Synth (macOS)
//

import SwiftUI
import SynthCore

struct ContentView: View {
    @Bindable var store: SynthStore
    @State private var isNamingPreset = false
    @State private var presetName = ""
    /// `--panel drums` (bass, drums, steps, mapping, status) opens on that tab: for screenshots.
    @State private var tab: String = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--panel"), i + 1 < args.count { return args[i + 1].lowercased() }
        return "bass"
    }()

    var body: some View {
        ReceiverWindow(model: store.model) {
            SynthStage(store: store)
        } controls: {
            TabView(selection: $tab) {
                Tab("Bass", systemImage: "waveform.path", value: "bass") {
                    BassPanel(store: store)
                }
                Tab("Drums", systemImage: "circle.grid.3x3", value: "drums") {
                    DrumsPanel(store: store)
                }
                Tab("Steps", systemImage: "squareshape.split.3x3", value: "steps") {
                    ScrollView { SequencerGrid(store: store).padding() }
                }
                Tab("Mapping", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: "mapping") {
                    MappingPanel(store: store)
                }
                Tab("Status", systemImage: "waveform.path.ecg", value: "status") {
                    ReceiverStatusView(model: store.model)
                }
            }
        } toolbar: {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    store.togglePlay()
                } label: {
                    Label(store.isPlaying ? "Stop" : "Play", systemImage: store.isPlaying ? "stop.fill" : "play.fill")
                }
                .help(store.isPlaying ? "Stop the sequencer (Space)" : "Start the sequencer (Space)")
                Menu {
                    Section("Built in") {
                        ForEach(SynthPreset.builtIn, id: \.name) { preset in
                            Button(preset.name) { store.apply(preset) }
                        }
                    }
                    if !store.userPresets.isEmpty {
                        Section("Yours") {
                            ForEach(store.userPresets, id: \.name) { preset in
                                Button(preset.name) { store.apply(preset) }
                            }
                        }
                    }
                    Divider()
                    Button("Save Preset\u{2026}") { presetName = store.currentPresetName; isNamingPreset = true }
                    Button("Import\u{2026}") { store.importPreset() }
                    Button("Export\u{2026}") { store.exportPreset() }
                } label: {
                    Label(store.currentPresetName, systemImage: "square.stack.3d.up")
                }
                .help("Presets: the whole instrument, patterns and mappings")
            }
        }
        .alert("Save preset", isPresented: $isNamingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") { store.saveUserPreset(named: presetName.isEmpty ? "Preset" : presetName) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
