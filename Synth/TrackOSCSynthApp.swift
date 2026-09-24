//
//  TrackOSCSynthApp.swift
//  TrackOSC Synth (macOS)
//
//  A 303-and-808-flavoured synth and drum machine played by the tracking
//  stream: knobs, a step sequencer and mappings from bodies, hands and
//  faces to the instrument, with MIDI out.
//

import SwiftUI
import SynthCore

@main
struct TrackOSCSynthApp: App {
    @State private var store = SynthStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 1000, minHeight: 640)
                .tint(.indigo)
        }
        .commands {
            ReceiverCommands(model: store.model)
            CommandMenu("Instrument") {
                Button(store.isPlaying ? "Stop" : "Play") { store.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                Toggle("Conductor Mode", isOn: $store.conductorMode)
                Toggle("Tracking Plays the Instrument", isOn: $store.mappingsEnabled)
                Divider()
                ForEach(0..<8, id: \.self) { index in
                    Button("Pattern \(index + 1)") { store.selectPattern(index) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                }
                Divider()
                Button("Randomise Pattern") { store.randomisePattern() }
                    .keyboardShortcut("r", modifiers: [])
                Button("Clear Pattern") { store.clearPattern() }
                Divider()
                Section("Presets") {
                    ForEach(store.allPresets, id: \.name) { preset in
                        Button(preset.name) { store.apply(preset) }
                    }
                }
            }
        }
    }
}
