//
//  TranscriptPanel.swift
//  TrackOSC Speaker (macOS)
//

import AppKit
import SwiftUI

struct TranscriptPanel: View {
    @Bindable var store: SpeakerStore
    private static let timeFormat = Date.FormatStyle(date: .omitted, time: .standard)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Spoken").font(.headline)
                Spacer()
                if !store.speech.queued.isEmpty {
                    Text("\(store.speech.queued.count) waiting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding([.horizontal, .top])
            List(store.speech.spoken) { utterance in
                HStack(alignment: .top, spacing: 8) {
                    Text(utterance.createdAt, format: Self.timeFormat)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11, design: .monospaced))
                    Text(utterance.text)
                        .font(.system(size: 12))
                    Spacer()
                    Text(utterance.category.rawValue)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            Divider()
            HStack {
                Toggle("Save to file", isOn: Binding(get: { store.settings.saveTranscript }, set: { store.settings.saveTranscript = $0 }))
                    .toggleStyle(.checkbox)
                    .help("Append every sentence, with its time, to transcript.txt")
                Spacer()
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([SpeakerStore.transcriptURL]) }
                    .controlSize(.small)
                    .disabled(!FileManager.default.fileExists(atPath: SpeakerStore.transcriptURL.path))
            }
            .padding([.horizontal, .bottom])
        }
    }
}
