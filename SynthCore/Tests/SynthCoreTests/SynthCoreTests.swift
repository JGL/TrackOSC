//
//  SynthCoreTests.swift
//  SynthCoreTests
//
//  Offline renders and pure logic: no audio device needed.
//

import Foundation
import Testing
@testable import SynthCore

private func render(_ graph: SynthGraph, seconds: Float) -> [Float] {
    let frames = Int(seconds * graph.sampleRate)
    var out = [Float](repeating: 0, count: frames)
    out.withUnsafeMutableBufferPointer { graph.render(into: $0.baseAddress!, frameCount: frames) }
    return out
}

private func makeGraph() -> SynthGraph {
    SynthGraph(sampleRate: 48000, parameters: ParameterBank(), events: EventQueue(), meters: Meters(), triggersOut: EventQueueOut())
}

@Suite("Offline rendering")
struct RenderTests {
    @Test func starterPatternRendersCleanly() {
        let graph = makeGraph()
        graph.events.push(.play)
        let out = render(graph, seconds: 4)
        #expect(out.allSatisfy { $0.isFinite })
        let peak = out.map(abs).max() ?? 0
        #expect(peak <= 1.0 && peak > 0.05)
        // Something is happening in every half-second window.
        let window = Int(graph.sampleRate / 2)
        for start in stride(from: window, to: out.count - window, by: window) {
            let rms = sqrtf(out[start..<start + window].map { $0 * $0 }.reduce(0, +) / Float(window))
            #expect(rms > 0.002, "silent window at \(start)")
        }
    }

    @Test func drumsDecayToSilence() {
        let graph = makeGraph()
        for kind in DrumVoiceKind.allCases { graph.events.push(.drum(kind, velocity: 1)) }
        graph.parameters.set(.delayMix, 0)
        graph.parameters.set(.reverbMix, 0)
        let out = render(graph, seconds: 3)
        let tail = out.suffix(4800)
        #expect(tail.map(abs).max()! < 0.01)
        #expect(out.prefix(4800).map(abs).max()! > 0.1)
    }

    @Test func ladderStaysStableAtFullResonanceAcrossTheSweep() {
        var filter = LadderFilter()
        var osc = Oscillator(shape: .saw)
        var peak: Float = 0
        for i in 0..<96000 {
            let cutoff = 100 * powf(80, Float(i) / 96000)   // 100 Hz → 8 kHz
            let y = filter.process(osc.next(frequency: 55, sampleRate: 48000), cutoff: cutoff, resonance: 1, sampleRate: 48000)
            #expect(y.isFinite)
            peak = max(peak, abs(y))
        }
        #expect(peak < 4)
    }

    @Test func polyBLEPAliasesLessThanNaive() {
        // A 1234.5 Hz saw at 48 kHz: everything in the spectrum that is not
        // within a few bins of a true harmonic is aliasing (or leakage, which
        // the Hann window keeps small). PolyBLEP must cut it by 20 dB.
        let sampleRate: Float = 48000, frequency: Float = 1234.5
        let n = 8192
        var osc = Oscillator(shape: .saw)
        var blep: [Float] = [], naive: [Float] = []
        var phase: Float = 0
        for i in 0..<n {
            let window = 0.5 - 0.5 * cosf(2 * .pi * Float(i) / Float(n))
            blep.append(osc.next(frequency: frequency, sampleRate: sampleRate) * window)
            naive.append(Oscillator.naive(shape: .saw, phase: phase) * window)
            phase += frequency / sampleRate
            if phase >= 1 { phase -= 1 }
        }
        func residual(_ x: [Float]) -> Float {
            var energy: Float = 0
            let binHz = sampleRate / Float(n)
            var bin = Int(1000 / binHz)
            while Float(bin) * binHz < 20000 {
                let hz = Float(bin) * binHz
                let nearestHarmonic = (hz / frequency).rounded() * frequency
                if abs(hz - nearestHarmonic) > 4 * binHz {
                    let w = 2 * Float.pi * Float(bin) / Float(n)
                    var re: Float = 0, im: Float = 0
                    for (i, v) in x.enumerated() { re += v * cosf(w * Float(i)); im -= v * sinf(w * Float(i)) }
                    energy += re * re + im * im
                }
                bin += 7
            }
            return energy
        }
        let ratio = residual(blep) / residual(naive)
        #expect(ratio < 0.1, "aliasing ratio \(ratio)")
    }
}

