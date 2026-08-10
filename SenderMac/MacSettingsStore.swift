//
//  MacSettingsStore.swift
//  Poseiosc Sender (macOS)
//
//  Destination, detector, camera, and display settings, persisted in
//  UserDefaults. Mirrors the iOS SettingsStore, with a selectable camera and
//  a fixed rotation instead of the iOS orientation lock.
//

import Foundation
import Observation

@Observable @MainActor
final class MacSettingsStore {
    var host: String { didSet { defaults.set(host, forKey: "oscHost") } }
    var port: UInt16 { didSet { defaults.set(Int(port), forKey: "oscPort") } }

    var detectPoses: Bool { didSet { defaults.set(detectPoses, forKey: "detectPoses") } }
    var detectHands: Bool { didSet { defaults.set(detectHands, forKey: "detectHands") } }
    var detectFaces: Bool { didSet { defaults.set(detectFaces, forKey: "detectFaces") } }
    var detectTexts: Bool { didSet { defaults.set(detectTexts, forKey: "detectTexts") } }
    var detectAnimals: Bool { didSet { defaults.set(detectAnimals, forKey: "detectAnimals") } }

    /// Selected camera's AVCaptureDevice.uniqueID (nil = system default).
    var cameraID: String? { didSet { defaults.set(cameraID, forKey: "cameraID") } }

    /// Physical rotation of the camera rig: 0, 90, 180, or 270 degrees.
    var rotationDegrees: Int { didSet { defaults.set(rotationDegrees, forKey: "rotationDegrees") } }

    /// Mirrors the on-screen preview (display-only; wire data is unmirrored).
    var mirrorPreview: Bool { didSet { defaults.set(mirrorPreview, forKey: "mirrorPreview") } }

    /// Hides the camera video, showing only the tracking overlay on black.
    /// Display-only: the camera and OSC output keep running.
    var hideVideoPreview: Bool { didSet { defaults.set(hideVideoPreview, forKey: "hideVideoPreview") } }

    private let defaults = UserDefaults.standard

    init() {
        let defaults = UserDefaults.standard
        host = defaults.string(forKey: "oscHost") ?? ""
        let storedPort = defaults.integer(forKey: "oscPort")
        port = (1...65535).contains(storedPort) ? UInt16(storedPort) : 9527

        func bool(_ key: String, default defaultValue: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
        }
        detectPoses = bool("detectPoses", default: true)
        detectHands = bool("detectHands", default: true)
        detectFaces = bool("detectFaces", default: true)
        detectTexts = bool("detectTexts", default: false)
        detectAnimals = bool("detectAnimals", default: false)
        mirrorPreview = bool("mirrorPreview", default: true)
        hideVideoPreview = bool("hideVideoPreview", default: false)

        cameraID = defaults.string(forKey: "cameraID")
        let storedRotation = defaults.integer(forKey: "rotationDegrees")
        rotationDegrees = [0, 90, 180, 270].contains(storedRotation) ? storedRotation : 0
    }

    var detectorConfig: DetectorConfig {
        DetectorConfig(
            poses: detectPoses,
            hands: detectHands,
            faces: detectFaces,
            texts: detectTexts,
            animals: detectAnimals
        )
    }
}
