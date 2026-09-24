//
//  AcidBass.swift
//  SynthCore
//
//  The 303 idea: one oscillator (saw or square), a resonant ladder filter
//  swept by a decaying envelope, accents that hit the envelope and
//  resonance harder, slides that glide the pitch, and an overdrive.
//

import Foundation

public struct AcidBassParameters: Sendable, Equatable {
    public var waveform: Oscillator.Shape = .saw
    /// Semitones.
    public var tune: Float = 0
    public var cutoff: Float = 800       // Hz, 100–8000
    public var resonance: Float = 0.6    // 0–1
    public var envMod: Float = 0.6       // 0–1, how far the envelope opens the filter
    public var decay: Float = 0.3        // seconds
    public var accent: Float = 0.5       // 0–1
    public var overdrive: Float = 0.2    // 0–1
    public var level: Float = 0.8
    public init() {}
}

public struct AcidBass {
    public var parameters = AcidBassParameters()
    private var oscillator = Oscillator(shape: .saw)
    private var filter = LadderFilter()
    private var filterEnvelope = DecayEnvelope()
    private var ampEnvelope: Float = 0
    private var gate = false
    private var accented = false
    private var frequency: Float = 110
    private var targetFrequency: Float = 110
    private var sliding = false
    private var cutoffSmoother = Smoother(800)

    public init() {}

    public static let slideSeconds: Float = 0.06

    /// Note on. `slide` glides from the current pitch instead of restarting.
    public mutating func noteOn(midiNote: Int, accent: Bool, slide: Bool) {
        targetFrequency = 440 * powf(2, (Float(midiNote) - 69 + parameters.tune) / 12)
        accented = accent
        if !slide || !gate {
            frequency = targetFrequency
            oscillator.reset()
            filter.reset()
            filterEnvelope.trigger(level: accent ? 1 : 0.7)
            ampEnvelope = 1
        }
        sliding = slide && gate
        gate = true
    }

    public mutating func noteOff() {
        gate = false
    }

    public var isActive: Bool { gate || ampEnvelope > 1e-4 }

    @inline(__always)
    public mutating func next(sampleRate: Float) -> Float {
        // Pitch glide.
        if sliding || frequency != targetFrequency {
            let coefficient = 1 - expf(-1 / (Self.slideSeconds * sampleRate))
            frequency += (targetFrequency - frequency) * coefficient
        }
        oscillator.shape = parameters.waveform
        let raw = oscillator.next(frequency: frequency, sampleRate: sampleRate)

        // Filter envelope: accented notes open further and decay a little faster.
        let env = filterEnvelope.next(decaySeconds: parameters.decay * (accented ? 0.8 : 1), sampleRate: sampleRate)
        let accentAmount = accented ? parameters.accent : 0
        let sweep = parameters.envMod * (1 + accentAmount * 1.5)
        let targetCutoff = parameters.cutoff * powf(2, env * sweep * 4)
        let cutoff = cutoffSmoother.next(target: targetCutoff, coefficient: 0.05)
        let resonance = min(parameters.resonance + accentAmount * 0.25, 1)
        var out = filter.process(raw, cutoff: cutoff, resonance: resonance, sampleRate: sampleRate)

        // Amplitude: hold while the gate is on, then a quick release.
        if gate { ampEnvelope = 1 } else { ampEnvelope *= expf(-1 / (0.02 * sampleRate)) }
        out *= ampEnvelope * (0.7 + 0.5 * accentAmount)

        // Overdrive: gain into a soft clip, level-compensated.
        let drive = 1 + parameters.overdrive * 8
        out = softClip(out * drive) / softClip(drive) * (1 + parameters.overdrive)
        return out * parameters.level
    }
}
