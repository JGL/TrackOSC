//
//  PersonTracker.swift
//  TrackOSC (ReceiverCore)
//
//  Gives each detected body a stable identity across frames (greedy nearest
//  centroid, with a grace period so a dropped frame does not create a new
//  person), and smooths joints with a one-pole filter that also yields
//  velocities.
//

import Foundation
import simd

struct PersonTracker: Sendable {
    struct Tracked: Sendable {
        let id: Int
        var joints: [SIMD2<Float>]
        var visible: [Bool]
        var velocities: [SIMD2<Float>]
        var speed: Float
        var firstSeen: Float
        var lastSeen: Float
        var missing: Bool
    }

    /// Seconds a person survives without a matching detection.
    var grace: Float = 0.5
    /// Largest centroid jump (scene units) still considered the same person.
    var maxJump: Float = 0.25
    /// One-pole smoothing time constant in seconds (0 = none).
    var smoothing: Float = 0.08

    private(set) var tracked: [Tracked] = []
    private var nextID = 1

    /// Feed one frame of normalised skeletons (17 joints each, with visibility).
    mutating func update(detections: [(joints: [SIMD2<Float>], visible: [Bool])], time: Float, dt: Float) {
        var unmatched = Array(detections.indices)
        var assignments: [(trackedIndex: Int, detectionIndex: Int)] = []

        // Greedy: repeatedly take the closest (tracked, detection) pair.
        var candidates: [(distance: Float, t: Int, d: Int)] = []
        for (t, person) in tracked.enumerated() {
            let pc = Self.centroid(person.joints, person.visible)
            for d in detections.indices {
                let dc = Self.centroid(detections[d].joints, detections[d].visible)
                candidates.append((simd_distance(pc, dc), t, d))
            }
        }
        candidates.sort { $0.distance < $1.distance }
        var usedTracked = Set<Int>()
        for candidate in candidates where candidate.distance <= maxJump {
            guard !usedTracked.contains(candidate.t), unmatched.contains(candidate.d) else { continue }
            usedTracked.insert(candidate.t)
            unmatched.removeAll { $0 == candidate.d }
            assignments.append((candidate.t, candidate.d))
        }

        let alpha: Float = smoothing <= 0 ? 1 : min(1, dt / smoothing)
        for (t, d) in assignments {
            var person = tracked[t]
            let target = detections[d]
            var speedSum: Float = 0
            var speedCount: Float = 0
            for j in 0..<person.joints.count {
                if target.visible[j] {
                    let previous = person.joints[j]
                    let next = person.visible[j] ? previous + (target.joints[j] - previous) * alpha : target.joints[j]
                    let velocity = dt > 0 ? (next - previous) / dt : .zero
                    person.velocities[j] = person.visible[j] ? velocity : .zero
                    person.joints[j] = next
                    person.visible[j] = true
                    speedSum += simd_length(person.velocities[j])
                    speedCount += 1
                } else {
                    person.visible[j] = false
                    person.velocities[j] = .zero
                }
            }
            let instantSpeed = speedCount > 0 ? speedSum / speedCount : 0
            person.speed += (instantSpeed - person.speed) * min(1, dt / 0.3)
            person.lastSeen = time
            person.missing = false
            tracked[t] = person
        }

        for d in unmatched {
            let detection = detections[d]
            tracked.append(Tracked(
                id: nextID, joints: detection.joints, visible: detection.visible,
                velocities: Array(repeating: .zero, count: detection.joints.count),
                speed: 0, firstSeen: time, lastSeen: time, missing: false
            ))
            nextID += 1
        }

        for t in tracked.indices where !usedTracked.contains(t) && tracked[t].lastSeen < time {
            tracked[t].missing = true
            tracked[t].velocities = Array(repeating: .zero, count: tracked[t].velocities.count)
        }
        tracked.removeAll { time - $0.lastSeen > grace }
    }

    mutating func reset() {
        tracked = []
    }

    static func centroid(_ joints: [SIMD2<Float>], _ visible: [Bool]) -> SIMD2<Float> {
        var sum = SIMD2<Float>.zero
        var n: Float = 0
        for (j, v) in zip(joints, visible) where v {
            sum += j
            n += 1
        }
        return n > 0 ? sum / n : SIMD2<Float>(0.5, 0.5)
    }
}
