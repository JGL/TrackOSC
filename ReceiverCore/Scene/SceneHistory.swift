//
//  SceneHistory.swift
//  TrackOSC (ReceiverCore)
//
//  The last ten seconds of joint positions per person, in a ring buffer
//  sampled by time – trails, ghosts and long exposures read from here.
//

import Foundation
import simd

struct SceneHistory: Sendable {
    struct Sample: Sendable {
        var time: Float
        var joints: [Int: [SIMD2<Float>]]   // person id → 17 joints
        var visible: [Int: [Bool]]
    }

    var span: Float = 10
    private(set) var samples: [Sample] = []

    mutating func record(_ scene: TrackingScene) {
        var joints: [Int: [SIMD2<Float>]] = [:]
        var visible: [Int: [Bool]] = [:]
        for person in scene.persons where person.confidence > 0 {
            joints[person.id] = person.joints
            visible[person.id] = person.visible
        }
        samples.append(Sample(time: scene.time, joints: joints, visible: visible))
        let cutoff = scene.time - span
        if let first = samples.first, first.time < cutoff {
            samples.removeAll { $0.time < cutoff }
        }
    }

    /// The sample nearest to `secondsAgo` before the latest one.
    func sample(secondsAgo: Float) -> Sample? {
        guard let latest = samples.last else { return nil }
        let target = latest.time - secondsAgo
        var low = 0, high = samples.count - 1
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].time < target { low = mid + 1 } else { high = mid }
        }
        return samples[low]
    }

    /// Every sample of one person's joint, oldest first, within the last `seconds`.
    func trail(personID: Int, joint: Int, seconds: Float) -> [SIMD2<Float>] {
        guard let latest = samples.last else { return [] }
        return samples.compactMap { sample in
            guard sample.time >= latest.time - seconds, let joints = sample.joints[personID],
                  joint < joints.count, sample.visible[personID]?[joint] == true else { return nil }
            return joints[joint]
        }
    }
}
