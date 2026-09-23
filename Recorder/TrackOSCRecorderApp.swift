//
//  TrackOSCRecorderApp.swift
//  TrackOSC Recorder (macOS)
//
//  Records the incoming OSC tracking stream to a .trackosc file and plays
//  recordings back to any receiver, so every other app can be developed
//  and demonstrated without a camera.
//

import AppKit
import SwiftUI

@main
struct TrackOSCRecorderApp: App {
    @NSApplicationDelegateAdaptor(RecorderAppDelegate.self) private var delegate
    @State private var store = RecorderStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear { delegate.store = store }
        }
        .commands {
            ReceiverCommands(model: store.model)
            CommandGroup(after: .newItem) {
                Button("Open Recording…") { store.player.presentOpenPanel() }
                    .keyboardShortcut("o")
                Button(store.recorder.isRecording ? "Stop Recording" : "Start Recording") { store.toggleRecording() }
                    .keyboardShortcut("r")
            }
            CommandMenu("Playback") {
                Button(store.player.isPlaying ? "Pause" : "Play") { store.player.togglePlayback() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(store.player.reader == nil)
                Button("Stop") { store.player.stop() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(store.player.reader == nil)
                Toggle("Loop", isOn: Binding(get: { store.player.isLooping }, set: { store.player.isLooping = $0 }))
                    .keyboardShortcut("l")
            }
        }
    }
}

/// Receives files opened from the Finder (double-click on a .trackosc).
final class RecorderAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var store: RecorderStore?

    /// A file opened from the Finder starts playing straight away.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            guard let url = urls.first else { return }
            store?.player.open(url: url)
            store?.player.play()
        }
    }

    /// Finish the file cleanly on quit (the writer flushes every second, so
    /// even a crash loses at most that much).
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            store?.stopRecording()
        }
    }
}
