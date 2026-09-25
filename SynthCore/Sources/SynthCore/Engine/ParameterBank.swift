//
//  ParameterBank.swift
//  SynthCore
//
//  Every continuously variable knob as a lock-free float the UI and the
//  mappings write and the audio thread reads. Indices are stable ids.
//

import Foundation
import Synchronization

public enum ParameterID: Int, CaseIterable, Sendable, Codable {
    // Bass
    case bassTune, bassCutoff, bassResonance, bassEnvMod, bassDecay, bassAccent, bassOverdrive, bassLevel, bassWaveform
    // Drums: tune, decay, tone, level per voice (kick … cowbell) follow in blocks of four.
    case kickTune, kickDecay, kickTone, kickLevel
    case snareTune, snareDecay, snareTone, snareLevel
    case closedHatTune, closedHatDecay, closedHatTone, closedHatLevel
    case openHatTune, openHatDecay, openHatTone, openHatLevel
    case lowTomTune, lowTomDecay, lowTomTone, lowTomLevel
    case highTomTune, highTomDecay, highTomTone, highTomLevel
    case clapTune, clapDecay, clapTone, clapLevel
    case cowbellTune, cowbellDecay, cowbellTone, cowbellLevel
    // Transport and mix
    case tempo, swing, delayMix, delayTime, delayFeedback, reverbMix, masterLevel

    public var name: String {
        switch self {
        case .bassTune: return "Tune"
        case .bassCutoff: return "Cutoff"
        case .bassResonance: return "Resonance"
        case .bassEnvMod: return "Env Mod"
        case .bassDecay: return "Decay"
        case .bassAccent: return "Accent"
        case .bassOverdrive: return "Overdrive"
        case .bassLevel: return "Level"
        case .bassWaveform: return "Waveform"
        case .tempo: return "Tempo"
        case .swing: return "Swing"
        case .delayMix: return "Delay"
        case .delayTime: return "Delay Time"
        case .delayFeedback: return "Feedback"
        case .reverbMix: return "Reverb"
        case .masterLevel: return "Master"
        default:
            let (kind, which) = drumComponents!
            return "\(kind.name) \(["Tune", "Decay", "Tone", "Level"][which])"
        }
    }

    /// (voice, 0 tune / 1 decay / 2 tone / 3 level) for drum parameters.
    public var drumComponents: (DrumVoiceKind, Int)? {
        let base = ParameterID.kickTune.rawValue
        guard rawValue >= base, rawValue < base + 4 * DrumVoiceKind.allCases.count else { return nil }
        let offset = rawValue - base
        return (DrumVoiceKind(rawValue: offset / 4)!, offset % 4)
    }

    public static func drum(_ kind: DrumVoiceKind, component: Int) -> ParameterID {
        ParameterID(rawValue: ParameterID.kickTune.rawValue + kind.rawValue * 4 + component)!
    }

    public var range: ClosedRange<Float> {
        switch self {
        case .bassTune: return -12...12
        case .bassCutoff: return 100...8000
        case .bassResonance, .bassEnvMod, .bassAccent, .bassOverdrive, .bassLevel, .bassWaveform: return 0...1
        case .bassDecay: return 0.05...2
        case .tempo: return 40...300
        case .swing: return 0.5...0.75
        case .delayMix, .delayFeedback, .reverbMix, .masterLevel: return 0...1
        case .delayTime: return 0.05...1
        default:
            let (_, which) = drumComponents!
            return which == 0 ? -1...1 : 0...1
        }
    }

    public var defaultValue: Float {
        switch self {
        case .bassTune: return 0
        case .bassCutoff: return 800
        case .bassResonance: return 0.6
        case .bassEnvMod: return 0.6
        case .bassDecay: return 0.3
        case .bassAccent: return 0.5
        case .bassOverdrive: return 0.2
        case .bassLevel: return 0.8
        case .bassWaveform: return 0
        case .tempo: return 124
        case .swing: return 0.5
        case .delayMix: return 0.15
        case .delayTime: return 0.375
        case .delayFeedback: return 0.35
        case .reverbMix: return 0.1
        case .masterLevel: return 0.8
        default:
            let (_, which) = drumComponents!
            return [0, 0.5, 0.5, 0.8][which]
        }
    }
}

/// Lock-free storage: floats as UInt32 bit patterns in atomics.
public final class ParameterBank: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Atomic<UInt32>>
    public let count = ParameterID.allCases.count

    public init() {
        storage = UnsafeMutablePointer<Atomic<UInt32>>.allocate(capacity: count)
        for id in ParameterID.allCases {
            (storage + id.rawValue).initialize(to: Atomic(id.defaultValue.bitPattern))
        }
    }

    deinit {
        storage.deinitialize(count: count)
        storage.deallocate()
    }

    @inline(__always)
    public func get(_ id: ParameterID) -> Float {
        Float(bitPattern: storage[id.rawValue].load(ordering: .relaxed))
    }

    public func set(_ id: ParameterID, _ value: Float) {
        let clamped = min(max(value, id.range.lowerBound), id.range.upperBound)
        storage[id.rawValue].store(clamped.bitPattern, ordering: .relaxed)
    }

    public func snapshot() -> [ParameterID: Float] {
        Dictionary(uniqueKeysWithValues: ParameterID.allCases.map { ($0, get($0)) })
    }

    public func restore(_ values: [ParameterID: Float]) {
        for (id, value) in values { set(id, value) }
    }
}
