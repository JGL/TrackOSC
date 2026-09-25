//
//  LayerName.swift
//  CostumeCore
//
//  The layer naming grammar: `prefix:part[:side][.flag...]`, resolved from
//  inkscape:label → data-name → serif:id → id. Case-insensitive; spaces,
//  hyphens and underscores in parts are ignored ("upper arm" = "upperArm").
//
//    bone:torso | bone:shoulders | bone:hips | bone:neck
//    bone:upperArm:left | bone:forearm:right | bone:hand:left
//    bone:thigh:left | bone:shin:right | bone:foot:left
//    head
//    face:leftEye | face:rightEye | face:leftBrow | face:rightBrow
//    face:nose | face:mouth | face:jaw | face:face
//    hand:palm[:left|right|any] | hand:thumb | hand:index | hand:middle
//    hand:ring | hand:pinky, with an optional phalanx 1–3: hand:index:2:left
//    guide:torso | guide:shoulders | guide:head   (never drawn)
//    pivot                                        (a two-point path inside a layer)
//    flags: .stretch .fixed .noflip .front .back
//

import Foundation

public enum Side: String, Sendable, Codable, CaseIterable { case left, right }

public enum BodyBone: String, Sendable, Codable, CaseIterable {
    case torso, shoulders, hips, neck, upperArm, forearm, hand, thigh, shin, foot
    /// Whether the part comes in a left and right.
    public var isSided: Bool {
        switch self {
        case .torso, .shoulders, .hips, .neck: false
        default: true
        }
    }
    /// The art axis when no pivot is drawn: vertical (top→bottom) or horizontal (left→right).
    public var defaultAxisIsHorizontal: Bool { self == .shoulders || self == .hips }
}

public enum FacePart: String, Sendable, Codable, CaseIterable {
    case leftEye, rightEye, leftBrow, rightBrow, nose, mouth, jaw, face
}

public enum HandPart: String, Sendable, Codable, CaseIterable {
    case palm, thumb, index, middle, ring, pinky
}

public enum HandSide: String, Sendable, Codable, CaseIterable { case left, right, any }

public enum LayerRole: Sendable, Equatable {
    case bone(BodyBone, Side?)
    case head
    case face(FacePart)
    case hand(HandPart, phalanx: Int?, HandSide)
    case guide(String)
    case pivot
    /// Drawn where it sits in the document, fitted to the stage.
    case scenery
}

public struct LayerFlags: OptionSet, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Scale along the bone only; width follows the figure's overall scale.
    public static let stretch = LayerFlags(rawValue: 1 << 0)
    /// Never scale with the bone; only the figure's overall scale.
    public static let fixed = LayerFlags(rawValue: 1 << 1)
    /// Do not mirror when the person faces away.
    public static let noflip = LayerFlags(rawValue: 1 << 2)
    /// Only shown when facing the camera.
    public static let front = LayerFlags(rawValue: 1 << 3)
    /// Only shown when facing away.
    public static let back = LayerFlags(rawValue: 1 << 4)
}

public struct LayerName: Sendable, Equatable {
    public var role: LayerRole
    public var flags: LayerFlags
    public var original: String

    /// nil when the label does not follow the grammar (the layer is scenery).
    public static func parse(_ label: String) -> LayerName? {
        var text = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Flags: everything after the first "." that is a known flag word.
        var flags = LayerFlags()
        let dotParts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if dotParts.count > 1 {
            text = dotParts[0]
            for flag in dotParts.dropFirst() {
                switch normalise(flag) {
                case "stretch": flags.insert(.stretch)
                case "fixed": flags.insert(.fixed)
                case "noflip": flags.insert(.noflip)
                case "front": flags.insert(.front)
                case "back": flags.insert(.back)
                default: break
                }
            }
        }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map { normalise(String($0)) }
        guard let prefix = parts.first else { return nil }
        let rest = Array(parts.dropFirst())

        func side(_ s: String?) -> Side? {
            switch s { case "left", "l": .left; case "right", "r": .right; default: nil }
        }

        switch prefix {
        case "bone", "body":
            guard let partName = rest.first else { return nil }
            guard let bone = BodyBone.allCases.first(where: { normalise($0.rawValue) == partName }) ?? Self.boneAliases[partName] else { return nil }
            let s = rest.count > 1 ? side(rest[1]) : nil
            return LayerName(role: .bone(bone, bone.isSided ? s : nil), flags: flags, original: label)
        case "head":
            return LayerName(role: .head, flags: flags, original: label)
        case "face":
            guard let partName = rest.first else { return LayerName(role: .face(.face), flags: flags, original: label) }
            guard let part = FacePart.allCases.first(where: { normalise($0.rawValue) == partName }) ?? Self.faceAliases[partName] else { return nil }
            return LayerName(role: .face(part), flags: flags, original: label)
        case "hand":
            guard let partName = rest.first else { return LayerName(role: .hand(.palm, phalanx: nil, .any), flags: flags, original: label) }
            guard let part = HandPart.allCases.first(where: { normalise($0.rawValue) == partName }) ?? Self.handAliases[partName] else { return nil }
            var phalanx: Int?
            var handSide = HandSide.any
            for extra in rest.dropFirst() {
                if let n = Int(extra), (1...3).contains(n) { phalanx = n }
                else if let s = side(extra) { handSide = s == .left ? .left : .right }
                else if extra == "any" { handSide = .any }
            }
            return LayerName(role: .hand(part, phalanx: part == .palm ? nil : phalanx, handSide), flags: flags, original: label)
        case "guide":
            return LayerName(role: .guide(rest.first ?? ""), flags: flags, original: label)
        case "pivot":
            return LayerName(role: .pivot, flags: flags, original: label)
        default:
            return nil
        }
    }

    static func normalise(_ s: String) -> String {
        s.lowercased().filter { !" -_".contains($0) }
    }

    static let boneAliases: [String: BodyBone] = [
        "body": .torso, "chest": .torso, "spine": .torso, "pelvis": .hips, "arm": .upperArm, "upperarm": .upperArm,
        "lowerarm": .forearm, "leg": .thigh, "upperleg": .thigh, "lowerleg": .shin, "calf": .shin, "shoulder": .shoulders, "hip": .hips,
    ]
    static let faceAliases: [String: FacePart] = [
        "lefteyebrow": .leftBrow, "righteyebrow": .rightBrow, "lips": .mouth, "chin": .jaw, "contour": .jaw, "eyel": .leftEye, "eyer": .rightEye,
    ]
    static let handAliases: [String: HandPart] = ["little": .pinky, "pointer": .index]
}
