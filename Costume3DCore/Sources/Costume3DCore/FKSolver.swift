//
//  FKSolver.swift
//  Costume3DCore
//
//  Forward kinematics of rotations: for every driven joint, aim the rig's
//  bone (+X in Apple's convention) along the live direction from the
//  17-joint stream, expressed in the solved parent's frame, so the rig
//  keeps its own bone lengths and any proportions work. The hips, spine,
//  neck and head also take a side vector (the hip or shoulder line) so
//  the body's yaw and twist follow; limbs use the minimal rotation. Only
//  the hips translate. Rotations are smoothed with slerp; a missing body
//  holds its last pose.
//

import Foundation
import simd

/// What a driven joint should do this frame.
public struct BoneTarget: Sendable {
    /// Unit direction the bone's +X should point along, in scene space.
    public var direction: SIMD3<Float>
    /// Optional unit vector the bone's +Y should lean towards, for yaw and twist. In Apple's rest
    /// convention (+X up the spine, +Z forward) a spine joint's +Y points to the character's right.
    public var side: SIMD3<Float>?
    public init(direction: SIMD3<Float>, side: SIMD3<Float>? = nil) {
        self.direction = direction
        self.side = side
    }
}

public enum Retarget17 {
    /// Bone targets for Apple's rig from the 17 joints.
    public static func targets(for live: Live3D) -> [String: BoneTarget] {
        let j = live.joints
        guard j.count >= 17 else { return [:] }
        func dir(_ a: Int, _ b: Int) -> SIMD3<Float>? {
            let d = j[b] - j[a]
            let l = simd_length(d)
            return l > 1e-4 ? d / l : nil
        }
        var t: [String: BoneTarget] = [:]
        let hipSide = dir(Body3D.leftHip, Body3D.rightHip)
        let shoulderSide = dir(Body3D.leftShoulder, Body3D.rightShoulder)
        if let up = dir(Body3D.root, Body3D.centerShoulder) {
            t["hips_joint"] = BoneTarget(direction: up, side: hipSide)
            for i in 1...7 {
                let f = Float(i - 1) / 6
                var side: SIMD3<Float>?
                if let h = hipSide, let s = shoulderSide { side = simd_normalize(h * (1 - f) + s * f) } else { side = hipSide ?? shoulderSide }
                t["spine_\(i)_joint"] = BoneTarget(direction: up, side: side)
            }
        }
        if let neck = dir(Body3D.centerShoulder, Body3D.centerHead) {
            for i in 1...4 { t["neck_\(i)_joint"] = BoneTarget(direction: neck, side: shoulderSide) }
        }
        if let head = dir(Body3D.centerHead, Body3D.topHead) {
            t["head_joint"] = BoneTarget(direction: head, side: shoulderSide)
        }
        for (side, shoulder, elbow, wrist, hip, knee, ankle) in [
            ("left", Body3D.leftShoulder, Body3D.leftElbow, Body3D.leftWrist, Body3D.leftHip, Body3D.leftKnee, Body3D.leftAnkle),
            ("right", Body3D.rightShoulder, Body3D.rightElbow, Body3D.rightWrist, Body3D.rightHip, Body3D.rightKnee, Body3D.rightAnkle),
        ] {
            if let d = dir(Body3D.centerShoulder, shoulder) { t["\(side)_shoulder_1_joint"] = BoneTarget(direction: d) }
            if let d = dir(shoulder, elbow) { t["\(side)_arm_joint"] = BoneTarget(direction: d) }
            if let d = dir(elbow, wrist) {
                t["\(side)_forearm_joint"] = BoneTarget(direction: d)
                t["\(side)_hand_joint"] = BoneTarget(direction: d)
            }
            if let d = dir(hip, knee) { t["\(side)_upLeg_joint"] = BoneTarget(direction: d) }
            if let d = dir(knee, ankle) {
                t["\(side)_leg_joint"] = BoneTarget(direction: d)
                // Feet: keep flat, pointing forward relative to the hips.
                if let h = hipSide, let up = dir(Body3D.root, Body3D.centerShoulder) {
                    let forward = simd_normalize(simd_cross(up, h))
                    let flat = forward - SIMD3<Float>(0, 1, 0) * forward.y
                    if simd_length(flat) > 1e-4 { t["\(side)_foot_joint"] = BoneTarget(direction: simd_normalize(flat)) }
                }
            }
        }
        return t
    }

    /// Model-space height of a rest pose from the top of the head to the lowest joint.
    public static func restHeight(_ rest: RestPose) -> Float {
        let world = rest.worldTransforms().positions
        guard let top = rest.index(of: "head_joint") else { return 1.6 }
        let minY = world.map(\.y).min() ?? 0
        return max(0.1, world[top].y + 0.12 - minY)
    }
}

