//
//  Drums.swift
//  SynthCore
//
//  808-flavoured analogue-model drums: a kick from a pitch-swept sine, a
//  snare from two tuned sines and filtered noise, hats from six square
//  waves at the 808's ratios, toms, a clap of noise bursts, a cowbell of
//  two squares. Each has tune, decay, tone and level.
//

import Foundation

public enum DrumVoiceKind: Int, CaseIterable, Sendable, Codable {
    case kick, snare, closedHat, openHat, lowTom, highTom, clap, cowbell

    public var name: String {
        switch self {
        case .kick: "Kick"
        case .snare: "Snare"
        case .closedHat: "Closed Hat"
        case .openHat: "Open Hat"
        case .lowTom: "Low Tom"
        case .highTom: "High Tom"
        case .clap: "Clap"
        case .cowbell: "Cowbell"
        }
    }

    public var shortName: String {
        switch self {
        case .kick: "BD"
        case .snare: "SD"
        case .closedHat: "CH"
        case .openHat: "OH"
        case .lowTom: "LT"
        case .highTom: "HT"
        case .clap: "CP"
        case .cowbell: "CB"
        }
    }
}

public struct DrumParameters: Sendable, Equatable {
    public var tune: Float = 0      // −1…1
    public var decay: Float = 0.5   // 0…1 (scaled per voice)
    public var tone: Float = 0.5    // 0…1
    public var level: Float = 0.8
    public init() {}
    public init(tune: Float, decay: Float, tone: Float, level: Float) {
        self.tune = tune; self.decay = decay; self.tone = tone; self.level = level
    }
}

/// One drum voice; `kind` decides the model.
public struct DrumVoice {
    public let kind: DrumVoiceKind
    public var parameters = DrumParameters()
    private var ampEnvelope = DecayEnvelope()
    private var pitchEnvelope = DecayEnvelope()
    private var noiseEnvelope = DecayEnvelope()
    private var phase: Float = 0
    private var phase2: Float = 0
    private var hatPhases = SIMD8<Float>(repeating: 0)
    private var noise = Noise()
    private var filter = StateVariableFilter()
    private var filter2 = StateVariableFilter()
    private var clapBurst = 0
    private var clapCountdown = 0
    private var velocity: Float = 1

    public init(kind: DrumVoiceKind) {
        self.kind = kind
        noise = Noise(seed: UInt32(kind.rawValue + 1) &* 2_654_435_761)
    }

    public var isActive: Bool { ampEnvelope.isActive || clapBurst > 0 }

    public mutating func trigger(velocity: Float = 1) {
        self.velocity = min(max(velocity, 0), 1)
        phase = 0
        phase2 = 0
        ampEnvelope.trigger(level: 1, attackSamples: kind == .kick ? 0 : 2)
        pitchEnvelope.trigger(level: 1)
        noiseEnvelope.trigger(level: 1)
        if kind == .clap { clapBurst = 4; clapCountdown = 0 }
    }

    // 808 hi-hat oscillator ratios (relative to the lowest, 205.3 Hz).
    private static let hatRatios = SIMD8<Float>(1.0, 1.4471, 1.6170, 1.9265, 2.5028, 2.6637, 0, 0)

