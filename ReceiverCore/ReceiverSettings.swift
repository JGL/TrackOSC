//
//  ReceiverSettings.swift
//  TrackOSC (ReceiverCore)
//
//  Connection and presentation settings shared by every receiver-type app,
//  persisted in UserDefaults (each app has its own defaults domain, so the
//  keys need no prefix).
//

import Foundation
import Observation

@Observable @MainActor
final class ReceiverSettings {
    /// The port the user asked for. `nil` means "the default, and fall
    /// forward to the next free port if it is taken".
    var customPort: UInt16? {
        didSet {
            if let customPort { defaults.set(Int(customPort), forKey: "listenPort") }
            else { defaults.removeObject(forKey: "listenPort") }
        }
    }

    var forwardEnabled: Bool { didSet { defaults.set(forwardEnabled, forKey: "forwardEnabled") } }
    var forwardHost: String { didSet { defaults.set(forwardHost, forKey: "forwardHost") } }
    var forwardPort: UInt16 { didSet { defaults.set(Int(forwardPort), forKey: "forwardPort") } }

    /// Launch straight into presentation mode (full screen, controls hidden).
    var startInPresentation: Bool { didSet { defaults.set(startInPresentation, forKey: "startInPresentation") } }
    /// Seconds without mouse movement before the cursor and hint hide in presentation.
    var cursorHideDelay: Double { didSet { defaults.set(cursorHideDelay, forKey: "cursorHideDelay") } }
    var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: "alwaysOnTop") } }

    private let defaults = UserDefaults.standard

    init() {
        let defaults = UserDefaults.standard
        // v1.4 stored the default port as an explicit choice; treat that as
        // "no custom port" so fall-forward applies.
        let storedPort = defaults.integer(forKey: "listenPort")
        let isCustom = (1...65535).contains(storedPort) && UInt16(storedPort) != TrackOSCApp.defaultPort
        customPort = isCustom ? UInt16(storedPort) : nil
        if !isCustom { defaults.removeObject(forKey: "listenPort") }
        forwardEnabled = defaults.bool(forKey: "forwardEnabled")
        forwardHost = defaults.string(forKey: "forwardHost") ?? "127.0.0.1"
        let storedForward = defaults.integer(forKey: "forwardPort")
        forwardPort = (1...65535).contains(storedForward) ? UInt16(storedForward) : 9528
        startInPresentation = defaults.bool(forKey: "startInPresentation")
        let storedDelay = defaults.double(forKey: "cursorHideDelay")
        cursorHideDelay = storedDelay > 0 ? storedDelay : 2
        alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
    }
}
