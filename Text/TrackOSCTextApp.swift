//
//  TrackOSCTextApp.swift
//  TrackOSC Text (macOS)
//
//  Kinetic typography driven by the tracking stream: recognised text, code
//  payloads and your own words, moved by people.
//

import SwiftUI

@main
struct TrackOSCTextApp: App {
    @State private var store: VisualStore
    @State private var settings = TextSettings()
    @State private var system: LetterSystem?

    init() {
        let store = VisualStore(app: .text, modes: TextModes.all)
        _store = State(initialValue: store)
        let settings = TextSettings()
        _settings = State(initialValue: settings)
        let system = store.renderer.map { LetterSystem(device: $0.device, fontName: settings.fontName) }
        _system = State(initialValue: system)
        if let system {
            system.pool.userText = settings.userText
            store.overlayProvider = { [store] scene, mode, params, dt in
                guard let behaviour = TextBehaviour(rawValue: mode.id) else { return nil }
                return system.step(scene: scene, behaviour: behaviour, params: params, palette: store.palette, viewport: store.viewport, viewSize: store.viewSize, dt: dt)
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
            ContentView(store: store, settings: settings, system: system)
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

/// The words and the face.
@Observable @MainActor
final class TextSettings {
    static let fonts: [(name: String, label: String)] = [
        ("Helvetica-Bold", "Helvetica Bold"), ("HelveticaNeue-CondensedBlack", "Helvetica Neue Condensed Black"),
        ("AvenirNext-Heavy", "Avenir Next Heavy"), ("Futura-Bold", "Futura Bold"), ("Georgia-Bold", "Georgia Bold"),
        ("Menlo-Bold", "Menlo Bold"), ("AmericanTypewriter-Bold", "American Typewriter Bold"), ("MarkerFelt-Wide", "Marker Felt"),
    ]
    var userText: String { didSet { UserDefaults.standard.set(userText, forKey: "userText") } }
    var fontName: String { didSet { UserDefaults.standard.set(fontName, forKey: "fontName") } }

    init() {
        userText = UserDefaults.standard.string(forKey: "userText") ?? "TRACKOSC\nHELLO"
        fontName = UserDefaults.standard.string(forKey: "fontName") ?? "Helvetica-Bold"
    }
}
