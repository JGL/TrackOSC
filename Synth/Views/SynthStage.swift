//
//  SynthStage.swift
//  TrackOSC Synth (macOS)
//
//  What an audience sees: a dark stage with the sixteen steps as a ring
//  of lights, the level as a glowing core, drum hits as flashes round the
//  ring and the tracked figure faintly behind, so a passer-by can tell
//  that they are playing it.
//

import SwiftUI
import SynthCore
import PoseioscShared

struct SynthStage: View {
    @Bindable var store: SynthStore

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, now: timeline.date)
            }
        }
        .background(store.model.settings.stageBackground)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, now: Date) {
        let accent = Color.accentColor
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.32

        // Figure behind, faint.
        drawScene(in: &context, size: size)

        // Level core.
        let level = CGFloat(min(1, store.peak))
        let core = radius * (0.25 + 0.45 * level)
        let glow = Path(ellipseIn: CGRect(x: centre.x - core, y: centre.y - core, width: core * 2, height: core * 2))
        context.fill(glow, with: .radialGradient(Gradient(colors: [accent.opacity(0.9), accent.opacity(0.0)]), center: centre, startRadius: 0, endRadius: core))

        // Step ring.
        for s in 0..<StepPattern.steps {
            let angle = Double(s) / Double(StepPattern.steps) * 2 * .pi - .pi / 2
            let p = CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
            let isCurrent = s == store.step
            let pattern = store.patterns[store.patternIndex]
            let hasBass = pattern.bass[s].gate
            let hasKick = pattern.drum(.kick, at: s) > 0
            let dot = isCurrent ? 14.0 : (hasKick ? 9.0 : 6.0)
            let colour: Color = isCurrent ? .white : (hasBass ? .orange.opacity(0.9) : (hasKick ? accent : Color.white.opacity(s % 4 == 0 ? 0.5 : 0.25)))
            context.fill(Path(ellipseIn: CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot)), with: .color(colour))
        }

        // Drum flashes: a short arc per voice, outside the ring.
        for (index, kind) in DrumVoiceKind.allCases.enumerated() {
            guard let at = store.lastDrumHits[kind] else { continue }
            let age = now.timeIntervalSince(at)
            guard age < 0.25 else { continue }
            let alpha = 1 - age / 0.25
            let start = Angle(degrees: Double(index) / Double(DrumVoiceKind.allCases.count) * 360 - 90)
            let end = Angle(degrees: Double(index + 1) / Double(DrumVoiceKind.allCases.count) * 360 - 94)
            var arc = Path()
            arc.addArc(center: centre, radius: radius * 1.25, startAngle: start, endAngle: end, clockwise: false)
            context.stroke(arc, with: .color(accent.opacity(alpha)), style: StrokeStyle(lineWidth: 6 + 10 * alpha, lineCap: .round))
        }

        // Bass note in the centre.
        if let note = store.lastBassNote, store.host.meters.isBassActive {
            let text = Text(String.noteName(note)).font(.system(size: radius * 0.35, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
            context.draw(text, at: centre)
        }

        // Not playing: a hint.
        if !store.isPlaying && !store.conductorMode {
            let text = Text("Press Space or raise a hand").font(.system(size: 14, design: .rounded)).foregroundStyle(.white.opacity(0.4))
            context.draw(text, at: CGPoint(x: centre.x, y: centre.y + radius * 1.45))
        }
    }

    private func drawScene(in context: inout GraphicsContext, size: CGSize) {
        let scene = store.scene
        guard scene.isLive else { return }
        let aspect = CGFloat(max(scene.frameAspect, 0.1))
        // Fit the frame in the stage.
        var w = size.width, h = w / aspect
        if h > size.height { h = size.height; w = h * aspect }
        let ox = (size.width - w) / 2, oy = (size.height - h) / 2
        func pt(_ p: ScenePoint) -> CGPoint { CGPoint(x: ox + CGFloat(p.x) * w, y: oy + CGFloat(p.y) * h) }
        let stroke = Color.white.opacity(0.18)
        for person in scene.persons {
            var path = Path()
            for (a, b) in Skeleton.body17Edges where a >= 5 && b >= 5 && person.visible[a] && person.visible[b] {
                path.move(to: pt(person.joints[a]))
                path.addLine(to: pt(person.joints[b]))
            }
            context.stroke(path, with: .color(stroke), lineWidth: 3)
            for outline in person.headOutlines(aspect: Float(aspect)) where outline.count > 1 {
                var head = Path()
                head.move(to: pt(outline[0]))
                for p in outline.dropFirst() { head.addLine(to: pt(p)) }
                context.stroke(head, with: .color(stroke), lineWidth: 2)
            }
        }
        for hand in scene.hands {
            var path = Path()
            for (a, b) in Skeleton.hand21Edges where hand.visible[a] && hand.visible[b] {
                path.move(to: pt(hand.joints[a]))
                path.addLine(to: pt(hand.joints[b]))
            }
            context.stroke(path, with: .color(stroke), lineWidth: 1.5)
        }
    }
}
