//
//  VoiceCatalog.swift
//  TrackOSC Speaker (macOS)
//
//  Every installed AVSpeechSynthesisVoice, grouped and filterable, plus
//  personal-voice authorisation and a refresh when voices are added in
//  System Settings.
//

import AVFoundation
import Foundation
import Observation

struct VoiceEntry: Identifiable, Hashable, Sendable {
    let identifier: String
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality
    let gender: AVSpeechSynthesisVoiceGender
    let isNovelty: Bool
    let isPersonal: Bool

    var id: String { identifier }

    var qualityLabel: String {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Default"
        }
    }

    var genderLabel: String {
        switch gender {
        case .male: "Male"
        case .female: "Female"
        default: "Unspecified"
        }
    }

    var languageName: String {
        Locale.current.localizedString(forIdentifier: language) ?? language
    }
}

@Observable @MainActor
final class VoiceCatalog {
    private(set) var voices: [VoiceEntry] = []
    private(set) var personalVoiceStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus

    var search = ""
    var languageFilter: String? = nil
    var qualityFilter: AVSpeechSynthesisVoiceQuality? = nil
    var genderFilter: AVSpeechSynthesisVoiceGender? = nil
    var includeNovelty = true
    var onlyPersonal = false

    private(set) var isRefreshing = false
    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Fetches the voice list off the main thread. Calling speechVoices()
    /// on the main thread from inside the voices-changed notification
    /// deadlocks against the speech service, so it is never done there.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        personalVoiceStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
        Task.detached(priority: .utility) { [weak self] in
            let entries = AVSpeechSynthesisVoice.speechVoices().map { voice in
                VoiceEntry(
                    identifier: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    quality: voice.quality,
                    gender: voice.gender,
                    isNovelty: voice.voiceTraits.contains(.isNoveltyVoice),
                    isPersonal: voice.voiceTraits.contains(.isPersonalVoice)
                )
            }
            .sorted { ($0.languageName, $0.name) < ($1.languageName, $1.name) }
            await MainActor.run { [weak self] in
                self?.voices = entries
                self?.isRefreshing = false
            }
        }
    }

    var languages: [String] {
        Array(Set(voices.map(\.language))).sorted {
            (Locale.current.localizedString(forIdentifier: $0) ?? $0) < (Locale.current.localizedString(forIdentifier: $1) ?? $1)
        }
    }

    var filtered: [VoiceEntry] {
        voices.filter { voice in
            if let languageFilter, voice.language != languageFilter { return false }
            if let qualityFilter, voice.quality != qualityFilter { return false }
            if let genderFilter, voice.gender != genderFilter { return false }
            if !includeNovelty, voice.isNovelty { return false }
            if onlyPersonal, !voice.isPersonal { return false }
            if !search.isEmpty, !voice.name.localizedCaseInsensitiveContains(search), !voice.languageName.localizedCaseInsensitiveContains(search) { return false }
            return true
        }
    }

    func entry(for identifier: String?) -> VoiceEntry? {
        guard let identifier else { return nil }
        return voices.first { $0.identifier == identifier }
    }

    /// The voice AVSpeech will use when none is chosen: the system default for the current language.
    static var systemDefaultDescription: String {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        return "System default (\(Locale.current.localizedString(forIdentifier: language) ?? language))"
    }

    func requestPersonalVoiceAccess() {
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { [weak self] status in
            Task { @MainActor in
                self?.personalVoiceStatus = status
                self?.refresh()
            }
        }
    }
}