@Suite("Sequencer and mapping logic")
struct LogicTests {
    @Test func stepsAreSampleAccurateWithSwing() {
        var sequencer = Sequencer()
        sequencer.tempo = 120
        sequencer.swing = 0.5
        sequencer.patterns[0] = .starter()
        sequencer.start()
        var stepSamples: [Int] = []
        for i in 0..<48000 where sequencer.tick(sampleRate: 48000) != nil { stepSamples.append(i) }
        // 120 BPM → a sixteenth every 6000 samples; 8 steps in a second.
        #expect(stepSamples.count == 8)
        #expect(stepSamples[1] - stepSamples[0] == 6000)
        sequencer.swing = 0.75
        sequencer.start()
        stepSamples = []
        for i in 0..<48000 where sequencer.tick(sampleRate: 48000) != nil { stepSamples.append(i) }
        #expect(stepSamples[1] - stepSamples[0] == 9000)   // long
        #expect(stepSamples[2] - stepSamples[1] == 3000)   // short
    }

    @Test func conductorModeWaitsForAdvance() {
        var sequencer = Sequencer()
        sequencer.conductorMode = true
        sequencer.patterns[0] = .starter()
        sequencer.start()
        var fired = 0
        for _ in 0..<1000 where sequencer.tick(sampleRate: 48000) != nil { fired += 1 }
        #expect(fired == 0)
        sequencer.advance()
        #expect(sequencer.tick(sampleRate: 48000)?.step == 0)
        #expect(sequencer.tick(sampleRate: 48000) == nil)
    }

    @Test func edgeDetectorHasHysteresisAndRefractory() {
        var detector = EdgeDetector(threshold: 0.5, hysteresis: 0.1, refractory: 0.5)
        #expect(detector.update(0.0, time: 0) == false)     // initialise below
        #expect(detector.update(0.6, time: 0.1) == true)    // rising edge
        #expect(detector.update(0.45, time: 0.2) == false)  // inside the hysteresis band: still on
        #expect(detector.update(0.6, time: 0.3) == false)
        #expect(detector.update(0.3, time: 0.4) == false)   // off
        #expect(detector.update(0.7, time: 0.45) == false)  // refractory
        #expect(detector.update(0.3, time: 0.5) == false)
        #expect(detector.update(0.7, time: 0.7) == true)
    }

    @Test func mappingCurvesAndInversion() {
        var m = ContinuousMapping(source: .noseX, target: .parameter(.bassCutoff), outputRange: 100...1100)
        #expect(m.map(0.5) == 600)
        m.curve = .exponential
        #expect(m.map(0.5) == 350)
        m.invert = true
        #expect(m.map(0.5) == 850)
        #expect(m.map(2) == 100)   // clamped
    }

    @Test func midiWordsArePinned() {
        #expect(MIDIWords.noteOn(channel: 1, note: 60, velocity: 127) == 0x2090_3C7F)
        #expect(MIDIWords.noteOff(channel: 10, note: 36) == 0x2089_2400)
        #expect(MIDIWords.controlChange(channel: 1, controller: 1, value: 64) == 0x20B0_0140)
        #expect(MIDIWords.clock == 0x10F8_0000)
    }

    @Test func eventQueueIsFIFOAndBounded() {
        let queue = EventQueue(capacity: 4)
        #expect(queue.push(.play))
        #expect(queue.push(.stop))
        #expect(queue.push(.advanceStep))
        #expect(queue.push(.play) == false)   // full (capacity − 1 usable)
        #expect(queue.pop() == .play)
        #expect(queue.pop() == .stop)
        #expect(queue.pop() == .advanceStep)
        #expect(queue.pop() == nil)
    }

    @Test func presetsRoundTripThroughJSON() throws {
        for preset in SynthPreset.builtIn {
            let data = try JSONEncoder().encode(preset)
            let back = try JSONDecoder().decode(SynthPreset.self, from: data)
            #expect(back == preset)
        }
        #expect(ParameterID.drum(.cowbell, component: 3) == .cowbellLevel)
        #expect(ParameterID.snareTone.drumComponents?.0 == .snare)
    }
}
