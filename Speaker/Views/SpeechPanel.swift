//
//  SpeechPanel.swift
//  TrackOSC Speaker (macOS)
//
//  Every AVSpeechUtterance and AVSpeechSynthesizer option.
//

import AVFoundation
import SwiftUI

struct SpeechPanel: View {
    @Bindable var store: SpeakerStore

    var body: some View {
        @Bindable var settings = store.settings
        VStack(alignment: .leading, spacing: 12) {
            Text("Utterance").font(.headline)
            labelled("Rate", value: String(format: "%.2f", settings.rate)) {
                Slider(value: $settings.rate, in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
            }
            Text("AVSpeechUtterance.rate: \(String(format: "%.2f", AVSpeechUtteranceMinimumSpeechRate)) to \(String(format: "%.2f", AVSpeechUtteranceMaximumSpeechRate)), default \(String(format: "%.2f", AVSpeechUtteranceDefaultSpeechRate)).")
                .font(.footnote).foregroundStyle(.secondary)
            labelled("Pitch", value: String(format: "%.2f×", settings.pitchMultiplier)) {
                Slider(value: $settings.pitchMultiplier, in: 0.5...2)
            }
            labelled("Volume", value: "\(Int(settings.volume * 100))%") {
                Slider(value: $settings.volume, in: 0...1)
            }
            labelled("Pause before", value: String(format: "%.1f s", settings.preUtteranceDelay)) {
                Slider(value: $settings.preUtteranceDelay, in: 0...5, step: 0.1)
            }
            labelled("Pause after", value: String(format: "%.1f s", settings.postUtteranceDelay)) {
                Slider(value: $settings.postUtteranceDelay, in: 0...5, step: 0.1)
            }
            Toggle("Prefer the system's assistive-technology speech settings", isOn: $settings.prefersAssistiveTechnologySettings)
                .toggleStyle(.checkbox)
            Text("When on, the rate, pitch and voice chosen in System Settings › Accessibility › Spoken Content take precedence over the values above.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Send as SSML", isOn: $settings.useSSML)
                .toggleStyle(.checkbox)
            Text("Wraps each sentence in <speak>; some voices pace punctuation better this way.")
                .font(.footnote).foregroundStyle(.secondary)

            Divider()
            Text("Synthesizer").font(.headline)
            Picker("When a new sentence arrives", selection: $settings.queuePolicy) {
                ForEach(QueuePolicy.allCases) { Text($0.label).tag($0) }
            }
            if settings.queuePolicy == .queue {
                Stepper("Keep at most \(settings.queueLimit) waiting", value: $settings.queueLimit, in: 1...20)
            }
            Picker("Interrupt", selection: $settings.stopBoundary) {
                ForEach(StopBoundary.allCases) { Text($0.label).tag($0) }
            }
            Text("Summaries never interrupt an event sentence; events interrupt summaries when \"Latest wins\" is chosen.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Divider()
            HStack {
                Button("Speak a Test Sentence") { store.speakTest() }
                Button("Stop") { store.speech.stopAll() }
                Spacer()
                Text("spoken \(store.speech.spokenCount) · dropped \(store.speech.droppedCount)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func labelled<Content: View>(_ label: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).frame(width: 96, alignment: .leading)
            content()
            Text(value).frame(width: 56, alignment: .trailing).font(.system(.body, design: .monospaced))
        }
    }
}
