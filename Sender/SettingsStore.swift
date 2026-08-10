//
//  SettingsStore.swift
//  Poseiosc Sender (iOS)
//
//  Destination + detector settings, persisted in UserDefaults.
//

import Foundation
import Observation

@Observable @MainActor
final class SettingsStore {
    var host: String { didSet { defaults.set(host, forKey: "oscHost") } }
    var port: UInt16 { didSet { defaults.set(Int(port), forKey: "oscPort") } }

    var detectPoses: Bool { didSet { defaults.set(detectPoses, forKey: "detectPoses") } }
    var detectHands: Bool { didSet { defaults.set(detectHands, forKey: "detectHands") } }
    var detectFaces: Bool { didSet { defaults.set(detectFaces, forKey: "detectFaces") } }
    var detectTexts: Bool { didSet { defaults.set(detectTexts, forKey: "detectTexts") } }
    var detectAnimals: Bool { didSet { defaults.set(detectAnimals, forKey: "detectAnimals") } }

    var useFrontCamera: Bool { didSet { defaults.set(useFrontCamera, forKey: "useFrontCamera") } }

    /// Mirrors the on-screen preview and overlay in selfie mode so it feels
    /// like a mirror. Display-only: OSC coordinates are always unmirrored.
    var mirrorFrontPreview: Bool { didSet { defaults.set(mirrorFrontPreview, forKey: "mirrorFrontPreview") } }

    /// Hides the camera video, showing only the tracking overlay on black.
    /// Display-only: the camera and OSC output keep running.
    var hideVideoPreview: Bool { didSet { defaults.set(hideVideoPreview, forKey: "hideVideoPreview") } }

    var cameraOrientation: CameraOrientationSetting {
        didSet { defaults.set(cameraOrientation.rawValue, forKey: "cameraOrientation") }
    }

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
        useFrontCamera = bool("useFrontCamera", default: true)
        mirrorFrontPreview = bool("mirrorFrontPreview", default: true)
        hideVideoPreview = bool("hideVideoPreview", default: false)
        let storedOrientation = defaults.object(forKey: "cameraOrientation") as? Int
        cameraOrientation = storedOrientation.flatMap(CameraOrientationSetting.init(rawValue:)) ?? .auto
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
