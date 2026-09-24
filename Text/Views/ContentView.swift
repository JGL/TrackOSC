//
//  ContentView.swift
//  TrackOSC Text (macOS)
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: VisualStore
    @Bindable var settings: TextSettings
    let system: LetterSystem?

    var body: some View {
        ReceiverWindow(model: store.model) {
            VisualStage(store: store)
        } controls: {
            VStack(spacing: 0) {
                WordsPanel(settings: settings, system: system)
                    .padding()
                Divider()
                InspectorView(store: store)
            }
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

/// The user's own words and the typeface; recognised text joins them by itself.
struct WordsPanel: View {
    @Bindable var settings: TextSettings
    let system: LetterSystem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Words").font(.headline)
            TextField("Your words, one or more per line", text: $settings.userText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .onChange(of: settings.userText) { _, text in system?.pool.userText = text }
            Text("Text the sender reads and codes it scans join these for a while after they were seen.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Typeface", selection: $settings.fontName) {
                ForEach(TextSettings.fonts, id: \.name) { Text($0.label).tag($0.name) }
            }
            .onChange(of: settings.fontName) { _, name in system?.setFont(name) }
        }
    }
}
