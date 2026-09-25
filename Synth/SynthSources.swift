//
//  SynthSources.swift
//  TrackOSC Synth (macOS)
//
//  Reads every mapping source out of the tracking scene (and the raw 3D
//  frame) once per tick. Continuous sources are values; event sources are
//  values too, fed to edge detectors, except the ones that are events by
//  nature (a code changing, a person arriving) which are reported as counts.
//

import Foundation
import PoseioscShared
import simd
import SynthCore

struct SourceReadings {
    var continuous: [ContinuousSource: Float] = [:]
    /// The raw value an EdgeDetector watches (threshold 0.5 unless noted).
    var event: [EventSource: Float] = [:]
    /// The latest code payload, for "code changed".
    var code: String?
    var personCount = 0
}

enum SynthSources {
    static let wristIndices = (left: 9, right: 10)
    static let shoulderIndices = (left: 5, right: 6)

    /// Read one person's sources (the `person`th by id) plus the scene-wide ones.
    static func read(scene: TrackingScene, latest: [FrameKind: TimestampedFrame], person index: Int, staleInterval: TimeInterval) -> SourceReadings {
        var r = SourceReadings()
        let persons = scene.persons.sorted { $0.id < $1.id }
        r.personCount = persons.count
        r.continuous[.humanCount] = Float(persons.count)
        r.continuous[.presence] = scene.presence
        r.continuous[.activity] = scene.activity

        let person = persons.indices.contains(index) ? persons[index] : persons.first
        if let person {
            if person.visible[0] {
                r.continuous[.noseX] = person.joints[0].x
                r.continuous[.noseY] = person.joints[0].y
            }
            if person.visible[wristIndices.left] { r.continuous[.leftWristHeight] = 1 - person.joints[wristIndices.left].y }
            if person.visible[wristIndices.right] { r.continuous[.rightWristHeight] = 1 - person.joints[wristIndices.right].y }
            r.continuous[.jointSpeed] = person.speed
            if person.visible[wristIndices.left], person.visible[wristIndices.right] {
                r.continuous[.handsDistance] = simd_distance(person.joints[wristIndices.left], person.joints[wristIndices.right])
            }
            // Raised = wrist above the same-side shoulder, measured in shoulder widths.
            let shoulderWidth = max(0.02, simd_distance(person.joints[shoulderIndices.left], person.joints[shoulderIndices.right]))
            func raised(_ wrist: Int, _ shoulder: Int) -> Float? {
                guard person.visible[wrist], person.visible[shoulder] else { return nil }
                return 0.5 + (person.joints[shoulder].y - person.joints[wrist].y) / shoulderWidth
            }
            let left = raised(wristIndices.left, shoulderIndices.left)
            let right = raised(wristIndices.right, shoulderIndices.right)
            if let left { r.event[.leftHandRaised] = left }
            if let right { r.event[.rightHandRaised] = right }
            if left != nil || right != nil { r.event[.anyHandRaised] = max(left ?? 0, right ?? 0) }
            // Hit: the faster wrist, in scene units per second (threshold 0.5 ≈ 1.5 u/s after scaling).
            var wristSpeed: Float = 0
            for w in [wristIndices.left, wristIndices.right] where person.visible[w] {
                wristSpeed = max(wristSpeed, simd_length(person.velocities[w]))
            }
            r.event[.hit] = wristSpeed / 3
            if let d = r.continuous[.handsDistance] {
                r.event[.handsTogether] = 0.5 + (0.6 - d / shoulderWidth) * 0.5   // together when closer than 0.6 shoulder widths
            }
            if let hand = person.hands.first ?? scene.hands.first {
                r.continuous[.handOpenness] = hand.openness
                r.continuous[.handSpread] = spread(of: hand)
            }
            if let face = person.face ?? scene.faces.first { readFace(face, into: &r) }
        } else {
            if let hand = scene.hands.first {
                r.continuous[.handOpenness] = hand.openness
                r.continuous[.handSpread] = spread(of: hand)
            }
            if scene.hands.count >= 2 {
                r.continuous[.handsDistance] = simd_distance(scene.hands[0].centre, scene.hands[1].centre)
            }
            if let face = scene.faces.first { readFace(face, into: &r) }
        }

        // 3D body: height and distance straight from the raw frame.
        if let frame = latest[.poses3D], Date().timeIntervalSince(frame.receivedAt) < staleInterval,
           case .poses3D(let f) = frame.decoded {
            let poses = f.detections
            if poses.indices.contains(index) || !poses.isEmpty {
                let pose = poses.indices.contains(index) ? poses[index] : poses[0]
                if pose.bodyHeight > 0 { r.continuous[.bodyHeight] = pose.bodyHeight }
                if let d = FrameMetrics.distance(of: pose) { r.continuous[.rootDepth] = Float(d) }
            }
        }

        // Codes: the most recent code payload in the scene.
        r.code = scene.texts.first { $0.isCode }?.text
        return r
    }

    private static func readFace(_ face: SceneFace, into r: inout SourceReadings) {
        r.continuous[.faceYaw] = face.yawDegrees
        r.continuous[.faceRoll] = face.rollDegrees
        r.continuous[.facePitch] = face.pitchDegrees
        r.continuous[.mouthOpenness] = face.mouthOpenness
        r.event[.mouthOpened] = face.mouthOpenness * 1.5
    }

    /// Index tip to pinky tip over wrist to middle MCP: about 0 closed, 1 spread.
    private static func spread(of hand: SceneHand) -> Float {
        guard hand.joints.count >= 21 else { return hand.openness }
        let size = max(0.005, simd_distance(hand.joints[0], hand.joints[9]))
        return min(1, simd_distance(hand.joints[8], hand.joints[20]) / size)
    }
}
