//
//  Parts.swift
//  Costume3DCore
//
//  The no-rigging path: a folder of models named per bone (the SVG
//  costumes' `bone:` vocabulary) and the maths that hangs each one on a
//  live joint pair: aim the part's long axis along the bone, scale it to
//  the bone's length, sit its start at the first joint.
//

import Foundation
import simd

/// Bones a part can be named after (file names like `forearm-left.usdz`).
public enum PartBone: String, CaseIterable, Sendable {
    case torso, neck, head, shoulders, hips
    case upperArmLeft = "upperArm-left", forearmLeft = "forearm-left", handLeft = "hand-left"
    case upperArmRight = "upperArm-right", forearmRight = "forearm-right", handRight = "hand-right"
    case thighLeft = "thigh-left", shinLeft = "shin-left", footLeft = "foot-left"
    case thighRight = "thigh-right", shinRight = "shin-right", footRight = "foot-right"

    /// Accepts "forearm_left", "ForearmLeft", "forearm-left", "left-forearm"…
    public static func match(fileName: String) -> PartBone? {
        let key = fileName.lowercased().filter { $0.isLetter }
        for bone in allCases {
            let candidates = [bone.rawValue.lowercased().filter { $0.isLetter }]
            let parts = bone.rawValue.split(separator: "-").map { $0.lowercased() }
            let swapped = parts.count == 2 ? parts[1] + parts[0] : nil
            if candidates.contains(key) || swapped == key { return bone }
        }
        return nil
    }

    /// The live joint pair (start, end) in Body3D indices, or an extrapolated end.
    public func segment(in live: Live3D) -> (SIMD3<Float>, SIMD3<Float>)? {
        let j = live.joints
        guard j.count >= 17 else { return nil }
        func beyond(_ a: Int, _ b: Int, _ factor: Float) -> (SIMD3<Float>, SIMD3<Float>) { (j[b], j[b] + (j[b] - j[a]) * factor) }
        switch self {
        case .torso: return (j[Body3D.root], j[Body3D.centerShoulder])
        case .neck: return (j[Body3D.centerShoulder], j[Body3D.centerHead])
        case .head: return (j[Body3D.centerHead], j[Body3D.topHead] + (j[Body3D.topHead] - j[Body3D.centerHead]) * 0.3)
        case .shoulders: return (j[Body3D.rightShoulder], j[Body3D.leftShoulder])
        case .hips: return (j[Body3D.rightHip], j[Body3D.leftHip])
        case .upperArmLeft: return (j[Body3D.leftShoulder], j[Body3D.leftElbow])
        case .forearmLeft: return (j[Body3D.leftElbow], j[Body3D.leftWrist])
        case .handLeft: return beyond(Body3D.leftElbow, Body3D.leftWrist, 0.4)
        case .upperArmRight: return (j[Body3D.rightShoulder], j[Body3D.rightElbow])
        case .forearmRight: return (j[Body3D.rightElbow], j[Body3D.rightWrist])
        case .handRight: return beyond(Body3D.rightElbow, Body3D.rightWrist, 0.4)
        case .thighLeft: return (j[Body3D.leftHip], j[Body3D.leftKnee])
        case .shinLeft: return (j[Body3D.leftKnee], j[Body3D.leftAnkle])
        case .footLeft: return beyond(Body3D.leftKnee, Body3D.leftAnkle, 0.25)
        case .thighRight: return (j[Body3D.rightHip], j[Body3D.rightKnee])
        case .shinRight: return (j[Body3D.rightKnee], j[Body3D.rightAnkle])
        case .footRight: return beyond(Body3D.rightKnee, Body3D.rightAnkle, 0.25)
        }
    }
}

/// Where a part goes: position of its axis start, rotation, uniform scale.
public struct PartPlacement: Sendable, Equatable {
    public var position: SIMD3<Float>
    public var rotation: simd_quatf
    public var scale: Float
}

public enum PartsMath {
    /// A model's art axis: the long axis of its bounding box, from the face nearest `preferStart` to the opposite one.
    public static func axis(ofBounds minimum: SIMD3<Float>, _ maximum: SIMD3<Float>) -> (start: SIMD3<Float>, end: SIMD3<Float>) {
        let size = maximum - minimum
        let centre = (minimum + maximum) / 2
        if size.y >= size.x && size.y >= size.z {
            // Vertical parts are drawn top-down like the SVG costumes: start at the top.
            return (SIMD3<Float>(centre.x, maximum.y, centre.z), SIMD3<Float>(centre.x, minimum.y, centre.z))
        } else if size.x >= size.z {
            return (SIMD3<Float>(minimum.x, centre.y, centre.z), SIMD3<Float>(maximum.x, centre.y, centre.z))
        } else {
            return (SIMD3<Float>(centre.x, centre.y, minimum.z), SIMD3<Float>(centre.x, centre.y, maximum.z))
        }
    }

    /// Maps the art axis onto the live segment: scale by length ratio, rotate art direction onto live direction, translate.
    public static func place(artAxis: (start: SIMD3<Float>, end: SIMD3<Float>), on segment: (SIMD3<Float>, SIMD3<Float>), fixedScale: Float? = nil) -> PartPlacement {
        let artVector = artAxis.end - artAxis.start
        let artLength = max(1e-4, simd_length(artVector))
        let liveVector = segment.1 - segment.0
        let liveLength = simd_length(liveVector)
        let scale = fixedScale ?? (liveLength > 1e-4 ? liveLength / artLength : 1)
        let rotation = liveLength > 1e-4 ? FKSolver.rotation(from: artVector / artLength, to: liveVector / liveLength) : simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        // The entity's origin lands so that the art start sits on the live start.
        let position = segment.0 - rotation.act(artAxis.start * scale)
        return PartPlacement(position: position, rotation: rotation, scale: scale)
    }
}
