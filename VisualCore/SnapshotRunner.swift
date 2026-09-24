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
        let face = SceneFace(centre: nose, size: SIMD2<Float>(0.14, 0.1), yawDegrees: 12, pitchDegrees: -4, rollDegrees: 2, mouthOpenness: 0.4, landmarks: [], personID: 0)
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