public struct FKResult: Sendable {
    /// Local rotation per rest-pose joint index (unchanged joints keep their rest rotation).
    public var localRotations: [simd_quatf]
    /// Where the hips joint's world position should be (scene space, model units already scaled).
    public var hipsPosition: SIMD3<Float>
    /// Uniform scale to make the rest pose the person's height.
    public var scale: Float
    /// World rotations per joint (for attaching extras).
    public var worldRotations: [simd_quatf]
}

public struct FKSolver: Sendable {
    /// Seconds to reach a new pose (one-pole).
    public var smoothing: Float = 0.06
    private var previous: FKResult?
    private var lastLive: Live3D?
    public init() {}

    public mutating func reset() { previous = nil; lastLive = nil }

    /// Solve the rest pose against a live body. Passing nil holds the last pose.
    public mutating func solve(rest: RestPose, live: Live3D?, deltaTime: Float) -> FKResult? {
        guard let live = live ?? lastLive else { return previous }
        lastLive = live
        let targets = Retarget17.targets(for: live)
        let restWorld = rest.worldTransforms()
        let scale = live.bodyHeight > 0.5 ? live.bodyHeight / Retarget17.restHeight(rest) : 1
        var local = rest.localRotations
        var world = restWorld.rotations
        for i in 0..<rest.count {
            let name = AppleRig.name(fromPath: rest.paths[i])
            let p = rest.parents[i]
            let parentWorld = p >= 0 ? world[p] : simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            if let target = targets[name] {
                let restX = restWorld.rotations[i].act(SIMD3<Float>(1, 0, 0))
                let delta: simd_quatf
                if let side = target.side {
                    // Full frame: X along the bone, Y towards the side vector.
                    let restY = restWorld.rotations[i].act(SIMD3<Float>(0, 1, 0))
                    let restFrame = Self.frame(x: restX, yHint: restY)
                    let liveFrame = Self.frame(x: target.direction, yHint: side)
                    delta = liveFrame * restFrame.inverse
                } else {
                    delta = Self.rotation(from: restX, to: target.direction)
                }
                let desiredWorld = delta * restWorld.rotations[i]
                local[i] = simd_normalize(parentWorld.inverse * desiredWorld)
            }
            world[i] = p >= 0 ? parentWorld * local[i] : local[i]
        }
        var result = FKResult(localRotations: local, hipsPosition: live.joints[Body3D.root], scale: scale, worldRotations: world)
        if let previous, previous.localRotations.count == local.count, smoothing > 0 {
            let t = min(1, deltaTime / smoothing)
            for i in 0..<local.count {
                result.localRotations[i] = simd_slerp(previous.localRotations[i], local[i], t)
            }
            result.hipsPosition = previous.hipsPosition + (result.hipsPosition - previous.hipsPosition) * t
            result.scale = previous.scale + (result.scale - previous.scale) * t
            // Recompute world rotations from the smoothed locals.
            for i in 0..<rest.count {
                let p = rest.parents[i]
                result.worldRotations[i] = p >= 0 ? result.worldRotations[p] * result.localRotations[i] : result.localRotations[i]
            }
        }
        previous = result
        return result
    }

    /// Minimal rotation taking unit `a` to unit `b`.
    public static func rotation(from a: SIMD3<Float>, to b: SIMD3<Float>) -> simd_quatf {
        let d = simd_dot(a, b)
        if d > 0.99999 { return simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)) }
        if d < -0.99999 {
            var axis = simd_cross(SIMD3<Float>(1, 0, 0), a)
            if simd_length(axis) < 1e-4 { axis = simd_cross(SIMD3<Float>(0, 1, 0), a) }
            return simd_quatf(angle: .pi, axis: simd_normalize(axis))
        }
        return simd_normalize(simd_quatf(from: a, to: b))
    }

    static func frame(x: SIMD3<Float>, yHint: SIMD3<Float>) -> simd_quatf {
        let xAxis = simd_normalize(x)
        var yAxis = yHint - xAxis * simd_dot(yHint, xAxis)
        if simd_length(yAxis) < 1e-4 {
            let alt = abs(xAxis.z) < 0.9 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
            yAxis = alt - xAxis * simd_dot(alt, xAxis)
        }
        yAxis = simd_normalize(yAxis)
        let zAxis = simd_cross(xAxis, yAxis)
        return simd_quatf(simd_float3x3(columns: (xAxis, yAxis, zAxis)))
    }
}
