//
//  TrackOSCColoursApp.swift
//  TrackOSC Colours (macOS)
//
//  Gradients, colour fields and patterns driven by the tracking stream.
//  `--snapshot-dir <folder>` renders every mode once at 1280×720 with the
//  attract figure and exits (the build check).
//

import SwiftUI

@main
struct TrackOSCColoursApp: App {
    @State private var store: VisualStore

    init() {
        let store = VisualStore(app: .colours, modes: ColoursModes.all)
        _store = State(initialValue: store)
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot-dir"), CommandLine.arguments.count > index + 1 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            let result = SnapshotRunner.run(store: store, folder: folder)
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
