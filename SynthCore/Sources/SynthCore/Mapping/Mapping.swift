//
//  Mapping.swift
//  SynthCore
//
//  How tracking drives the synth. Continuous sources (a nose, a wrist
//  height, a mouth) map to knobs, tempo or MIDI CCs through a range, a
//  curve and a smoother; event sources (a hand raised, a hit, hands
//  together) fire drums, bass notes, MIDI notes, patterns and steps.
//  The sources themselves are read by the app from its tracking scene;
//  this file is the pure logic and is tested.
//

import Foundation

public enum ContinuousSource: String, CaseIterable, Sendable, Codable, Identifiable {
    case noseX, noseY, leftWristHeight, rightWristHeight, jointSpeed, handOpenness, handSpread, handsDistance,
         bodyHeight, rootDepth, faceYaw, faceRoll, facePitch, mouthOpenness, humanCount, presence, activity
    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .noseX: "Nose across"; case .noseY: "Nose down"; case .leftWristHeight: "Left wrist height"
        case .rightWristHeight: "Right wrist height"; case .jointSpeed: "Movement speed"; case .handOpenness: "Hand openness"
        case .handSpread: "Hand spread"; case .handsDistance: "Hands apart"; case .bodyHeight: "Body height (3D)"
        case .rootDepth: "Distance (3D)"; case .faceYaw: "Face yaw"; case .faceRoll: "Face roll"; case .facePitch: "Face pitch"
        case .mouthOpenness: "Mouth openness"; case .humanCount: "Number of people"; case .presence: "Presence"; case .activity: "Activity"
        }
    }

    /// Natural input range of the source.
    public var defaultRange: ClosedRange<Float> {
        switch self {
        case .faceYaw, .faceRoll: -45...45
        case .facePitch: -30...30
        case .bodyHeight: 1...2
        case .rootDepth: 0.5...4
        case .humanCount: 0...4
        case .jointSpeed: 0...2
        default: 0...1
        }
    }
}

public enum EventSource: String, CaseIterable, Sendable, Codable, Identifiable {
    case leftHandRaised, rightHandRaised, anyHandRaised, hit, handsTogether, barcodeChanged, personEntered, personLeft, mouthOpened, beat
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .leftHandRaised: "Left hand raised"; case .rightHandRaised: "Right hand raised"; case .anyHandRaised: "Any hand raised"
        case .hit: "Hit (fast wrist)"; case .handsTogether: "Hands together"; case .barcodeChanged: "Code changed"
        case .personEntered: "Person entered"; case .personLeft: "Person left"; case .mouthOpened: "Mouth opened"; case .beat: "Every beat"
        }
    }
}

public enum ContinuousTarget: Sendable, Codable, Equatable, Hashable {
    case parameter(ParameterID)
    case midiCC(channel: Int, controller: Int)

    public var name: String {
        switch self {
        case .parameter(let id): id.name
        case .midiCC(let channel, let controller): "MIDI CC \(controller) ch \(channel)"
        }
    }
}

public enum EventTarget: Sendable, Codable, Equatable, Hashable {
    case drum(DrumVoiceKind)
    case bassNote(Int)
    case midiNote(channel: Int, note: Int)
    case selectPattern(Int)
    case toggleStep(DrumVoiceKind, Int)
    case advanceStep
    case playStop

    public var name: String {
        switch self {
        case .drum(let kind): kind.name
        case .bassNote(let note): "Bass note \(note)"
        case .midiNote(let channel, let note): "MIDI note \(note) ch \(channel)"
        case .selectPattern(let index): "Pattern \(index + 1)"
        case .toggleStep(let kind, let step): "Toggle \(kind.shortName) step \(step + 1)"
        case .advanceStep: "Advance step (conductor)"
        case .playStop: "Play / stop"
        }
    }
}

public enum Curve: String, CaseIterable, Sendable, Codable {
    case linear, exponential, logarithmic, sCurve
    public func apply(_ t: Float) -> Float {
        let x = min(max(t, 0), 1)
        switch self {
        case .linear: return x
        case .exponential: return x * x
        case .logarithmic: return sqrtf(x)
        case .sCurve: return x * x * (3 - 2 * x)
        }
    }
}

public struct ContinuousMapping: Sendable, Codable, Equatable, Identifiable {
    public var id = UUID()
    public var isEnabled = true
    public var source: ContinuousSource
    public var target: ContinuousTarget
    public var inputRange: ClosedRange<Float>
    public var outputRange: ClosedRange<Float>
    public var curve: Curve = .linear
    /// Seconds; 0 = instant.
    public var smoothing: Float = 0.1
    public var invert = false
    /// Which tracked person (0 = first).
    public var person = 0

    public init(source: ContinuousSource, target: ContinuousTarget, inputRange: ClosedRange<Float>? = nil, outputRange: ClosedRange<Float>) {
        self.source = source
        self.target = target
        self.inputRange = inputRange ?? source.defaultRange
        self.outputRange = outputRange
    }

    /// Input value → output value (before smoothing).
    public func map(_ value: Float) -> Float {
        let span = inputRange.upperBound - inputRange.lowerBound
        var t = span == 0 ? 0 : (value - inputRange.lowerBound) / span
        t = curve.apply(t)
        if invert { t = 1 - t }
        return outputRange.lowerBound + t * (outputRange.upperBound - outputRange.lowerBound)
    }
}

public struct EventMapping: Sendable, Codable, Equatable, Identifiable {
    public var id = UUID()
    public var isEnabled = true
    public var source: EventSource
    public var target: EventTarget
    public var velocity: Float = 1
    public var person = 0

    public init(source: EventSource, target: EventTarget) {
        self.source = source
        self.target = target
    }
}

/// Turns a continuous value into on/off edges with hysteresis and a
/// refractory period, so a wrist hovering at the threshold fires once.
public struct EdgeDetector: Sendable {
    public var threshold: Float
    public var hysteresis: Float
    public var refractory: Float
    private var isOn = false
    private var lastFire: Float = -.infinity
    private var initialised = false

    public init(threshold: Float, hysteresis: Float = 0.05, refractory: Float = 0.25) {
        self.threshold = threshold
        self.hysteresis = hysteresis
        self.refractory = refractory
    }

    /// Returns true on the rising edge only.
    public mutating func update(_ value: Float, time: Float) -> Bool {
        if !initialised {
            initialised = true
            isOn = value > threshold
            return false
        }
        if isOn {
            if value < threshold - hysteresis { isOn = false }
            return false
        }
        guard value > threshold, time - lastFire >= refractory else { return false }
        isOn = true
        lastFire = time
        return true
    }

    public mutating func reset() { isOn = false; initialised = false }
}

/// Per-mapping smoothing state, kept by the app between frames.
public struct MappingSmoother: Sendable {
    private var value: Float?
    public init() {}

    public mutating func next(target: Float, smoothing: Float, dt: Float) -> Float {
        guard let current = value, smoothing > 0 else { value = target; return target }
        let coefficient = min(1, dt / smoothing)
        let next = current + (target - current) * coefficient
        value = next
        return next
    }
}
