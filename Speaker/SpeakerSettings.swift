//
//  SpeakerSettings.swift
//  TrackOSC Speaker (macOS)
//
//  Every knob the app exposes, persisted in UserDefaults. The speech ones
//  map one-to-one onto AVSpeechUtterance and AVSpeechSynthesizer.
//

import AVFoundation
import Foundation
import Observation

enum Verbosity: String, CaseIterable, Identifiable {
    case terse, normal, detailed
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum QueuePolicy: String, CaseIterable, Identifiable {
    /// A new utterance interrupts whatever is being said.
    case latestWins
    /// Utterances wait their turn, up to a cap; older ones are dropped first.
    case queue
    var id: String { rawValue }
    var label: String { self == .latestWins ? "Latest wins" : "Queue" }
}

enum StopBoundary: String, CaseIterable, Identifiable {
    case immediate, word
    var id: String { rawValue }
    var label: String { self == .immediate ? "Immediately" : "At the next word" }
    var avBoundary: AVSpeechBoundary { self == .immediate ? .immediate : .word }
}

@Observable @MainActor
final class SpeakerSettings {
    // Narration
    var narratedKinds: Set<FrameKind> { didSet { store(narratedKinds.map(\.rawValue), "narratedKinds") } }
    var announceEmpty: Bool { didSet { store(announceEmpty, "announceEmpty") } }
    var summaryInterval: Double { didSet { store(summaryInterval, "summaryInterval") } }
    var verbosity: Verbosity { didSet { store(verbosity.rawValue, "verbosity") } }
    var textCooldown: Double { didSet { store(textCooldown, "textCooldown") } }
    var coalesceWindow: Double { didSet { store(coalesceWindow, "coalesceWindow") } }
    var isMuted: Bool { didSet { store(isMuted, "isMuted") } }
    /// Append every utterance to a text file (for installation logs).
    var saveTranscript: Bool { didSet { store(saveTranscript, "saveTranscript") } }

    // Speech (AVSpeechUtterance)
    var voiceIdentifier: String? { didSet { store(voiceIdentifier, "voiceIdentifier") } }
    var rate: Float { didSet { store(rate, "rate") } }
    var pitchMultiplier: Float { didSet { store(pitchMultiplier, "pitchMultiplier") } }
    var volume: Float { didSet { store(volume, "volume") } }
    var preUtteranceDelay: Double { didSet { store(preUtteranceDelay, "preUtteranceDelay") } }
    var postUtteranceDelay: Double { didSet { store(postUtteranceDelay, "postUtteranceDelay") } }
    var prefersAssistiveTechnologySettings: Bool { didSet { store(prefersAssistiveTechnologySettings, "prefersAssistiveTechnologySettings") } }
    var useSSML: Bool { didSet { store(useSSML, "useSSML") } }

    // Synthesizer behaviour
    var queuePolicy: QueuePolicy { didSet { store(queuePolicy.rawValue, "queuePolicy") } }
    var queueLimit: Int { didSet { store(queueLimit, "queueLimit") } }
    var stopBoundary: StopBoundary { didSet { store(stopBoundary.rawValue, "stopBoundary") } }

    nonisolated static let defaultNarratedKinds: Set<FrameKind> = [.poses, .hands, .faces, .texts, .animals, .barcodes]

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        if let raw = d.array(forKey: "narratedKinds") as? [String] {
            narratedKinds = Set(raw.compactMap(FrameKind.init(rawValue:)))
        } else {
            narratedKinds = Self.defaultNarratedKinds
        }
        announceEmpty = d.object(forKey: "announceEmpty") as? Bool ?? true
        summaryInterval = d.object(forKey: "summaryInterval") as? Double ?? 15
        verbosity = Verbosity(rawValue: d.string(forKey: "verbosity") ?? "") ?? .normal
        textCooldown = d.object(forKey: "textCooldown") as? Double ?? 30
        coalesceWindow = d.object(forKey: "coalesceWindow") as? Double ?? 0.25
        isMuted = d.bool(forKey: "isMuted")
        saveTranscript = d.bool(forKey: "saveTranscript")

        voiceIdentifier = d.string(forKey: "voiceIdentifier")
        rate = d.object(forKey: "rate") as? Float ?? AVSpeechUtteranceDefaultSpeechRate
        pitchMultiplier = d.object(forKey: "pitchMultiplier") as? Float ?? 1
        volume = d.object(forKey: "volume") as? Float ?? 1
        preUtteranceDelay = d.object(forKey: "preUtteranceDelay") as? Double ?? 0
        postUtteranceDelay = d.object(forKey: "postUtteranceDelay") as? Double ?? 0
        prefersAssistiveTechnologySettings = d.bool(forKey: "prefersAssistiveTechnologySettings")
        useSSML = d.bool(forKey: "useSSML")

        queuePolicy = QueuePolicy(rawValue: d.string(forKey: "queuePolicy") ?? "") ?? .latestWins
        queueLimit = d.object(forKey: "queueLimit") as? Int ?? 3
        stopBoundary = StopBoundary(rawValue: d.string(forKey: "stopBoundary") ?? "") ?? .word
    }

    private func store(_ value: Any?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
