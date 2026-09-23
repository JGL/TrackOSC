//
//  PoseioscReceiverApp.swift
//  TrackOSC Receiver (macOS)
//
//  Listens for TrackOSC/VisionOSC OSC messages, visualises them, and advertises
//  itself via Bonjour so the senders can discover it.
//

import SwiftUI

@main
struct PoseioscReceiverApp: App {
    @State private var store = ReceiverStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            ReceiverCommands(model: store.model)
        }
    }
}
