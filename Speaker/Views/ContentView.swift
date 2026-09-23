//
//  ContentView.swift
//  TrackOSC Speaker (macOS)
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: SpeakerStore

    var body: some View {
        ReceiverWindow(model: store.model) {
            SpeakerStage(store: store)
        } controls: {
            TabView {
                Tab("Narration", systemImage: "text.bubble") {
                    ScrollView { NarrationPanel(store: store).padding() }
                }
                Tab("Speech", systemImage: "waveform") {
                    ScrollView { SpeechPanel(store: store).padding() }
                }
                Tab("Voices", systemImage: "person.wave.2") {
                    VoicesPanel(store: store)
                }
                Tab("Transcript", systemImage: "list.bullet.rectangle") {
                    TranscriptPanel(store: store)
                }
                Tab("Status", systemImage: "waveform.path.ecg") {
                    ReceiverStatusView(model: store.model)
                }
            }
        } toolbar: {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    store.settings.isMuted.toggle()
                    if store.settings.isMuted { store.speech.stopAll() }
                } label: {
                    Label(store.settings.isMuted ? "Unmute" : "Mute",
                          systemImage: store.settings.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(store.settings.isMuted ? Color.red : Color.primary)
                }
                .help(store.settings.isMuted ? "Unmute (⌘M)" : "Mute (⌘M)")
                Button("Summarise") { store.summariseNow() }
                    .help("Say the summary now (⌘⇧S)")
            }
        }
    }
}
