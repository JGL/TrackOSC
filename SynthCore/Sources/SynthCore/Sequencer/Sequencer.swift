//
//  Sequencer.swift
//  SynthCore
//
//  Sixteen steps of bass (note, gate, accent, slide) and drum triggers,
//  eight patterns, sample-accurate stepping with swing, and a conductor
//  mode where something outside (a tracked gesture) advances the steps.
//

import Foundation

public struct BassStep: Sendable, Equatable, Codable {
    public var note: Int = 36       // MIDI note
    public var gate = false
    public var accent = false
    public var slide = false
    public init() {}
    public init(note: Int, gate: Bool, accent: Bool = false, slide: Bool = false) {
        self.note = note; self.gate = gate; self.accent = accent; self.slide = slide
    }
}

public struct StepPattern: Sendable, Equatable, Codable {
    public static let steps = 16
    public var bass: [BassStep] = Array(repeating: BassStep(), count: StepPattern.steps)
    /// drums[voice][step]: 0 off, 1 on, 2 accent.
    public var drums: [[UInt8]] = Array(repeating: Array(repeating: 0, count: StepPattern.steps), count: DrumVoiceKind.allCases.count)
    public init() {}

    public func drum(_ kind: DrumVoiceKind, at step: Int) -> UInt8 { drums[kind.rawValue][step] }
    public mutating func setDrum(_ kind: DrumVoiceKind, at step: Int, _ value: UInt8) { drums[kind.rawValue][step] = value }
    public mutating func toggleDrum(_ kind: DrumVoiceKind, at step: Int) {
        drums[kind.rawValue][step] = (drums[kind.rawValue][step] + 1) % 3
    }
}

/// What the sequencer wants played on a step.
public struct StepTriggers: Sendable {
    public var step: Int
    public var bassNote: Int?
    public var bassAccent = false
    public var bassSlide = false
    public var bassGateOff = false
    public var drums: [(DrumVoiceKind, Float)] = []
}

public struct Sequencer {
    public var patterns: [StepPattern] = Array(repeating: StepPattern(), count: 8)
    public var patternIndex = 0
    public var tempo: Float = 120      // BPM, 40–300
    public var swing: Float = 0.5      // 0.5 straight … 0.75
    public var isPlaying = false
    /// In conductor mode steps advance only when `advance()` is called.
    public var conductorMode = false
    public private(set) var step = -1
    private var samplesUntilNext: Float = 0
    private var pendingAdvance = false
    private var lastGate = false

    public init() {}

    public var pattern: StepPattern {
        get { patterns[patternIndex] }
        set { patterns[patternIndex] = newValue }
    }

    public mutating func start() {
        isPlaying = true
        step = -1
        samplesUntilNext = 0
    }

    public mutating func stop() {
        isPlaying = false
        step = -1
    }

    /// Conductor mode: take the next step now.
    public mutating func advance() {
        pendingAdvance = true
    }

    /// Seconds per sixteenth at the current tempo, with swing applied to odd steps.
    func stepSeconds(forStep s: Int) -> Float {
        let sixteenth = 60 / max(tempo, 1) / 4
        let odd = s % 2 == 1
        let swingAmount = (min(max(swing, 0.5), 0.75) - 0.5) * 2   // 0…0.5
        return odd ? sixteenth * (1 - swingAmount) : sixteenth * (1 + swingAmount)
    }

    /// Call once per sample; returns triggers when a step starts.
    @inline(__always)
    public mutating func tick(sampleRate: Float) -> StepTriggers? {
        guard isPlaying else { return nil }
        if conductorMode {
            guard pendingAdvance else { return nil }
            pendingAdvance = false
            step = (step + 1) % StepPattern.steps
        } else {
            let due = samplesUntilNext <= 0
            if due {
                step = (step + 1) % StepPattern.steps
                samplesUntilNext += stepSeconds(forStep: step) * sampleRate
            }
            samplesUntilNext -= 1
            guard due else { return nil }
        }
        let pattern = patterns[patternIndex]
        var triggers = StepTriggers(step: step)
        let bass = pattern.bass[step]
        if bass.gate {
            triggers.bassNote = bass.note
            triggers.bassAccent = bass.accent
            triggers.bassSlide = bass.slide && lastGate
        } else if lastGate {
            triggers.bassGateOff = true
        }
        lastGate = bass.gate
        for kind in DrumVoiceKind.allCases {
            let v = pattern.drums[kind.rawValue][step]
            if v > 0 { triggers.drums.append((kind, v == 2 ? 1 : 0.7)) }
        }
        return triggers
    }
}

extension StepPattern {
    /// A classic starting point: four-on-the-floor with an acid line.
    public static func starter() -> StepPattern {
        var p = StepPattern()
        for s in stride(from: 0, to: 16, by: 4) { p.setDrum(.kick, at: s, 2) }
        p.setDrum(.snare, at: 4, 1); p.setDrum(.snare, at: 12, 1)
        for s in stride(from: 2, to: 16, by: 4) { p.setDrum(.closedHat, at: s, 1) }
        p.setDrum(.openHat, at: 14, 1)
        let line: [(Int, Int, Bool, Bool)] = [(0, 36, true, false), (2, 36, false, false), (3, 48, false, true), (6, 39, false, false), (8, 36, true, false), (10, 43, false, true), (11, 36, false, false), (14, 41, false, false)]
        for (s, note, accent, slide) in line { p.bass[s] = BassStep(note: note, gate: true, accent: accent, slide: slide) }
        return p
    }
}
