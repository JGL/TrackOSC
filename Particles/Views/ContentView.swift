//
//  ContentView.swift
//  TrackOSC Particles (macOS)
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: VisualStore

    var body: some View {
        ReceiverWindow(model: store.model) {
            VisualStage(store: store)
        } controls: {
            InspectorView(store: store)
        } toolbar: {
            ToolbarItemGroup(placement: .automatic) {
                Button { store.previousMode() } label: { Image(systemName: "chevron.left") }
                    .help("Previous mode (←)")
                Text(store.mode.name).font(.callout).frame(minWidth: 110)
                Button { store.nextMode() } label: { Image(systemName: "chevron.right") }
                    .help("Next mode (→)")
                Button { store.randomise() } label: { Label("Randomise", systemImage: "dice") }
                    .help("Random parameters and palette (Space)")
                Button { store.screenshot() } label: { Label("Screenshot", systemImage: "camera") }
                    .help("Save a PNG to Downloads (S)")
                Button {
                    store.toggleRecording()
                } label: {
                    Label(store.recorder.isRecording ? "Stop" : "Record", systemImage: store.recorder.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(store.recorder.isRecording ? Color.red : Color.primary)
                }
                .help(store.recorder.isRecording ? "Stop recording (V)" : "Record the output to an .mp4 in Downloads (V)")
            }
        }
    }
}
