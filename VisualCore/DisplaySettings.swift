//
//  DisplaySettings.swift
//  TrackOSC (VisualCore)
//
//  How the scene meets the screen: mirroring, fit or fill, smoothing,
//  render scale, the attract delay, auto-shuffle, and the post pass.
//

import Foundation
import Observation

enum FitMode: String, CaseIterable, Identifiable, Sendable {
    case fit, fill
    var id: String { rawValue }
    var label: String { self == .fit ? "Fit (letterbox)" : "Fill (crop)" }
}

@Observable @MainActor
final class DisplaySettings {
    /// Selfie-style: the person's left appears on the viewer's left.
    var mirror: Bool { didSet { defaults.set(mirror, forKey: "mirror") } }
    var fitMode: FitMode { didSet { defaults.set(fitMode.rawValue, forKey: "fitMode") } }
    /// One-pole smoothing time constant, seconds.
    var smoothing: Float { didSet { defaults.set(smoothing, forKey: "smoothing") } }
    /// 0.5 … 1 of the display's pixel size.
    var renderScale: Float { didSet { defaults.set(renderScale, forKey: "renderScale") } }
    /// Seconds idle before the attract scene; 0 disables it.
    var attractDelay: Float { didSet { defaults.set(attractDelay, forKey: "attractDelay") } }
    /// Seconds between automatic mode changes; 0 disables.
    var autoShuffle: Float { didSet { defaults.set(autoShuffle, forKey: "autoShuffle") } }
    var vignette: Float { didSet { defaults.set(vignette, forKey: "vignette") } }
    var grain: Float { didSet { defaults.set(grain, forKey: "grain") } }
    var gamma: Float { didSet { defaults.set(gamma, forKey: "gamma") } }
    var showModeName: Bool { didSet { defaults.set(showModeName, forKey: "showModeName") } }

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        mirror = d.object(forKey: "mirror") as? Bool ?? true
        fitMode = FitMode(rawValue: d.string(forKey: "fitMode") ?? "") ?? .fit
        smoothing = d.object(forKey: "smoothing") as? Float ?? 0.08
        renderScale = d.object(forKey: "renderScale") as? Float ?? 1
        attractDelay = d.object(forKey: "attractDelay") as? Float ?? 20
        autoShuffle = d.object(forKey: "autoShuffle") as? Float ?? 0
        vignette = d.object(forKey: "vignette") as? Float ?? 0.25
        grain = d.object(forKey: "grain") as? Float ?? 0.03
        gamma = d.object(forKey: "gamma") as? Float ?? 1
        showModeName = d.object(forKey: "showModeName") as? Bool ?? true
    }
}
