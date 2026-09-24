//
//  SynthGraph.swift
//  SynthCore
//
//  Everything the audio thread owns: the sequencer, the bass, the drums,
//  a delay and a small reverb, the master. `render` fills a buffer; it
//  never allocates, locks or logs. The UI reaches it only through the
//  ParameterBank (atomics) and the EventQueue.
//

import Foundation
import Synchronization

/// Levels and positions the UI reads at display rate.
public final class Meters: @unchecked Sendable {
    private let peakBits = Atomic<UInt32>(0)
    private let stepValue = Atomic<Int>(-1)
    private let patternValue = Atomic<Int>(0)
    private let playingValue = Atomic<Bool>(false)
    private let bassActive = Atomic<Bool>(false)
    private let drumHits = Atomic<UInt64>(0)   // bit per voice, set on trigger

    public init() {}

    public var peak: Float { Float(bitPattern: peakBits.load(ordering: .relaxed)) }
    public var step: Int { stepValue.load(ordering: .relaxed) }
    public var pattern: Int { patternValue.load(ordering: .relaxed) }
    public var isPlaying: Bool { playingValue.load(ordering: .relaxed) }
    public var isBassActive: Bool { bassActive.load(ordering: .relaxed) }
    /// Drum voices triggered since the last call (bit mask), then cleared.
    public func takeDrumHits() -> UInt64 { drumHits.exchange(0, ordering: .relaxed) }

    func set(peak: Float) { peakBits.store(peak.bitPattern, ordering: .relaxed) }
    func set(step: Int) { stepValue.store(step, ordering: .relaxed) }
    func set(pattern: Int) { patternValue.store(pattern, ordering: .relaxed) }
    func set(playing: Bool) { playingValue.store(playing, ordering: .relaxed) }
    func set(bassActive active: Bool) { bassActive.store(active, ordering: .relaxed) }
    func hit(_ kind: DrumVoiceKind) { _ = drumHits.bitwiseOr(1 << UInt64(kind.rawValue), ordering: .relaxed) }
}

/// A trigger the graph reports back (for MIDI out and the UI).
public struct GraphTrigger: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case bassOn(note: Int, accent: Bool), bassOff, drum(DrumVoiceKind, velocity: Float) }
    public var kind: Kind
    public var sampleOffset: Int
}

public final class SynthGraph {
    public let sampleRate: Float
    public let parameters: ParameterBank
    public let events: EventQueue
    public let meters: Meters
    public let triggersOut: EventQueueOut

    public var sequencer = Sequencer()
    private var bass = AcidBass()
    private var drums: [DrumVoice] = DrumVoiceKind.allCases.map { DrumVoice(kind: $0) }
    private var delayBuffer: [Float]
    private var delayIndex = 0
    private var reverb = SimpleReverb()
    private var peak: Float = 0
    private var peakHold = 0
    private var masterSmoother = Smoother(0.8)

    public init(sampleRate: Float, parameters: ParameterBank, events: EventQueue, meters: Meters, triggersOut: EventQueueOut) {
        self.sampleRate = sampleRate
        self.parameters = parameters
        self.events = events
        self.meters = meters
        self.triggersOut = triggersOut
        delayBuffer = Array(repeating: 0, count: Int(sampleRate * 1.1))
        reverb = SimpleReverb(sampleRate: sampleRate)
        sequencer.patterns[0] = .starter()
    }

    private func applyEvent(_ event: SynthEvent, at offset: Int) {
        switch event {
        case .bassNoteOn(let note, let accent, let slide):
            bass.noteOn(midiNote: note, accent: accent, slide: slide)
            triggersOut.push(GraphTrigger(kind: .bassOn(note: note, accent: accent), sampleOffset: offset))
        case .bassNoteOff:
            bass.noteOff()
            triggersOut.push(GraphTrigger(kind: .bassOff, sampleOffset: offset))
        case .drum(let kind, let velocity):
            drums[kind.rawValue].trigger(velocity: velocity)
            meters.hit(kind)
            triggersOut.push(GraphTrigger(kind: .drum(kind, velocity: velocity), sampleOffset: offset))
        case .play:
            sequencer.start()
            meters.set(playing: true)
        case .stop:
            sequencer.stop()
            bass.noteOff()
            meters.set(playing: false)
            meters.set(step: -1)
        case .advanceStep:
            sequencer.advance()
        case .selectPattern(let index):
            sequencer.patternIndex = min(max(index, 0), sequencer.patterns.count - 1)
            meters.set(pattern: sequencer.patternIndex)
        case .toggleDrumStep(let kind, let step):
            sequencer.pattern.toggleDrum(kind, at: step)
        case .setBassStep(let step, let value):
            sequencer.pattern.bass[step] = value
        case .setConductor(let on):
            sequencer.conductorMode = on
        case .setPattern(let index, let pattern):
            if sequencer.patterns.indices.contains(index) { sequencer.patterns[index] = pattern }
        }
    }