    @inline(__always)
    public mutating func next(sampleRate: Float) -> Float {
        let p = parameters
        let tune = powf(2, p.tune)   // ±1 octave
        var out: Float = 0
        switch kind {
        case .kick:
            let decay = 0.15 + p.decay * 0.8
            let amp = ampEnvelope.next(decaySeconds: decay, sampleRate: sampleRate)
            let pitchEnv = pitchEnvelope.next(decaySeconds: 0.04 + p.tone * 0.08, sampleRate: sampleRate)
            let frequency = 48 * tune * (1 + pitchEnv * (2 + p.tone * 6))
            phase += frequency / sampleRate
            if phase >= 1 { phase -= 1 }
            out = sinf(phase * 2 * .pi) * amp
            out = softClip(out * (1 + p.tone * 2))

        case .snare:
            let decay = 0.08 + p.decay * 0.4
            let amp = ampEnvelope.next(decaySeconds: decay, sampleRate: sampleRate)
            let noiseAmp = noiseEnvelope.next(decaySeconds: decay * 1.3, sampleRate: sampleRate)
            let f1 = 180 * tune, f2 = 330 * tune
            phase += f1 / sampleRate; if phase >= 1 { phase -= 1 }
            phase2 += f2 / sampleRate; if phase2 >= 1 { phase2 -= 1 }
            let body = (sinf(phase * 2 * .pi) + sinf(phase2 * 2 * .pi) * 0.6) * amp * 0.5
            let snap = filter.process(noise.next(), cutoff: 1800 + p.tone * 4000, q: 0.8, mode: .high, sampleRate: sampleRate) * noiseAmp
            out = body * (1 - p.tone * 0.5) + snap * (0.5 + p.tone)

        case .closedHat, .openHat:
            let decay = kind == .closedHat ? 0.03 + p.decay * 0.12 : 0.15 + p.decay * 0.8
            let amp = ampEnvelope.next(decaySeconds: decay, sampleRate: sampleRate)
            let base = 205.3 * tune
            hatPhases += Self.hatRatios * (base / sampleRate)
            hatPhases -= hatPhases.rounded(.down)
            var sum: Float = 0
            for i in 0..<6 { sum += hatPhases[i] < 0.5 ? Float(1) : Float(-1) }
            let metallic = filter.process(sum / 6, cutoff: 7000 + p.tone * 5000, q: 1.2, mode: .high, sampleRate: sampleRate)
            out = filter2.process(metallic, cutoff: 9000 + p.tone * 6000, q: 0.7, mode: .band, sampleRate: sampleRate) * amp * 2.5

        case .lowTom, .highTom:
            let decay = 0.15 + p.decay * 0.5
            let amp = ampEnvelope.next(decaySeconds: decay, sampleRate: sampleRate)
            let pitchEnv = pitchEnvelope.next(decaySeconds: 0.08, sampleRate: sampleRate)
            let base: Float = kind == .lowTom ? 90 : 180
            let frequency = base * tune * (1 + pitchEnv * (0.5 + p.tone))
            phase += frequency / sampleRate; if phase >= 1 { phase -= 1 }
            out = sinf(phase * 2 * .pi) * amp + noise.next() * amp * 0.03 * p.tone

        case .clap:
            // Four quick bursts then a longer tail, all filtered noise.
            let n = noise.next()
            var burst: Float = 0
            if clapBurst > 0 {
                if clapCountdown <= 0 {
                    noiseEnvelope.trigger(level: 1)
                    clapCountdown = Int(0.01 * sampleRate)
                    clapBurst -= 1
                }
                clapCountdown -= 1
                burst = noiseEnvelope.next(decaySeconds: 0.008, sampleRate: sampleRate)
            }
            let tail = ampEnvelope.next(decaySeconds: 0.1 + p.decay * 0.5, sampleRate: sampleRate)
            let shaped = filter.process(n, cutoff: 1000 + p.tone * 2500, q: 1.5, mode: .band, sampleRate: sampleRate)
            out = shaped * (burst * 1.5 + tail * 0.6)

        case .cowbell:
            let decay = 0.1 + p.decay * 0.5
            let amp = ampEnvelope.next(decaySeconds: decay, sampleRate: sampleRate)
            phase += 587 * tune / sampleRate; if phase >= 1 { phase -= 1 }
            phase2 += 845 * tune / sampleRate; if phase2 >= 1 { phase2 -= 1 }
            let squares: Float = (phase < 0.5 ? 1 : -1) + (phase2 < 0.5 ? 0.8 : -0.8)
            out = filter.process(squares * 0.5, cutoff: 600 + p.tone * 1500, q: 2, mode: .band, sampleRate: sampleRate) * amp * 2
        }
        return out * p.level * velocity
    }
}
