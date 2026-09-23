//
//  SpeakerStage.swift
//  TrackOSC Speaker (macOS)
//
//  The stage: what is being said, large, with the spoken words highlighted,
//  over a quiet status line. In presentation this is all that shows.
//

import SwiftUI

struct SpeakerStage: View {
    @Bindable var store: SpeakerStore

    var body: some View {
        let speech = store.speech
        let shown = speech.current ?? store.lastUtterance
        ZStack {
            Color.black
            VStack(spacing: 24) {
                Spacer()
                if let shown {
                    highlighted(shown, range: speech.current?.id == shown.id ? speech.spokenRange : nil)
                        .font(.system(size: 44, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(speech.current == nil ? .white.opacity(0.55) : .white)
                        .padding(.horizontal, 48)
                        .id(shown.id)
                    Text(shown.category == .summary ? "summary" : shown.category == .event ? "event" : "test")
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    Text(store.model.isListening ? "Listening on UDP \(String(store.model.effectivePort))" : "Not listening")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Point a TrackOSC sender here and I will describe what it sees.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
                HStack(spacing: 16) {
                    if store.settings.isMuted {
                        Label("Muted", systemImage: "speaker.slash.fill").foregroundStyle(.red)
                    } else if speech.isSpeaking {
                        Label("Speaking", systemImage: "waveform").foregroundStyle(.green)
                    } else {
                        Label("Quiet", systemImage: "waveform").foregroundStyle(.white.opacity(0.4))
                    }
                    if !speech.queued.isEmpty {
                        Text("\(speech.queued.count) queued").foregroundStyle(.white.opacity(0.5))
                    }
                    Text(store.voices.entry(for: store.settings.voiceIdentifier)?.name ?? "System voice")
                        .foregroundStyle(.white.opacity(0.4))
                }
                .font(.callout)
                .padding(.bottom, 20)
            }
        }
    }

    private func highlighted(_ utterance: Utterance, range: Range<String.Index>?) -> Text {
        guard let range else { return Text(utterance.text) }
        let text = utterance.text
        return Text(text[..<range.lowerBound]) + Text(text[range]).foregroundColor(.yellow) + Text(text[range.upperBound...])
    }
}
