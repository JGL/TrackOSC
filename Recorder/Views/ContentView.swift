//
//  ContentView.swift
//  TrackOSC Recorder (macOS)
//

import PoseioscShared
import SwiftUI

struct ContentView: View {
    @Bindable var store: RecorderStore

    var body: some View {
        ReceiverWindow(model: store.model) {
            ZStack(alignment: .bottom) {
                VisualizerView(model: store.model)
                if !store.model.fullScreen.isGUIHidden {
                    TransportStrip(store: store)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: { $0.pathExtension == RecordingFormat.fileExtension }) else { return false }
                store.player.open(url: url)
                return true
            }
        } controls: {
            TabView {
                Tab("Record", systemImage: "record.circle") {
                    ScrollView {
                        RecordPanel(store: store)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Tab("Play", systemImage: "play.circle") {
                    ScrollView {
                        PlayPanel(store: store)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Tab("Status", systemImage: "waveform.path.ecg") {
                    ReceiverStatusView(model: store.model)
                }
            }
        } toolbar: {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    store.toggleRecording()
                } label: {
                    Label(store.recorder.isRecording ? "Stop" : "Record",
                          systemImage: store.recorder.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(store.recorder.isRecording ? Color.red : Color.primary)
                }
                .help(store.recorder.isRecording ? "Stop recording (⌘R)" : "Record every incoming datagram to a .trackosc file (⌘R)")
            }
        }
    }
}
