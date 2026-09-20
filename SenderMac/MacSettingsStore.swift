//
//  MacSettingsStore.swift
//  TrackOSC Sender (macOS)
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

    /// The detectors currently switched on. Persisted one key per detector
    /// (see `Detector.defaultsKey`); the legacy five keep their v1.0 keys.
    var enabledDetectors: Set<Detector> { didSet { Detector.store(enabledDetectors, in: defaults) } }

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
        enabledDetectors = Detector.loadEnabled(from: defaults)
        mirrorPreview = bool("mirrorPreview", default: true)
        hideVideoPreview = bool("hideVideoPreview", default: false)

        cameraID = defaults.string(forKey: "cameraID")
        let storedRotation = defaults.integer(forKey: "rotationDegrees")
        rotationDegrees = [0, 90, 180, 270].contains(storedRotation) ? storedRotation : 0
    }

    func isEnabled(_ detector: Detector) -> Bool {
        enabledDetectors.contains(detector)
    }

    func toggle(_ detector: Detector) {
        if enabledDetectors.contains(detector) {
            enabledDetectors.remove(detector)
        } else {
            enabledDetectors.insert(detector)
        }
    }

    var detectorConfig: DetectorConfig {
        DetectorConfig(enabled: enabledDetectors)
    }
}
