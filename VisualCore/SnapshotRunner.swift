//
//  SnapshotRunner.swift
//  TrackOSC (VisualCore)
//
//  Renders every mode once, offscreen, with the attract figure, and writes
//  a PNG per mode – so a build can be checked without a window or a camera.
//

import AppKit
import Foundation

enum SnapshotRunner {
    /// A side-on quadruped in JointOrder.animal25, facing left.
    static func syntheticAnimal(at origin: SIMD2<Float>, aspect: Float) -> SceneAnimal {
        func p(_ x: Float, _ y: Float) -> SIMD2<Float> { origin + SIMD2<Float>(x * 0.35 / aspect * 0.5, y * 0.12) }
        let joints: [SIMD2<Float>] = [
            p(-0.50, -0.20),                                     // nose
            p(-0.44, -0.30), p(-0.36, -0.30),                    // eyes
            p(-0.46, -0.48), p(-0.42, -0.42), p(-0.40, -0.36),   // left ear
            p(-0.30, -0.48), p(-0.32, -0.42), p(-0.34, -0.36),   // right ear
            p(-0.25, -0.10),                                     // neck
            p(-0.22, 0.20), p(-0.22, 0.50), p(-0.24, 0.80),      // left front leg
            p(-0.12, 0.20), p(-0.12, 0.50), p(-0.14, 0.80),      // right front leg
            p(0.30, 0.20), p(0.32, 0.50), p(0.34, 0.80),         // left back leg
            p(0.40, 0.20), p(0.42, 0.50), p(0.44, 0.80),         // right back leg
            p(0.35, -0.05), p(0.50, -0.25), p(0.60, -0.50),      // tail
        ]
        return SceneAnimal(id: 1, joints: joints, visible: Array(repeating: true, count: 25),
                           velocities: Array(repeating: .zero, count: 25), centroid: p(0.05, 0.1),
                           age: 3, confidence: 1, speed: 0.1)
    }

    /// 76 points in the FaceLandmarks layout, drawn as simple shapes around a nose.
    static func syntheticLandmarks(around nose: SIMD2<Float>, aspect: Float) -> [SIMD2<Float>] {
        func ring(_ centre: SIMD2<Float>, _ rx: Float, _ ry: Float, _ count: Int, from: Float = 0, to: Float = 2 * .pi) -> [SIMD2<Float>] {
            (0..<count).map { i in
                let a = from + (to - from) * Float(i) / Float(max(count - 1, 1))
                return centre + SIMD2<Float>(cosf(a) * rx / aspect, sinf(a) * ry)
            }
        }
        let ex: Float = 0.018, ey: Float = -0.02
        var points: [SIMD2<Float>] = []
        points += ring(nose + SIMD2(-ex, ey), 0.008, 0.005, 6)                       // left eye 0–5
        points.append(nose + SIMD2(-ex, ey))                                          // left pupil 6
        points += ring(nose + SIMD2(ex, ey), 0.008, 0.005, 6)                        // right eye 7–12
        points.append(nose + SIMD2(ex, ey))                                           // right pupil 13
        points += ring(nose + SIMD2(-ex, ey - 0.012), 0.012, 0.006, 6, from: .pi, to: 2 * .pi)   // left brow 14–19
        points += ring(nose + SIMD2(ex, ey - 0.012), 0.012, 0.006, 6, from: .pi, to: 2 * .pi)    // right brow 20–25
        points += ring(nose + SIMD2(0, 0.03), 0.018, 0.009, 14)                      // outer lips 26–39
        points += ring(nose + SIMD2(0, 0.03), 0.011, 0.004, 6)                       // inner lips 40–45
        points += ring(nose + SIMD2(0, 0.008), 0.012, 0.006, 8, from: 0, to: .pi)   // nose 46–53
        points += (0..<5).map { i in nose + SIMD2(0, -0.02 + Float(i) * 0.007) }      // nose crest 54–58
        points += ring(nose + SIMD2(0, -0.005), 0.045, 0.055, 17, from: 0.15 * .pi, to: 0.85 * .pi) // jaw 59–75
        return points
    }

    @MainActor
    static func run(store: VisualStore, folder: URL, width: Int = 1280, height: Int = 720) -> Bool {
        guard let renderer = store.renderer else {
            FileHandle.standardError.write(Data("No Metal device\n".utf8))
            return false
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let missing = store.modes.map(\.fragment).filter { !renderer.availableFragments.contains($0) }
        if !missing.isEmpty {
            FileHandle.standardError.write(Data("Missing shaders: \(missing.joined(separator: ", "))\n".utf8))
            return false
        }
        var scene = AttractScene().scene(at: 7.3, dt: 1 / 60, aspect: 9.0 / 16.0)
        // A hand and a face on the figure so hand and face modes have something to show.
        let wrist = scene.persons[0].joints[10]
        let handJoints = (0..<21).map { i -> SIMD2<Float> in
            let finger = Float((i - 1) / 4), knuckle = Float((i - 1) % 4 + 1)
            return i == 0 ? wrist : wrist + SIMD2<Float>((finger - 2) * 0.012, -0.018 * knuckle)
        }
        let hand = SceneHand(joints: handJoints, visible: Array(repeating: true, count: 21), centre: wrist + SIMD2<Float>(0, -0.03), openness: 0.9, isLeft: false, personID: 0)
        scene.hands = [hand]
        scene.persons[0].hands = [hand]
        let nose = scene.persons[0].joints[0]
        let face = SceneFace(centre: nose, size: SIMD2<Float>(0.14, 0.1), yawDegrees: 12, pitchDegrees: -4, rollDegrees: 2, mouthOpenness: 0.4,
                             landmarks: Self.syntheticLandmarks(around: nose, aspect: 9.0 / 16.0), personID: 0)
        scene.faces = [face]
        scene.persons[0].face = face
        scene.animals = [Self.syntheticAnimal(at: SIMD2<Float>(0.68, 0.8), aspect: 9.0 / 16.0)]
        scene.texts = [
            SceneText(text: "HELLO", centre: SIMD2<Float>(0.3, 0.62), size: SIMD2<Float>(0.3, 0.05), isCode: false),
            SceneText(text: "https://github.com/JGL/TrackOSC", centre: SIMD2<Float>(0.6, 0.5), size: SIMD2<Float>(0.25, 0.25), isCode: true),
        ]
        scene.isAttract = false
        scene.presence = 1
        scene.activity = 0.4

        var ok = true
        for mode in store.modes {
            // Sprite apps step a simulation per call; give them time to settle.
            let warmup = store.overlayProvider != nil ? 90 : (mode.usesFeedback ? 30 : 0)
            for _ in 0..<warmup {
                _ = renderer.snapshot(scene: scene, inputs: store.currentInputs(for: mode, scene: scene, dt: 1 / 60), width: width, height: height)
            }
            let inputs = store.currentInputs(for: mode, scene: scene, dt: 1 / 60)
            guard let image = renderer.snapshot(scene: scene, inputs: inputs, width: width, height: height, warmupFrames: 0) else {
                FileHandle.standardError.write(Data("Render failed: \(mode.id) \(renderer.lastError ?? "")\n".utf8))
                ok = false
                continue
            }
            let rep = NSBitmapImageRep(cgImage: image)
            let url = folder.appendingPathComponent("\(mode.id).png")
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                print("wrote \(url.path)")
            }
        }
        if let error = renderer.lastError {
            FileHandle.standardError.write(Data("Renderer error: \(error)\n".utf8))
            ok = false
        }
        return ok
    }
}
