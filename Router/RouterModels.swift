//
//  RouterModels.swift
//  TrackOSC Router (macOS)
//
//  Rules are data: a trigger over a value source, and an action. They are
//  Codable so they save as JSON, export, import and ship as presets.
//

import Foundation
import PoseioscShared

extension FrameKind: Codable {}

/// A number or a string read from the latest frames.
enum SourceKind: String, Codable, CaseIterable, Identifiable {
    case peopleCount, handCount, faceCount, animalCount, textCount, barcodeCount, humanCount
    case noseX, noseY, jointX, jointY, leftHandRaised, rightHandRaised
    case handJointX, handJointY
    case faceCentreX, faceCentreY, faceWidth, faceYaw, facePitch, faceRoll, mouthOpenness
    case distance3D, bodyHeight
    case recognisedText, barcodePayload, barcodeSymbology, animalLabel

    var id: String { rawValue }

    var label: String {
        switch self {
        case .peopleCount: "Number of people (2D body)"
        case .handCount: "Number of hands"
        case .faceCount: "Number of faces"
        case .animalCount: "Number of animals"
        case .textCount: "Number of text boxes"
        case .barcodeCount: "Number of codes"
        case .humanCount: "Number of humans (rectangles)"
        case .noseX: "Nose, across (0 left … 1 right)"
        case .noseY: "Nose, down (0 top … 1 bottom)"
        case .jointX: "Body joint, across"
        case .jointY: "Body joint, down"
        case .leftHandRaised: "Left hand raised (0 or 1)"
        case .rightHandRaised: "Right hand raised (0 or 1)"
        case .handJointX: "Hand joint, across"
        case .handJointY: "Hand joint, down"
        case .faceCentreX: "Face centre, across"
        case .faceCentreY: "Face centre, down"
        case .faceWidth: "Face width (fraction of frame)"
        case .faceYaw: "Face yaw (degrees)"
        case .facePitch: "Face pitch (degrees)"
        case .faceRoll: "Face roll (degrees)"
        case .mouthOpenness: "Mouth openness (0 closed … 1 wide)"
        case .distance3D: "Distance from camera (metres, 3D body)"
        case .bodyHeight: "Body height (metres, 3D body)"
        case .recognisedText: "Recognised text"
        case .barcodePayload: "Code payload"
        case .barcodeSymbology: "Code symbology"
        case .animalLabel: "Animal label"
        }
    }

    var isText: Bool {
        switch self {
        case .recognisedText, .barcodePayload, .barcodeSymbology, .animalLabel: true
        default: false
        }
    }

    var usesJoint: Bool {
        switch self {
        case .jointX, .jointY, .handJointX, .handJointY: true
        default: false
        }
    }

    var jointNames: [String] {
        switch self {
        case .handJointX, .handJointY: JointOrder.hand21
        default: JointOrder.body17
        }
    }

    var usesPerson: Bool {
        switch self {
        case .peopleCount, .handCount, .faceCount, .animalCount, .textCount, .barcodeCount, .humanCount: false
        default: true
        }
    }

    /// A sensible input range for continuous mapping and thresholds.
    var defaultRange: ClosedRange<Double> {
        switch self {
        case .peopleCount, .handCount, .faceCount, .animalCount, .textCount, .barcodeCount, .humanCount: 0...4
        case .faceYaw, .faceRoll: -45...45
        case .facePitch: -30...30
        case .distance3D: 0.5...4
        case .bodyHeight: 1...2
        case .faceWidth: 0...0.5
        default: 0...1
        }
    }
}

struct ValueSource: Codable, Hashable {
    var kind: SourceKind = .noseX
    /// Joint index for the joint sources (see `SourceKind.jointNames`).
    var joint: Int = 0
    /// Which detection, 0 = first.
    var person: Int = 0
}

enum SourceValue: Equatable, Sendable {
    case number(Double)
    case text(String)
    case none

    var number: Double? { if case .number(let v) = self { return v } else { return nil } }
    var text: String? { if case .text(let t) = self { return t } else { return nil } }

    var display: String {
        switch self {
        case .number(let v): v == v.rounded() && abs(v) < 1000 ? String(Int(v)) : String(format: "%.3f", v)
        case .text(let t): "\"\(t)\""
        case .none: "–"
        }
    }
}

enum EdgeKind: String, Codable, CaseIterable, Identifiable {
    case appear, leave, change
    var id: String { rawValue }
    var label: String {
        switch self { case .appear: "appears"; case .leave: "leaves"; case .change: "count changes" }
    }
}

enum Direction: String, Codable, CaseIterable, Identifiable {
    case rise, fall
    var id: String { rawValue }
    var label: String { self == .rise ? "rises above" : "falls below" }
}

enum RangeEdge: String, Codable, CaseIterable, Identifiable {
    case enter, exit
    var id: String { rawValue }
    var label: String { self == .enter ? "enters" : "leaves" }
}

