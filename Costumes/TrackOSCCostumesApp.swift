//
//  TrackOSCCostumesApp.swift
//  TrackOSC Costumes (macOS)
//
//  Dresses tracked bodies, faces and hands in SVG costumes with named
//  layers: bundled ones, or a folder of your own that reloads as you draw.
//

import SwiftUI

@main
struct TrackOSCCostumesApp: App {
    @State private var store = CostumesStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 1000, minHeight: 640)
                .tint(.yellow)
        }
        .commands {
            ReceiverCommands(model: store.model)
            CommandMenu("Costume") {
                Button("Previous Costume") { store.nextCostume(-1) }
                    .keyboardShortcut("[", modifiers: [.command])
                Button("Next Costume") { store.nextCostume(1) }
                    .keyboardShortcut("]", modifiers: [.command])
                Button("Reload") { store.reload() }
                    .keyboardShortcut("r", modifiers: [.command])
                Divider()
                Toggle("Mirror", isOn: $store.mirror)
                Toggle("Show Skeleton", isOn: $store.showSkeleton)
                Divider()
                Button("Choose Costumes Folder\u{2026}") { store.library.chooseFolder() }
                Button(store.recorder.isRecording ? "Stop Recording" : "Record Stage") { store.toggleRecording() }
            }
        }
    }
}
