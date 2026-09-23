//
//  VoicesPanel.swift
//  TrackOSC Speaker (macOS)
//
//  Browse every installed voice: filter, preview, choose. Voices are added
//  in System Settings › Accessibility › Spoken Content › System Voice.
//

import AVFoundation
import SwiftUI

struct VoicesPanel: View {
    @Bindable var store: SpeakerStore

    var body: some View {
        @Bindable var catalog = store.voices
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search voices", text: $catalog.search)
                    .textFieldStyle(.roundedBorder)
                Button("Refresh") { catalog.refresh() }
                    .controlSize(.small)
            }
            HStack {
                Picker("Language", selection: $catalog.languageFilter) {
                    Text("All languages").tag(String?.none)
                    ForEach(catalog.languages, id: \.self) { language in
                        Text(Locale.current.localizedString(forIdentifier: language) ?? language).tag(String?.some(language))
                    }
                }
                .labelsHidden()
                Picker("Quality", selection: $catalog.qualityFilter) {
                    Text("Any quality").tag(AVSpeechSynthesisVoiceQuality?.none)
                    Text("Default").tag(AVSpeechSynthesisVoiceQuality?.some(.default))
                    Text("Enhanced").tag(AVSpeechSynthesisVoiceQuality?.some(.enhanced))
                    Text("Premium").tag(AVSpeechSynthesisVoiceQuality?.some(.premium))
                }
                .labelsHidden()
                Picker("Gender", selection: $catalog.genderFilter) {
                    Text("Any gender").tag(AVSpeechSynthesisVoiceGender?.none)
                    Text("Female").tag(AVSpeechSynthesisVoiceGender?.some(.female))
                    Text("Male").tag(AVSpeechSynthesisVoiceGender?.some(.male))
                    Text("Unspecified").tag(AVSpeechSynthesisVoiceGender?.some(.unspecified))
                }
                .labelsHidden()
            }
            HStack {
                Toggle("Novelty", isOn: $catalog.includeNovelty).toggleStyle(.checkbox)
                Toggle("Personal only", isOn: $catalog.onlyPersonal).toggleStyle(.checkbox)
                Spacer()
                Text("\(catalog.filtered.count) of \(catalog.voices.count)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }

            List(selection: Binding(
                get: { store.settings.voiceIdentifier },
                set: { store.settings.voiceIdentifier = $0 }
            )) {
                HStack {
                    Text(VoiceCatalog.systemDefaultDescription)
                    Spacer()
                    previewButton(voice: nil)
                }
                .tag(String?.none)
                ForEach(catalog.filtered) { voice in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(voice.name)
                                if voice.isPersonal { badge("Personal") }
                                if voice.isNovelty { badge("Novelty") }
                                if voice.quality != .default { badge(voice.qualityLabel) }
                            }
                            Text("\(voice.languageName) · \(voice.genderLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        previewButton(voice: AVSpeechSynthesisVoice(identifier: voice.identifier))
                    }
                    .tag(String?.some(voice.identifier))
                }
            }
            .listStyle(.inset)

            personalVoiceRow
            Text("More voices, including Enhanced and Premium downloads: System Settings › Accessibility › Spoken Content › System Voice › Manage Voices.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    private func previewButton(voice: AVSpeechSynthesisVoice?) -> some View {
        Button {
            store.speech.preview("A person appeared. Two hands now.", voice: voice)
        } label: {
            Image(systemName: "play.circle")
        }
        .buttonStyle(.borderless)
        .help("Preview this voice")
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: .capsule)
    }

    @ViewBuilder
    private var personalVoiceRow: some View {
        switch store.voices.personalVoiceStatus {
        case .authorized:
            EmptyView()
        case .notDetermined:
            HStack {
                Text("Personal Voice (yours, made in Accessibility settings) needs permission.").font(.footnote)
                Spacer()
                Button("Allow…") { store.voices.requestPersonalVoiceAccess() }.controlSize(.small)
            }
        case .denied:
            Text("Personal Voice access was denied; allow it in System Settings › Privacy & Security › Personal Voice.")
                .font(.footnote).foregroundStyle(.secondary)
        case .unsupported:
            EmptyView()
        @unknown default:
            EmptyView()
        }
    }
}