enum MatchMode: String, Codable, CaseIterable, Identifiable {
    case equals, contains, regex
    var id: String { rawValue }
    var label: String { rawValue }
}

enum Trigger: Codable, Hashable {
    case presence(kind: FrameKind, edge: EdgeKind)
    case threshold(source: ValueSource, value: Double, direction: Direction, hysteresis: Double)
    case range(source: ValueSource, low: Double, high: Double, edge: RangeEdge)
    case continuous(source: ValueSource, inMin: Double, inMax: Double, outMin: Double, outMax: Double, rateHz: Double)
    case stringMatch(source: ValueSource, mode: MatchMode, pattern: String, cooldown: Double)

    var source: ValueSource? {
        switch self {
        case .presence: nil
        case .threshold(let s, _, _, _), .range(let s, _, _, _), .continuous(let s, _, _, _, _, _), .stringMatch(let s, _, _, _): s
        }
    }

    var isContinuous: Bool { if case .continuous = self { return true } else { return false } }

    var summary: String {
        switch self {
        case .presence(let kind, let edge): "\(kind.address) \(edge.label)"
        case .threshold(let s, let v, let d, _): "\(s.kind.label) \(d.label) \(v.formatted())"
        case .range(let s, let low, let high, let edge): "\(s.kind.label) \(edge.label) \(low.formatted())…\(high.formatted())"
        case .continuous(let s, let inMin, let inMax, let outMin, let outMax, let hz): "\(s.kind.label) \(inMin.formatted())…\(inMax.formatted()) → \(outMin.formatted())…\(outMax.formatted()) at \(hz.formatted()) Hz"
        case .stringMatch(let s, let mode, let pattern, _): "\(s.kind.label) \(mode.label) \"\(pattern)\""
        }
    }
}

struct KeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: Int
    static let command = KeyModifiers(rawValue: 1)
    static let shift = KeyModifiers(rawValue: 2)
    static let option = KeyModifiers(rawValue: 4)
    static let control = KeyModifiers(rawValue: 8)
}

enum Action: Codable, Hashable {
    case midiNote(channel: Int, note: Int, velocity: Int, durationMs: Int)
    case midiCC(channel: Int, controller: Int, value: Int)
    case shortcut(name: String, input: String)
    case keyPress(keyCode: Int, modifiers: KeyModifiers)
    case http(method: String, url: String, body: String)
    case log

    var summary: String {
        switch self {
        case .midiNote(let ch, let note, let vel, let ms): "MIDI note \(note) vel \(vel) ch \(ch) for \(ms) ms"
        case .midiCC(let ch, let cc, let value): "MIDI CC \(cc) = \(value) ch \(ch)"
        case .shortcut(let name, _): "Shortcut \"\(name)\""
        case .keyPress(let code, let mods): "Key \(KeyCodes.name(for: code, modifiers: mods))"
        case .http(let method, let url, _): "\(method) \(url)"
        case .log: "Log only"
        }
    }
}

struct Rule: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var isEnabled = true
    var trigger: Trigger
    var action: Action
}

/// What a rule fires with: the mapped or raw value and any text.
struct Firing: Sendable {
    var rule: Rule
    var value: Double?
    var text: String?
    var time: Date = .now

    /// Fills {value}, {text} and {rule} in templates.
    func fill(_ template: String) -> String {
        template
            .replacingOccurrences(of: "{value}", with: value.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.3f", $0) } ?? "")
            .replacingOccurrences(of: "{text}", with: text ?? "")
            .replacingOccurrences(of: "{rule}", with: rule.name)
    }
}

enum KeyCodes {
    /// Virtual key codes for the keys a rule may press (ANSI layout).
    static let common: [(name: String, code: Int)] = [
        ("Space", 49), ("Return", 36), ("Tab", 48), ("Escape", 53), ("Delete", 51),
        ("Left arrow", 123), ("Right arrow", 124), ("Down arrow", 125), ("Up arrow", 126),
        ("Page up", 116), ("Page down", 121), ("Home", 115), ("End", 119),
        ("A", 0), ("B", 11), ("C", 8), ("D", 2), ("E", 14), ("F", 3), ("G", 5), ("H", 4), ("I", 34), ("J", 38),
        ("K", 40), ("L", 37), ("M", 46), ("N", 45), ("O", 31), ("P", 35), ("Q", 12), ("R", 15), ("S", 1),
        ("T", 17), ("U", 32), ("V", 9), ("W", 13), ("X", 7), ("Y", 16), ("Z", 6),
        ("0", 29), ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("5", 23), ("6", 22), ("7", 26), ("8", 28), ("9", 25),
        ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118), ("F5", 96), ("F6", 97), ("F7", 98), ("F8", 100),
        ("F9", 101), ("F10", 109), ("F11", 103), ("F12", 111),
    ]

    static func name(for code: Int, modifiers: KeyModifiers) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(common.first { $0.code == code }?.name ?? "key \(code)")
        return parts.joined()
    }
}
