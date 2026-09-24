//
//  ReceiverSettings.swift
//  TrackOSC (ReceiverCore)
//
//  Connection, source and full-screen settings shared by every receiver-type app,
//  persisted in UserDefaults (each app has its own defaults domain, so the
//  keys need no prefix).
//

import AppKit
import Foundation
import Observation
import SwiftUI

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

    /// Which sender is heard when several send to this port.
    var sourcePolicy: SourcePolicy { didSet { defaults.set(sourcePolicy.rawValue, forKey: "sourcePolicy") } }
    var sourceHost: String { didSet { defaults.set(sourceHost, forKey: "sourceHost") } }

    /// The stage's fill, and the window's background in full screen.
    var stageBackground: Color {
        didSet {
            let rgb = NSColor(stageBackground).usingColorSpace(.sRGB) ?? .black
            defaults.set([rgb.redComponent, rgb.greenComponent, rgb.blueComponent], forKey: "stageBackground")
        }
    }

    /// Launch straight into full screen (controls hidden).
    var startInFullScreen: Bool { didSet { defaults.set(startInFullScreen, forKey: "startInFullScreen") } }
    /// Seconds without mouse movement before the cursor and hint hide in full screen.
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
        sourcePolicy = SourcePolicy(rawValue: defaults.string(forKey: "sourcePolicy") ?? "") ?? .latestWins
        sourceHost = defaults.string(forKey: "sourceHost") ?? ""
        if let rgb = defaults.array(forKey: "stageBackground") as? [Double], rgb.count == 3 {
            stageBackground = Color(red: rgb[0], green: rgb[1], blue: rgb[2])
        } else {
            stageBackground = .black
        }
        // "startInPresentation" was the v1.5 name. A `--fullscreen` launch
        // argument does the same for one launch without changing the setting.
        startInFullScreen = defaults.bool(forKey: "startInFullScreen") || defaults.bool(forKey: "startInPresentation")
            || CommandLine.arguments.contains("--fullscreen")
        let storedDelay = defaults.double(forKey: "cursorHideDelay")
        cursorHideDelay = storedDelay > 0 ? storedDelay : 2
        alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
    }
}