    private func pullParameters() {
        let p = parameters
        bass.parameters.waveform = p.get(.bassWaveform) < 0.5 ? .saw : .pulse
        bass.parameters.tune = p.get(.bassTune)
        bass.parameters.cutoff = p.get(.bassCutoff)
        bass.parameters.resonance = p.get(.bassResonance)
        bass.parameters.envMod = p.get(.bassEnvMod)
        bass.parameters.decay = p.get(.bassDecay)
        bass.parameters.accent = p.get(.bassAccent)
        bass.parameters.overdrive = p.get(.bassOverdrive)
        bass.parameters.level = p.get(.bassLevel)
        for kind in DrumVoiceKind.allCases {
            drums[kind.rawValue].parameters = DrumParameters(
                tune: p.get(.drum(kind, component: 0)), decay: p.get(.drum(kind, component: 1)),
                tone: p.get(.drum(kind, component: 2)), level: p.get(.drum(kind, component: 3)))
        }
        sequencer.tempo = p.get(.tempo)
        sequencer.swing = p.get(.swing)
    }

    /// Fill `frameCount` mono samples into `output` (the host copies to channels).
    public func render(into output: UnsafeMutablePointer<Float>, frameCount: Int) {
        while let event = events.pop() { applyEvent(event, at: 0) }
        pullParameters()
        let delayMix = parameters.get(.delayMix)
        let delayTime = parameters.get(.delayTime)
        let delayFeedback = parameters.get(.delayFeedback)
        let reverbMix = parameters.get(.reverbMix)
        let master = parameters.get(.masterLevel)
        let delaySamples = max(1, min(delayBuffer.count - 1, Int(delayTime * sampleRate)))

        for i in 0..<frameCount {
            if let triggers = sequencer.tick(sampleRate: sampleRate) {
                meters.set(step: triggers.step)
                if let note = triggers.bassNote {
                    applyEvent(.bassNoteOn(note: note, accent: triggers.bassAccent, slide: triggers.bassSlide), at: i)
                } else if triggers.bassGateOff {
                    applyEvent(.bassNoteOff, at: i)
                }
                for (kind, velocity) in triggers.drums { applyEvent(.drum(kind, velocity: velocity), at: i) }
            }
            var dry = bass.next(sampleRate: sampleRate)
            for k in 0..<drums.count where drums[k].isActive { dry += drums[k].next(sampleRate: sampleRate) }

            // Delay (feedback, one tap).
            let readIndex = (delayIndex - delaySamples + delayBuffer.count) % delayBuffer.count
            let delayed = delayBuffer[readIndex]
            delayBuffer[delayIndex] = dry + delayed * delayFeedback
            delayIndex = (delayIndex + 1) % delayBuffer.count
            var wet = dry + delayed * delayMix
            wet += reverb.process(dry) * reverbMix
            var out = softClip(wet * masterSmoother.next(target: master, coefficient: 0.001))
            if !out.isFinite { out = 0 }
            output[i] = out
            let magnitude = abs(out)
            if magnitude > peak { peak = magnitude; peakHold = Int(sampleRate * 0.15) }
        }
        peakHold -= frameCount
        if peakHold <= 0 { peak *= 0.8 }
        meters.set(peak: peak)
        meters.set(bassActive: bass.isActive)
    }
}

/// A small Schroeder reverb: four combs and two allpasses.
struct SimpleReverb {
    private var combs: [(buffer: [Float], index: Int)]
    private var allpasses: [(buffer: [Float], index: Int)]
    private let feedback: Float = 0.82

    init(sampleRate: Float = 48000) {
        let scale = sampleRate / 44100
        combs = [1116, 1188, 1277, 1356].map { (Array(repeating: 0, count: Int(Float($0) * scale)), 0) }
        allpasses = [556, 441].map { (Array(repeating: 0, count: Int(Float($0) * scale)), 0) }
    }

    @inline(__always)
    mutating func process(_ input: Float) -> Float {
        var sum: Float = 0
        for c in combs.indices {
            let y = combs[c].buffer[combs[c].index]
            combs[c].buffer[combs[c].index] = input + y * feedback
            combs[c].index = (combs[c].index + 1) % combs[c].buffer.count
            sum += y
        }
        var out = sum * 0.25
        for a in allpasses.indices {
            let buffered = allpasses[a].buffer[allpasses[a].index]
            let y = -out + buffered
            allpasses[a].buffer[allpasses[a].index] = out + buffered * 0.5
            allpasses[a].index = (allpasses[a].index + 1) % allpasses[a].buffer.count
            out = y
        }
        return out
    }
}

/// Triggers flowing out of the audio thread (to MIDI and the UI).
public final class EventQueueOut: @unchecked Sendable {
    private let capacity: Int
    private var slots: [GraphTrigger?]
    private let head = Atomic<Int>(0)
    private let tail = Atomic<Int>(0)

    public init(capacity: Int = 1024) {
        self.capacity = capacity
        slots = Array(repeating: nil, count: capacity)
    }

    @discardableResult
    func push(_ trigger: GraphTrigger) -> Bool {
        let t = tail.load(ordering: .relaxed)
        let next = (t + 1) % capacity
        if next == head.load(ordering: .acquiring) { return false }
        slots[t] = trigger
        tail.store(next, ordering: .releasing)
        return true
    }

    public func pop() -> GraphTrigger? {
        let h = head.load(ordering: .relaxed)
        if h == tail.load(ordering: .acquiring) { return nil }
        let trigger = slots[h]
        slots[h] = nil
        head.store((h + 1) % capacity, ordering: .releasing)
        return trigger
    }
}
