//
//  TrackOSC3DCostumesApp.swift
//  TrackOSC 3D Costumes (macOS)
//
//  Dresses the 3D body pose (/poses3d/arr) in rigged USDZ models on
//  Apple's motion-capture skeleton, folders of parts, or a mannequin.
//

import SwiftUI

@main
struct TrackOSC3DCostumesApp: App {
    @State private var store = Costumes3DStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 1000, minHeight: 640)
                .tint(.brown)
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
                Toggle("Axis Gnomon", isOn: $store.showGnomon)
                Button("Reset View") { store.resetView() }
                    .keyboardShortcut("0", modifiers: [.command])
                Divider()
                Button("Choose Models Folder\u{2026}") { store.library.chooseFolder() }
            }
        }
    }
}
