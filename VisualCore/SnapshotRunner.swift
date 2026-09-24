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
        scene.isAttract = false
        scene.presence = 1
        scene.activity = 0.4

        var ok = true
        for mode in store.modes {
            let inputs = store.currentInputs(for: mode)
            guard let image = renderer.snapshot(scene: scene, inputs: inputs, width: width, height: height, warmupFrames: mode.usesFeedback ? 30 : 0) else {
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
