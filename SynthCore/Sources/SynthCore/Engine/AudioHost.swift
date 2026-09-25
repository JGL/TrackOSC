//
//  AudioHost.swift
//  SynthCore
//
//  AVAudioEngine with one AVAudioSourceNode whose render block is a
//  nonisolated @Sendable closure over the graph (the Swift 6 main-actor
//  trap: a closure created on the main actor would inherit its isolation).
//

import AVFoundation
import Foundation

/// Boxes the graph for the render block; the graph is only ever touched
/// from the audio thread once the engine runs.
final class GraphBox: @unchecked Sendable {
    let graph: SynthGraph
    var scratch: [Float]
    init(graph: SynthGraph, maxFrames: Int) {
        self.graph = graph
        scratch = Array(repeating: 0, count: maxFrames)
    }
}

@MainActor
public final class AudioHost {
    public let engine = AVAudioEngine()
    public let parameters = ParameterBank()
    public let events = EventQueue()
    public let meters = Meters()
    public let triggers = EventQueueOut()
    public private(set) var sampleRate: Float = 48000
    public private(set) var isRunning = false
    public private(set) var lastError: String?
    private var sourceNode: AVAudioSourceNode?
    private var box: GraphBox?

    public init() {}

    /// Builds the graph at the output's sample rate and starts the engine.
    public func start() {
        guard !isRunning else { return }
        let output = engine.outputNode
        let format = output.inputFormat(forBus: 0)
        sampleRate = Float(format.sampleRate > 0 ? format.sampleRate : 48000)
        let graph = SynthGraph(sampleRate: sampleRate, parameters: parameters, events: events, meters: meters, triggersOut: triggers)
        let box = GraphBox(graph: graph, maxFrames: 8192)
        self.box = box
        let node = Self.makeSourceNode(box: box, format: format)
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1))
        engine.connect(engine.mainMixerNode, to: output, format: format)
        do {
            try engine.start()
            isRunning = true
            lastError = nil
        } catch {
            lastError = "Audio engine failed to start: \(error.localizedDescription)"
        }
    }

    public func stop() {
        engine.stop()
        isRunning = false
    }

    /// Created in a nonisolated factory so the render closure is not bound to the main actor.
    private nonisolated static func makeSourceNode(box: GraphBox, format: AVAudioFormat) -> AVAudioSourceNode {
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
        return AVAudioSourceNode(format: monoFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let frames = Int(frameCount)
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard frames <= box.scratch.count, let first = buffers.first, let data = first.mData else { return noErr }
            box.scratch.withUnsafeMutableBufferPointer { scratch in
                box.graph.render(into: scratch.baseAddress!, frameCount: frames)
                let out = data.bindMemory(to: Float.self, capacity: frames)
                for i in 0..<frames { out[i] = scratch[i] }
            }
            return noErr
        }
    }

    // MARK: - Convenience

    public func play() { events.push(.play) }
    public func stopSequencer() { events.push(.stop) }
    public func trigger(_ kind: DrumVoiceKind, velocity: Float = 1) { events.push(.drum(kind, velocity: velocity)) }
    public func bassNote(_ note: Int, accent: Bool = false, slide: Bool = false) { events.push(.bassNoteOn(note: note, accent: accent, slide: slide)) }
}
