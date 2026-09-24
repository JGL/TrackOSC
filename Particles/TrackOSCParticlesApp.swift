//
//  TrackOSCParticlesApp.swift
//  TrackOSC Particles (macOS)
//
//  Physics particles, trails and ghosts driven by the tracking stream.
//

import SwiftUI

@main
struct TrackOSCParticlesApp: App {
    @State private var store: VisualStore
    @State private var system: ParticleSystem?

    init() {
        let store = VisualStore(app: .particles, modes: ParticlesModes.all)
        _store = State(initialValue: store)
        let system = store.renderer.map { ParticleSystem(device: $0.device) }
        _system = State(initialValue: system)
        if let system {
            store.overlayProvider = { [store] scene, mode, params, dt in
                guard let behaviour = ParticleBehaviour(rawValue: mode.id) else { return nil }
                return system.step(scene: scene, behaviour: behaviour, params: params, palette: store.palette, history: store.builder.history, viewport: store.viewport, dt: dt)
            }
            store.trailPersistence = { _, params in params["trails"] ?? 0 }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot-dir"), CommandLine.arguments.count > index + 1 {
            let result = SnapshotRunner.run(store: store, folder: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(result ? 0 : 1)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .commands {
            ReceiverCommands(model: store.model)
            CommandMenu("Look") {
                Button("Next Mode") { store.nextMode() }.keyboardShortcut("]")
                Button("Previous Mode") { store.previousMode() }.keyboardShortcut("[")
                Button("Randomise") { store.randomise() }.keyboardShortcut("r", modifiers: [.command, .option])
                Button("Reset Parameters") { store.resetParameters() }
                Divider()
                Button("Screenshot") { store.screenshot() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button(store.recorder.isRecording ? "Stop Recording" : "Record Video") { store.toggleRecording() }
                    .keyboardShortcut("v", modifiers: [.command, .option])
            }
        }
    }
}
