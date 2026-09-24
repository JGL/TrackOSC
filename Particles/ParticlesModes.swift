//
//  ParticlesModes.swift
//  TrackOSC Particles
//
//  The mode catalogue. Every mode draws sprites over the vc_fade
//  background (trails = the previous frame kept, per the Trails parameter).
//

import Foundation

enum ParticlesModes {
    static func mode(_ id: ParticleBehaviour, _ name: String, _ blurb: String, count: Float, size: Float, speed: Float = 1,
                     trails: Float, extraName: String, extraRange: ClosedRange<Float>, extra: Float) -> VisualMode {
        VisualMode(id: id.rawValue, name: name, blurb: blurb, fragment: "vc_fade", usesFeedback: true, parameters: [
            ParameterSpec("count", "Particles", 200...100_000, default: count),
            ParameterSpec("size", "Size", 1...40, default: size, unit: " px"),
            ParameterSpec("speed", "Speed", 0.1...4, default: speed, unit: "×"),
            ParameterSpec("trails", "Trails", 0...0.98, default: trails),
            ParameterSpec("extra", extraName, extraRange, default: extra),
        ])
    }

    static let all: [VisualMode] = [
        mode(.attract, "Attract", "Every particle races for the nearest joint.", count: 8000, size: 5, trails: 0.85, extraName: "Pull", extraRange: 0.2...4, extra: 1),
        mode(.repel, "Repel", "A field of particles parts around the body.", count: 12000, size: 4, trails: 0.6, extraName: "Reach", extraRange: 0.3...3, extra: 1),
        mode(.orbit, "Orbit", "Particles circle each person like moons.", count: 6000, size: 5, trails: 0.9, extraName: "Radius", extraRange: 0.3...3, extra: 1),
        mode(.sparks, "Sparks", "Fast joints throw sparks that fall.", count: 20000, size: 5, trails: 0.9, extraName: "Gravity", extraRange: 0...3, extra: 1),
        mode(.skeletonFire, "Skeleton Fire", "Bones burn; flames rise and cool.", count: 15000, size: 9, trails: 0.8, extraName: "Rise", extraRange: 0.2...3, extra: 1),
        mode(.ghostParade, "Ghost Parade", "Where each person was, half a second ago, and before that.", count: 15000, size: 4, trails: 0.5, extraName: "Spacing", extraRange: 0.3...3, extra: 1),
        mode(.longExposure, "Long Exposure", "Joints leave light that lingers.", count: 30000, size: 6, trails: 0.97, extraName: "Hold", extraRange: 0.2...3, extra: 1),
        mode(.flowField, "Flow Field", "A slow current that moving joints stir.", count: 15000, size: 3, trails: 0.92, extraName: "Scale", extraRange: 0.3...3, extra: 1),
        mode(.constellation, "Constellation", "Stars, and the lines that make a figure of them.", count: 400, size: 4, speed: 1, trails: 0.5, extraName: "Reach", extraRange: 0.3...3, extra: 1),
        mode(.rainSnow, "Rain / Snow", "Falling drops that break on the body; turn it up for snow.", count: 6000, size: 4, trails: 0.7, extraName: "Snow", extraRange: 0...2, extra: 0.3),
        mode(.particleBody, "Particle Body", "The body itself, made of dust.", count: 25000, size: 4, trails: 0.75, extraName: "Jitter", extraRange: 0.2...3, extra: 1),
        mode(.handFountains, "Hand Fountains", "Hands throw fountains; open them to spread.", count: 20000, size: 5, trails: 0.85, extraName: "Spread", extraRange: 0.2...3, extra: 1),
    ]
}
