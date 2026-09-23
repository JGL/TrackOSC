//
//  TrackOSCSpeakerApp.swift
//  TrackOSC Speaker (macOS)
//
//  Reads the incoming tracking stream aloud with AVSpeechSynthesis: who and
//  what has appeared or left, recognised text and codes, and a periodic
//  summary of where everyone is.
//

import SwiftUI

@main
struct TrackOSCSpeakerApp: App {
    @State private var store = SpeakerStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 960, minHeight: 600)
        }
        .commands {
            ReceiverCommands(model: store.model)
            CommandMenu("Speech") {
                Button(store.settings.isMuted ? "Unmute" : "Mute") { store.settings.isMuted.toggle() }
                    .keyboardShortcut("m")
                Button("Stop Speaking") { store.speech.stopAll() }
                    .keyboardShortcut(".", modifiers: [.command])
                Button("Speak a Test Sentence") { store.speakTest() }
                    .keyboardShortcut("t")
                Button("Summarise Now") { store.summariseNow() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
