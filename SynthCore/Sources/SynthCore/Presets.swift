//
//  Presets.swift
//  SynthCore
//
//  A preset is the whole instrument: parameters, patterns and mappings.
//

import Foundation

public struct SynthPreset: Codable, Equatable, Sendable {
    public var name: String
    public var parameters: [Int: Float]     // ParameterID raw values
    public var patterns: [StepPattern]
    public var patternIndex: Int
    public var continuous: [ContinuousMapping]
    public var events: [EventMapping]
    public var conductor: Bool

    public init(name: String, parameters: [ParameterID: Float], patterns: [StepPattern], patternIndex: Int,
                continuous: [ContinuousMapping], events: [EventMapping], conductor: Bool) {
        self.name = name
        self.parameters = Dictionary(uniqueKeysWithValues: parameters.map { ($0.key.rawValue, $0.value) })
        self.patterns = patterns
        self.patternIndex = patternIndex
        self.continuous = continuous
        self.events = events
        self.conductor = conductor
    }

    public var parameterValues: [ParameterID: Float] {
        Dictionary(uniqueKeysWithValues: parameters.compactMap { key, value in ParameterID(rawValue: key).map { ($0, value) } })
    }

    static func defaults() -> [ParameterID: Float] {
        Dictionary(uniqueKeysWithValues: ParameterID.allCases.map { ($0, $0.defaultValue) })
    }

    /// The bundled starting points.
    public static let builtIn: [SynthPreset] = [
        {
            var params = defaults()
            params[.bassCutoff] = 500; params[.bassResonance] = 0.75; params[.bassEnvMod] = 0.7; params[.delayMix] = 0.25
            var patterns = Array(repeating: StepPattern(), count: 8)
            patterns[0] = .starter()
            return SynthPreset(name: "Acid theremin", parameters: params, patterns: patterns, patternIndex: 0, continuous: [
                ContinuousMapping(source: .noseX, target: .parameter(.bassCutoff), outputRange: 150...5000),
                ContinuousMapping(source: .rightWristHeight, target: .parameter(.bassResonance), outputRange: 0.3...0.95),
                ContinuousMapping(source: .leftWristHeight, target: .parameter(.bassDecay), outputRange: 0.1...1.2),
                ContinuousMapping(source: .activity, target: .parameter(.delayFeedback), outputRange: 0.2...0.7),
            ], events: [
                EventMapping(source: .personEntered, target: .playStop),
            ], conductor: false)
        }(),
        {
            var params = defaults()
            params[.tempo] = 100
            var patterns = Array(repeating: StepPattern(), count: 8)
            patterns[0] = .starter()
            return SynthPreset(name: "Drum conductor", parameters: params, patterns: patterns, patternIndex: 0, continuous: [
                ContinuousMapping(source: .noseX, target: .parameter(.kickTune), outputRange: -0.5...0.5),
                ContinuousMapping(source: .mouthOpenness, target: .parameter(.snareTone), outputRange: 0.2...1),
            ], events: [
                EventMapping(source: .hit, target: .advanceStep),
                EventMapping(source: .leftHandRaised, target: .drum(.clap)),
                EventMapping(source: .rightHandRaised, target: .drum(.cowbell)),
            ], conductor: true)
        }(),
        {
            var params = defaults()
            params[.bassOverdrive] = 0.45; params[.reverbMix] = 0.2
            var patterns = Array(repeating: StepPattern(), count: 8)
            patterns[0] = .starter()
            return SynthPreset(name: "Two-hand filter", parameters: params, patterns: patterns, patternIndex: 0, continuous: [
                ContinuousMapping(source: .handsDistance, target: .parameter(.bassCutoff), outputRange: 120...6000),
                ContinuousMapping(source: .handOpenness, target: .parameter(.bassResonance), outputRange: 0.2...0.95),
                {
                    var m = ContinuousMapping(source: .noseY, target: .parameter(.bassOverdrive), inputRange: 0.2...0.6, outputRange: 0.1...0.6)
                    m.invert = true
                    return m
                }(),
                ContinuousMapping(source: .presence, target: .parameter(.masterLevel), outputRange: 0.2...0.85),
            ], events: [
                EventMapping(source: .handsTogether, target: .selectPattern(1)),
                EventMapping(source: .mouthOpened, target: .drum(.openHat)),
            ], conductor: false)
        }(),
    ]
}
