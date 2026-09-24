//
//  RestPose.swift
//  Costume3DCore
//
//  A skeleton's rest (bind) pose as joint paths, parents and local
//  transforms, plus a synthetic T-pose in Apple's conventions used by the
//  mannequin, the tests and the bundled Blocky model.
//

import Foundation
import simd

public struct RestPose: Sendable {
    /// RealityKit-style paths ("root/hips_joint/…"), parents before children.
    public var paths: [String]
    /// Index of each joint's parent, −1 for the root.
    public var parents: [Int]
    public var localRotations: [simd_quatf]
    public var localTranslations: [SIMD3<Float>]

    public init(paths: [String], parents: [Int], localRotations: [simd_quatf], localTranslations: [SIMD3<Float>]) {
        self.paths = paths
        self.parents = parents
        self.localRotations = localRotations
        self.localTranslations = localTranslations
    }

    public var count: Int { paths.count }
    public var names: [String] { paths.map(AppleRig.name(fromPath:)) }

    public func index(of name: String) -> Int? {
        paths.firstIndex { AppleRig.name(fromPath: $0) == name }
    }

    /// World rotation and position of every joint in the rest pose.
    public func worldTransforms() -> (rotations: [simd_quatf], positions: [SIMD3<Float>]) {
        var rotations = [simd_quatf](repeating: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)), count: count)
        var positions = [SIMD3<Float>](repeating: .zero, count: count)
        for i in 0..<count {
            let p = parents[i]
            if p < 0 {
                rotations[i] = localRotations[i]
                positions[i] = localTranslations[i]
            } else {
                rotations[i] = rotations[p] * localRotations[i]
                positions[i] = positions[p] + rotations[p].act(localTranslations[i])
            }
        }
        return (rotations, positions)
    }

    /// Build a rest pose from world positions in Apple's convention: each
    /// joint's +X points to its (first) child; leaves inherit the parent's
    /// direction. `up` picks the frame's roll.
    public static func fromWorldPositions(_ positions: [String: SIMD3<Float>], joints: [(name: String, parent: String?)] = AppleRig.joints) -> RestPose {
        let names = joints.map(\.name)
        let index = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        var parents = [Int](repeating: -1, count: names.count)
        var firstChild = [Int](repeating: -1, count: names.count)
        for (i, j) in joints.enumerated() {
            if let p = j.parent, let pi = index[p] {
                parents[i] = pi
                if firstChild[pi] < 0 { firstChild[pi] = i }
            }
        }
        var worldRot = [simd_quatf](repeating: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)), count: names.count)
        var worldPos = [SIMD3<Float>](repeating: .zero, count: names.count)
        for i in 0..<names.count {
            let pos = positions[names[i]] ?? (parents[i] >= 0 ? worldPos[parents[i]] : .zero)
            worldPos[i] = pos
            var axis: SIMD3<Float>
            let preferred = axisChild[names[i]]
            if let preferred, let some = preferred, let childPos = positions[some], simd_length(childPos - pos) > 1e-5 {
                axis = simd_normalize(childPos - pos)
            } else if preferred == nil, firstChild[i] >= 0, let childPos = positions[names[firstChild[i]]], simd_length(childPos - pos) > 1e-5 {
                axis = simd_normalize(childPos - pos)
            } else if parents[i] >= 0 {
                axis = worldRot[parents[i]].act(SIMD3<Float>(1, 0, 0))
            } else {
                axis = SIMD3<Float>(0, 1, 0)
            }
            worldRot[i] = frame(x: axis, hint: SIMD3<Float>(0, 0, 1))
        }
        var localRot: [simd_quatf] = [], localTrans: [SIMD3<Float>] = []
        for i in 0..<names.count {
            let p = parents[i]
            if p < 0 {
                localRot.append(worldRot[i]); localTrans.append(worldPos[i])
            } else {
                localRot.append(worldRot[p].inverse * worldRot[i])
                localTrans.append(worldRot[p].inverse.act(worldPos[i] - worldPos[p]))
            }
        }
        let paths = names.map(AppleRig.path(of:))
        return RestPose(paths: paths, parents: parents, localRotations: localRot, localTranslations: localTrans)
    }

    /// Joints whose +X should not follow their first child: the hand aims down the middle finger,
    /// the head continues the neck (nil child), the eyes look forward.
    static let axisChild: [String: String?] = [
        "left_hand_joint": "left_handMidStart_joint", "right_hand_joint": "right_handMidStart_joint",
        "head_joint": nil, "left_eye_joint": "left_eyeball_joint", "right_eye_joint": "right_eyeball_joint",
    ]

    /// A rotation whose +X is `x`, with +Z as close to `hint` as possible.
    public static func frame(x: SIMD3<Float>, hint: SIMD3<Float>) -> simd_quatf {
        let xAxis = simd_normalize(x)
        var zAxis = hint - xAxis * simd_dot(hint, xAxis)
        if simd_length(zAxis) < 1e-4 {
            let alt = abs(xAxis.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            zAxis = alt - xAxis * simd_dot(alt, xAxis)
        }
        zAxis = simd_normalize(zAxis)
        let yAxis = simd_cross(zAxis, xAxis)
        return simd_quatf(simd_float3x3(columns: (xAxis, yAxis, zAxis)))
    }

    /// Apple-convention T-pose positions, metres: +Y up, facing +Z, left hand along +X.
    public static let tPosePositions: [String: SIMD3<Float>] = {
        var p: [String: SIMD3<Float>] = [:]
        p["root"] = SIMD3<Float>(0, 0, 0)
        p["hips_joint"] = SIMD3<Float>(0, 0.92, 0)
        for i in 1...7 { p["spine_\(i)_joint"] = SIMD3<Float>(0, 0.98 + Float(i - 1) * 0.0667, 0) }
        for i in 1...4 { p["neck_\(i)_joint"] = SIMD3<Float>(0, 1.42 + Float(i - 1) * 0.033, 0) }
        p["head_joint"] = SIMD3<Float>(0, 1.55, 0)
        p["jaw_joint"] = SIMD3<Float>(0, 1.56, 0.04)
        p["chin_joint"] = SIMD3<Float>(0, 1.53, 0.09)
        p["nose_joint"] = SIMD3<Float>(0, 1.62, 0.10)
        for (side, s) in [("left", Float(1)), ("right", Float(-1))] {
            p["\(side)_eye_joint"] = SIMD3<Float>(0.03 * s, 1.64, 0.08)
            p["\(side)_eyeUpperLid_joint"] = SIMD3<Float>(0.03 * s, 1.655, 0.09)
            p["\(side)_eyeLowerLid_joint"] = SIMD3<Float>(0.03 * s, 1.625, 0.09)
            p["\(side)_eyeball_joint"] = SIMD3<Float>(0.03 * s, 1.64, 0.10)
            p["\(side)_shoulder_1_joint"] = SIMD3<Float>(0.07 * s, 1.40, 0)
            p["\(side)_arm_joint"] = SIMD3<Float>(0.19 * s, 1.40, 0)
            p["\(side)_forearm_joint"] = SIMD3<Float>(0.47 * s, 1.40, 0)
            p["\(side)_hand_joint"] = SIMD3<Float>(0.73 * s, 1.40, 0)
            let fingers: [(String, Float, Float)] = [("Pinky", -0.040, 0.070), ("Ring", -0.016, 0.085), ("Mid", 0, 0.090), ("Index", 0.024, 0.082)]
            for (finger, z, length) in fingers {
                p["\(side)_hand\(finger)Start_joint"] = SIMD3<Float>(0.76 * s, 1.40, z)
                p["\(side)_hand\(finger)_1_joint"] = SIMD3<Float>((0.76 + 0.06) * s, 1.40, z)
                p["\(side)_hand\(finger)_2_joint"] = SIMD3<Float>((0.76 + 0.06 + length * 0.45) * s, 1.40, z)
                p["\(side)_hand\(finger)_3_joint"] = SIMD3<Float>((0.76 + 0.06 + length * 0.75) * s, 1.40, z)
                p["\(side)_hand\(finger)End_joint"] = SIMD3<Float>((0.76 + 0.06 + length) * s, 1.40, z)
            }
            p["\(side)_handThumbStart_joint"] = SIMD3<Float>(0.75 * s, 1.39, 0.035)
            p["\(side)_handThumb_1_joint"] = SIMD3<Float>(0.78 * s, 1.385, 0.06)
            p["\(side)_handThumb_2_joint"] = SIMD3<Float>(0.81 * s, 1.38, 0.08)
            p["\(side)_handThumbEnd_joint"] = SIMD3<Float>(0.835 * s, 1.375, 0.095)
            p["\(side)_upLeg_joint"] = SIMD3<Float>(0.10 * s, 0.90, 0)
            p["\(side)_leg_joint"] = SIMD3<Float>(0.10 * s, 0.48, 0)
            p["\(side)_foot_joint"] = SIMD3<Float>(0.10 * s, 0.07, 0)
            p["\(side)_toes_joint"] = SIMD3<Float>(0.10 * s, 0.02, 0.10)
            p["\(side)_toesEnd_joint"] = SIMD3<Float>(0.10 * s, 0.02, 0.18)
        }
        return p
    }()

    public static func tPose() -> RestPose { fromWorldPositions(tPosePositions) }
}
