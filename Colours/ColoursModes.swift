//
//  ColoursModes.swift
//  TrackOSC Colours
//
//  The mode catalogue. Adding a mode = one fragment function in
//  ColoursModes.metal and one entry here; parameters are read in order
//  from u.params.
//

import Foundation

enum ColoursModes {
    static let all: [VisualMode] = [
        VisualMode(id: "bodyHue", name: "Body Hue", blurb: "Glowing skeletons, one colour per person.",
                   fragment: "colours_body_hue", parameters: [
                    ParameterSpec("thickness", "Thickness", 0.002...0.05, default: 0.012),
                    ParameterSpec("glow", "Glow", 0...3, default: 1),
                    ParameterSpec("background", "Background", 0...2, default: 0.6),
                   ]),
        VisualMode(id: "handGlow", name: "Hand Glow", blurb: "Light pours from every hand; open hands shine wider.",
                   fragment: "colours_hand_glow", parameters: [
                    ParameterSpec("radius", "Radius", 0.02...0.4, default: 0.12),
                    ParameterSpec("intensity", "Intensity", 0.2...3, default: 1.2),
                    ParameterSpec("fingers", "Fingertips", 0...2, default: 0.6),
                   ]),
        VisualMode(id: "jointStops", name: "Joint Stops", blurb: "Every joint is a colour stop of one smooth field.",
                   fragment: "colours_joint_stops", parameters: [
                    ParameterSpec("falloff", "Falloff", 1...20, default: 6),
                    ParameterSpec("spread", "Spread", 0.2...3, default: 1),
                    ParameterSpec("drift", "Drift", 0...3, default: 0.5),
                   ]),
        VisualMode(id: "voronoi", name: "Voronoi People", blurb: "The screen divided between whoever is nearest.",
                   fragment: "colours_voronoi", parameters: [
                    ParameterSpec("edge", "Edge width", 0.001...0.08, default: 0.02),
                    ParameterSpec("darken", "Edge darkness", 0...1, default: 0.8),
                    ParameterSpec("pulse", "Pulse", 0...5, default: 1),
                   ]),
        VisualMode(id: "metaballs", name: "Metaballs", blurb: "Joints as blobs that merge into a coloured field.",
                   fragment: "colours_metaballs", parameters: [
                    ParameterSpec("size", "Blob size", 0.01...0.15, default: 0.05),
                    ParameterSpec("threshold", "Threshold", 0.2...5, default: 1.5),
                    ParameterSpec("bands", "Bands", 0...10, default: 3),
                   ]),
        VisualMode(id: "rings", name: "Rings", blurb: "Ripples radiate from each person, faster when they move.",
                   fragment: "colours_rings", parameters: [
                    ParameterSpec("spacing", "Spacing", 0.02...0.4, default: 0.1),
                    ParameterSpec("speed", "Speed", 0...4, default: 1),
                    ParameterSpec("width", "Width", 0.05...0.9, default: 0.4),
                   ]),
        VisualMode(id: "stripes", name: "Stripes", blurb: "Bands that turn with the shoulders and breathe with presence.",
                   fragment: "colours_stripes", parameters: [
                    ParameterSpec("count", "Count", 2...40, default: 10),
                    ParameterSpec("softness", "Softness", 0.01...0.5, default: 0.15),
                    ParameterSpec("turn", "Turn", 0...2, default: 1),
                   ]),
        VisualMode(id: "checkers", name: "Checkers", blurb: "A chequerboard warped by whoever stands in it.",
                   fragment: "colours_checkers", parameters: [
                    ParameterSpec("cells", "Cells", 2...40, default: 12),
                    ParameterSpec("warp", "Warp", 0...4, default: 1.5),
                    ParameterSpec("radius", "Radius", 0.05...0.6, default: 0.2),
                   ]),
        VisualMode(id: "memoryWash", name: "Memory Wash", blurb: "The skeleton paints, and the paint fades.",
                   fragment: "colours_memory_wash", usesFeedback: true, parameters: [
                    ParameterSpec("decay", "Persistence", 0.8...0.995, default: 0.96),
                    ParameterSpec("brush", "Brush", 0.005...0.08, default: 0.02),
                    ParameterSpec("hueSpeed", "Hue drift", 0...3, default: 1),
                   ]),
        VisualMode(id: "heatMap", name: "Heat Map", blurb: "Where people have been, slowly cooling.",
                   fragment: "colours_heat_map", usesFeedback: true, parameters: [
                    ParameterSpec("cooling", "Persistence", 0.9...0.9995, default: 0.995),
                    ParameterSpec("warmth", "Warmth", 0.2...5, default: 1),
                    ParameterSpec("spot", "Spot size", 0.01...0.2, default: 0.05),
                   ]),
        VisualMode(id: "kaleido", name: "Kaleido Body", blurb: "The body folded into a kaleidoscope.",
                   fragment: "colours_kaleido", parameters: [
                    ParameterSpec("segments", "Segments", 2...16, default: 6),
                    ParameterSpec("spin", "Spin", 0...3, default: 0.5),
                    ParameterSpec("zoom", "Zoom", 0.5...3, default: 1),
                   ]),
        VisualMode(id: "aurora", name: "Aurora", blurb: "Noise curtains that brighten where hands rise.",
                   fragment: "colours_aurora", parameters: [
                    ParameterSpec("scale", "Scale", 0.5...8, default: 2.5),
                    ParameterSpec("speed", "Speed", 0...3, default: 1),
                    ParameterSpec("lift", "Hand lift", 0...2, default: 0.8),
                   ]),
        VisualMode(id: "faceMood", name: "Face Mood", blurb: "Colour follows where the face looks and how open the mouth is.",
                   fragment: "colours_face_mood", parameters: [
                    ParameterSpec("reach", "Reach", 0.05...0.8, default: 0.25),
                    ParameterSpec("swing", "Swing", 0...2, default: 1),
                    ParameterSpec("brighten", "Mouth brighten", 0...3, default: 1.5),
                   ]),
        VisualMode(id: "paletteSweep", name: "Palette Sweep", blurb: "The palette sweeps across, its phase led by the nose.",
                   fragment: "colours_palette_sweep", parameters: [
                    ParameterSpec("repeats", "Repeats", 0.5...8, default: 1.5),
                    ParameterSpec("speed", "Speed", 0...3, default: 0.5),
                    ParameterSpec("follow", "Follow nose", 0...2, default: 1),
                   ]),
    ]
}
