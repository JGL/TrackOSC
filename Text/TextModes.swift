//
//  TextModes.swift
//  TrackOSC Text
//

import Foundation

enum TextModes {
    static func mode(_ id: TextBehaviour, _ name: String, _ blurb: String, size: Float, speed: Float = 1, density: Float = 200,
                     trails: Float = 0, extraName: String, extraRange: ClosedRange<Float>, extra: Float) -> VisualMode {
        VisualMode(id: id.rawValue, name: name, blurb: blurb, fragment: "vc_fade", usesFeedback: true, parameters: [
            ParameterSpec("size", "Letter size", 12...200, default: size, unit: " px"),
            ParameterSpec("speed", "Speed", 0.1...4, default: speed, unit: "×"),
            ParameterSpec("density", "Letters", 10...2000, default: density),
            ParameterSpec("trails", "Trails", 0...0.95, default: trails),
            ParameterSpec("extra", extraName, extraRange, default: extra),
        ])
    }

    static let all: [VisualMode] = [
        mode(.physicsLetters, "Physics Letters", "Letters fall, pile up and get knocked about by the body.", size: 44, density: 150, extraName: "Bounce", extraRange: 0.2...3, extra: 1),
        mode(.alongSkeleton, "Along Skeleton", "Words run along arms, spines and legs.", size: 40, extraName: "Spacing", extraRange: 0.5...2, extra: 1),
        mode(.alongContour, "Along Contour", "Words trace detected outlines – or a jaw, or a body.", size: 32, extraName: "Spacing", extraRange: 0.5...2, extra: 1),
        mode(.wordCloud, "Word Cloud", "Whole words drift around each person.", size: 36, extraName: "Radius", extraRange: 0.3...3, extra: 1),
        mode(.orbit, "Orbit", "Letters circle every joint.", size: 28, density: 200, trails: 0.6, extraName: "Radius", extraRange: 0.3...3, extra: 1),
        mode(.scatter, "Scatter", "A resting sentence that fast movements scatter.", size: 40, density: 120, trails: 0.5, extraName: "Kick", extraRange: 0.2...3, extra: 1),
        mode(.typewriter, "Typewriter", "Recognised text is typed out where it was read.", size: 40, extraName: "Unused", extraRange: 0...1, extra: 0),
        mode(.marquee, "Marquee", "Words scroll past at the height of each head.", size: 72, extraName: "Lines", extraRange: 1...4, extra: 2),
        mode(.boxLabels, "Box Labels", "Text and codes drawn where they were seen.", size: 36, extraName: "Unused", extraRange: 0...1, extra: 0),
        mode(.letterRain, "Letter Rain", "Letters fall and break over the body.", size: 36, density: 250, trails: 0.5, extraName: "Sway", extraRange: 0...3, extra: 1),
    ]
}
