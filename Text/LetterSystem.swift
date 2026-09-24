//
//  LetterSystem.swift
//  TrackOSC Text
//
//  Letters as sprites from the glyph atlas, moved by one of ten
//  behaviours. Positions are scene uv; sizes are pixels.
//

import Foundation
import Metal
import simd

enum TextBehaviour: String, CaseIterable, Sendable {
    case physicsLetters, alongSkeleton, alongContour, wordCloud, orbit, scatter, typewriter, marquee, boxLabels, letterRain
}

@MainActor
final class LetterSystem {
    static let capacity = 4000

    struct Letter {
        var character: Character
        var word: Int
        var position: SIMD2<Float>
        var velocity: SIMD2<Float> = .zero
        var rotation: Float = 0
        var size: Float
        var colourT: Float
        var alpha: Float = 1
        var seed: Float = .random(in: 0...1)
        var anchor: Int = 0
    }

    private var letters: [Letter] = []
    private var behaviour: TextBehaviour?
    private var time: Float = 0
    private var typed: [String: Int] = [:]      // typewriter progress per entry
    private var marqueeOffset: Float = 0
    let buffers: SpriteBuffers
    let pool = TextPool()
    private(set) var atlas: GlyphAtlas?
    private let device: MTLDevice

    init(device: MTLDevice, fontName: String) {
        self.device = device
        buffers = SpriteBuffers(device: device, spriteCapacity: Self.capacity, lineCapacity: 256)
        atlas = GlyphAtlas(device: device, fontName: fontName)
    }

    func setFont(_ name: String) {
        atlas = GlyphAtlas(device: device, fontName: name)
    }

    // MARK: - Step

    var viewport = SceneViewport()
    /// Pixels per scene-uv unit, horizontally and vertically.
    private var pixelsPerUV = SIMD2<Float>(1280, 720)

    /// A glyph's advance at `size` pixels tall, in scene uv (x).
    private func advanceUV(_ character: Character, size: Float) -> Float {
        guard let atlas, let g = atlas.glyph(for: character) else { return size * 0.6 / pixelsPerUV.x }
        return g.advance * (size / Float(atlas.fontSize)) / pixelsPerUV.x
    }

    func step(scene: TrackingScene, behaviour: TextBehaviour, params: ParameterValues, palette: Palette, viewport: SceneViewport, viewSize: SIMD2<Float>, dt rawDt: Float) -> SpriteBatch? {
        guard let atlas else { return nil }
        self.viewport = viewport
        pixelsPerUV = SIMD2(viewSize.x / max(viewport.width, 1e-3), viewSize.y / max(viewport.height, 1e-3))
        let dt = min(max(rawDt, 1 / 240), 1 / 20)
        time += dt
        pool.update(scene: scene)
        let size = params["size"] ?? 48
        let speed = params["speed"] ?? 1
        let density = Int(params["density"] ?? 200)
        let extra = params["extra"] ?? 1
        let aspect = max(scene.frameAspect, 0.1)
        let geometry = SceneGeometryLite(scene: scene)

        if behaviour != self.behaviour {
            letters = []
            self.behaviour = behaviour
            typed = [:]
        }

        switch behaviour {
        case .physicsLetters: stepPhysics(geometry, dt: dt, speed: speed, density: density, aspect: aspect, bounce: extra)
        case .alongSkeleton: layAlongSkeleton(scene, size: size, aspect: aspect, spacing: extra)
        case .alongContour: layAlongContour(scene, size: size, aspect: aspect, spacing: extra)
        case .wordCloud: stepWordCloud(scene, dt: dt, speed: speed, density: density, aspect: aspect, radius: extra)
        case .orbit: stepOrbit(geometry, dt: dt, speed: speed, density: density, aspect: aspect, radius: extra)
        case .scatter: stepScatter(geometry, scene: scene, dt: dt, speed: speed, density: density, aspect: aspect, kick: extra)
        case .typewriter: stepTypewriter(scene, dt: dt, speed: speed, size: size)
        case .marquee: stepMarquee(scene, dt: dt, speed: speed, size: size, aspect: aspect, lines: extra)
        case .boxLabels: layBoxLabels(scene, size: size)
        case .letterRain: stepRain(geometry, dt: dt, speed: speed, density: density, aspect: aspect, sway: extra)
        }
        return write(palette: palette, size: size, atlas: atlas, aspect: aspect)
    }

    // MARK: - Spawning helpers

    private func fill(to count: Int, _ make: (Character, Int, Int) -> Letter) {
        let wanted = min(count, Self.capacity)
        if letters.count > wanted { letters.removeLast(letters.count - wanted) }
        guard letters.count < wanted else { return }
        let source = pool.letters(at: time, limit: wanted)
        guard !source.isEmpty else { return }
        var i = letters.count
        while letters.count < wanted {
            let (character, word) = source[i % source.count]
            letters.append(make(character, word, i))
            i += 1
        }
    }

    // MARK: - Behaviours

    private func stepPhysics(_ g: SceneGeometryLite, dt: Float, speed: Float, density: Int, aspect: Float, bounce: Float) {
        let vp = viewport
        fill(to: density) { c, w, i in
            Letter(character: c, word: w, position: SIMD2(Float.random(in: vp.min.x...vp.max.x), Float.random(in: (vp.min.y - 1) ... (vp.min.y - 0.05))),
                   size: 1, colourT: Float(w) * 0.15 + Float.random(in: 0...0.1))
        }
        for i in letters.indices {
            var l = letters[i]
            l.velocity.y += 0.8 * dt * speed
            if let near = g.nearestBone(to: l.position), near.distance < 0.035 {
                let away = simd_normalize(l.position - near.point + SIMD2(1e-5, 0))
                l.velocity += away * (0.035 - near.distance) * 40 * bounce
                l.rotation += (away.x) * 4 * dt
            }
            // Floor and walls at the screen's edges.
            let floor = vp.max.y - 0.03
            if l.position.y > floor { l.position.y = floor; l.velocity.y = -abs(l.velocity.y) * 0.4 * bounce; l.velocity.x *= 0.9 }
            if l.position.x < vp.min.x + 0.02 { l.position.x = vp.min.x + 0.02; l.velocity.x = abs(l.velocity.x) * 0.5 }
            if l.position.x > vp.max.x - 0.02 { l.position.x = vp.max.x - 0.02; l.velocity.x = -abs(l.velocity.x) * 0.5 }
            l.velocity *= 0.995
            l.position += l.velocity * dt
            l.rotation *= 0.98
            letters[i] = l
        }
        // Letters that settle for good get recycled from the top now and then.
        if let i = letters.indices.randomElement(), letters[i].position.y > vp.max.y - 0.04, abs(letters[i].velocity.y) < 0.01, Float.random(in: 0...1) < 0.02 {
            letters[i].position = SIMD2(Float.random(in: vp.min.x...vp.max.x), vp.min.y - 0.1)
            letters[i].velocity = .zero
        }
    }

    /// The sentence repeated along every path the scene offers: each
    /// person's arm span, spine and legs and their head (face landmarks
    /// when present, otherwise a circle), and each animal's spine, legs,
    /// ears and tail. Letters crawl slowly along the paths.
    private func layAlongSkeleton(_ scene: TrackingScene, size: Float, aspect: Float, spacing: Float) {
        letters = []
        let words = pool.words(at: time)
        guard !words.isEmpty else { return }
        var paths: [(points: [SIMD2<Float>], colourT: Float)] = []
        for (pi, person) in scene.persons.enumerated() where person.confidence > 0 {
            let base = Float(pi) * 0.3
            func joints(_ ids: [Int]) -> [SIMD2<Float>] { ids.filter { person.visible[$0] }.map { person.joints[$0] } }
            paths.append((joints([10, 8, 6, 5, 7, 9]), base))            // right wrist → left wrist over the shoulders
            paths.append((joints([11, 13, 15]), base + 0.15))            // left leg
            paths.append((joints([12, 14, 16]), base + 0.15))            // right leg
            paths.append((joints([5, 11]), base + 0.3))                  // left side of the torso
            paths.append((joints([6, 12]), base + 0.3))                  // right side
            paths.append((joints([11, 12]), base + 0.3))                 // hips
            for outline in person.headOutlines(aspect: scene.frameAspect) { paths.append((outline, base + 0.45)) }
            for hand in person.hands {
                for finger in [[0, 1, 2, 3, 4], [0, 5, 6, 7, 8], [0, 9, 10, 11, 12], [0, 13, 14, 15, 16], [0, 17, 18, 19, 20]] {
                    paths.append((finger.filter { hand.visible[$0] }.map { hand.joints[$0] }, base + 0.6))
                }
            }
        }
        for (ai, animal) in scene.animals.enumerated() where animal.confidence > 0 {
            let base = 0.5 + Float(ai) * 0.2
            func joints(_ ids: [Int]) -> [SIMD2<Float>] { ids.filter { animal.visible[$0] }.map { animal.joints[$0] } }
            paths.append((joints([0, 9, 22, 23, 24]), base))             // nose → neck → tail
            paths.append((joints([9, 10, 11, 12]), base + 0.1))          // left front leg
            paths.append((joints([9, 13, 14, 15]), base + 0.1))          // right front leg
            paths.append((joints([22, 16, 17, 18]), base + 0.2))         // left back leg
            paths.append((joints([22, 19, 20, 21]), base + 0.2))         // right back leg
            paths.append((joints([1, 5, 4, 3]), base + 0.3))             // left ear
            paths.append((joints([2, 8, 7, 6]), base + 0.3))             // right ear
        }
        layRepeating(words, along: paths, size: size, spacing: spacing)
    }

    /// Lays the words, repeated, along each path, letters crawling with time.
    private func layRepeating(_ words: [PoolEntry], along paths: [(points: [SIMD2<Float>], colourT: Float)], size: Float, spacing: Float) {
        let ppu = pixelsPerUV
        let sentence = Array(words.map(\.text).joined(separator: "  ") + "  ")
        guard !sentence.isEmpty else { return }
        let step = size * 0.7 * spacing   // letter advance in pixels
        func screen(_ p: SIMD2<Float>) -> SIMD2<Float> { p * ppu }
        for (pi, path) in paths.enumerated() where path.points.count >= 2 {
            var lengths: [Float] = [0]
            for i in 1..<path.points.count { lengths.append(lengths[i - 1] + simd_distance(screen(path.points[i]), screen(path.points[i - 1]))) }
            let total = lengths.last!
            guard total > step else { continue }
            let crawl = fmodf(time * 20 + Float(pi) * 37, step * Float(sentence.count))
            var s: Float = -crawl
            var ci = 0
            while s < total, letters.count < Self.capacity {
                let character = sentence[ci % sentence.count]
                ci += 1
                defer { s += step }
                if character.isWhitespace || s < 0 { continue }
                var k = 1
                while k < path.points.count - 1, lengths[k] < s { k += 1 }
                let t = (s - lengths[k - 1]) / max(lengths[k] - lengths[k - 1], 1e-5)
                let p = path.points[k - 1] + (path.points[k] - path.points[k - 1]) * t
                let d = screen(path.points[k]) - screen(path.points[k - 1])
                letters.append(Letter(character: character, word: pi, position: p, rotation: atan2(d.y, d.x), size: 1,
                                      colourT: path.colourT + s / max(total, 1) * 0.2))
            }
        }
    }

    /// Words along detected outlines: /contours/arr first, then faces
    /// (landmarks or the box), then the outline of each person and animal.
    private func layAlongContour(_ scene: TrackingScene, size: Float, aspect: Float, spacing: Float) {
        letters = []
        let words = pool.words(at: time)
        guard !words.isEmpty else { return }
        var paths: [(points: [SIMD2<Float>], colourT: Float)] = []
        for (i, contour) in scene.contours.prefix(8).enumerated() { paths.append((contour + [contour[0]], Float(i) * 0.15)) }
        if paths.isEmpty {
            // No outlines from the sender: trace faces, bodies and animals instead.
            for (i, face) in scene.faces.enumerated() {
                if face.landmarks.count >= 76 {
                    paths.append((Array(face.landmarks[59..<76]), Float(i) * 0.2))
                } else {
                    paths.append(((0...24).map { k in
                        let angle = Float(k) / 24 * 2 * .pi
                        return face.centre + SIMD2(cosf(angle) * face.size.x * 0.5, sinf(angle) * face.size.y * 0.5)
                    }, Float(i) * 0.2))
                }
            }
            func box(_ lo: SIMD2<Float>, _ hi: SIMD2<Float>, _ t: Float) {
                let pad = SIMD2<Float>(0.04 / max(aspect, 0.1), 0.04)
                paths.append(([lo - pad, SIMD2(hi.x + pad.x, lo.y - pad.y), hi + pad, SIMD2(lo.x - pad.x, hi.y + pad.y), lo - pad], t))
            }
            for (i, person) in scene.persons.enumerated() where person.confidence > 0 { box(person.boundingBox.min, person.boundingBox.max, 0.3 + Float(i) * 0.3) }
            for (i, animal) in scene.animals.enumerated() where animal.confidence > 0 {
                let visible = zip(animal.joints, animal.visible).filter { $0.1 }.map { $0.0 }
                guard !visible.isEmpty else { continue }
                box(visible.reduce(SIMD2(1, 1)) { simd_min($0, $1) }, visible.reduce(SIMD2(0, 0)) { simd_max($0, $1) }, 0.6 + Float(i) * 0.2)
            }
        }
        layRepeating(words, along: paths, size: size, spacing: spacing)
    }

    private func stepWordCloud(_ scene: TrackingScene, dt: Float, speed: Float, density: Int, aspect: Float, radius: Float) {
        // One "letter" per word here: the word is drawn as a run from its first letter.
        let words = pool.words(at: time)
        let centres = (scene.persons.map(\.centroid) + scene.animals.map(\.centroid))
        let count = min(max(words.count, 1) * max(centres.count, 1), 60)
        if letters.count != count {
            letters = (0..<count).map { i in
                let centre = centres.isEmpty ? SIMD2<Float>(0.5, 0.5) : centres[i % centres.count]
                return Letter(character: " ", word: i % max(words.count, 1), position: centre + SIMD2(Float.random(in: -0.2...0.2), Float.random(in: -0.2...0.2)), size: 1, colourT: Float(i) * 0.13, anchor: centres.isEmpty ? -1 : i % centres.count)
            }
        }
        for i in letters.indices {
            var l = letters[i]
            let centre = centres.isEmpty ? SIMD2<Float>(0.5, 0.5) : centres[min(max(l.anchor, 0), centres.count - 1)]
            let angle = time * 0.2 * speed + l.seed * 6.28
            let r = radius * (0.12 + l.seed * 0.15)
            let target = centre + SIMD2(cosf(angle) * r / aspect, sinf(angle) * r * 0.7)
            l.velocity += (target - l.position) * 4 * dt
            l.velocity *= 0.9
            l.position += l.velocity * dt
            l.word = i % max(words.count, 1)
            letters[i] = l
        }
    }

    private func stepOrbit(_ g: SceneGeometryLite, dt: Float, speed: Float, density: Int, aspect: Float, radius: Float) {
        fill(to: density) { c, w, i in
            Letter(character: c, word: w, position: SIMD2(Float.random(in: 0...1), Float.random(in: 0...1)), size: 1, colourT: Float(w) * 0.15 + Float(i % 7) * 0.02)
        }
        let anchors = g.anchors.isEmpty ? [SIMD2<Float>(0.5, 0.5)] : g.anchors
        for i in letters.indices {
            var l = letters[i]
            let a = anchors[i % anchors.count]
            let angle = time * (0.6 + l.seed) * speed + l.seed * 6.28
            let r = radius * 0.05 * (1 + l.seed)
            let target = a + SIMD2(cosf(angle) * r / aspect, sinf(angle) * r)
            l.velocity += (target - l.position) * 12 * dt
            l.velocity *= 0.85
            l.position += l.velocity * dt
            l.rotation = angle + .pi / 2
            letters[i] = l
        }
    }

    private func stepScatter(_ g: SceneGeometryLite, scene: TrackingScene, dt: Float, speed: Float, density: Int, aspect: Float, kick: Float) {
        fill(to: density) { c, w, i in
            Letter(character: c, word: w, position: SIMD2(Float.random(in: 0.1...0.9), Float.random(in: 0.1...0.9)), size: 1, colourT: Float(w) * 0.15)
        }
        for i in letters.indices {
            var l = letters[i]
            // Rest on a slow orbit of the centre; fast joints kick letters near them.
            let home = SIMD2<Float>(0.5 + cosf(l.seed * 6.28 + time * 0.05) * 0.3 / aspect, 0.5 + sinf(l.seed * 6.28 + time * 0.05) * 0.3)
            l.velocity += (home - l.position) * 1.5 * dt * speed
            for joint in g.fastJoints {
                let d = simd_distance(joint.position, l.position)
                if d < 0.12 {
                    l.velocity += joint.velocity * (0.12 - d) / 0.12 * 3 * kick
                    l.rotation += Float.random(in: -1...1) * kick
                }
            }
            l.velocity *= 0.94
            l.position += l.velocity * dt
            l.rotation *= 0.97
            letters[i] = l
        }
    }

    private func stepTypewriter(_ scene: TrackingScene, dt: Float, speed: Float, size: Float) {
        letters = []
        let live = pool.entries.filter { $0.source != .user && $0.centre != nil }.sorted { $0.firstSeen < $1.firstSeen }
        for (ei, entry) in live.suffix(6).enumerated() {
            let shown = min(entry.text.count, Int((time - entry.firstSeen) * 12 * speed))
            typed[entry.id] = shown
            guard let centre = entry.centre, let boxSize = entry.size else { continue }
            let chars = Array(entry.text.prefix(shown))
            let advance = advanceUV("M", size: size)
            let start = centre.x - boxSize.x / 2
            let fade = max(0, 1 - max(0, time - entry.lastSeen - 5) / 5)
            for (ci, c) in chars.enumerated() where !c.isWhitespace {
                letters.append(Letter(character: c, word: ei, position: SIMD2(start + Float(ci) * advance, centre.y), size: 1, colourT: 0.2 + Float(ei) * 0.15, alpha: fade))
            }
            // Cursor.
            if shown < entry.text.count, Int(time * 3) % 2 == 0 {
                letters.append(Letter(character: "_", word: ei, position: SIMD2(start + Float(chars.count) * advance, centre.y), size: 1, colourT: 0.9, alpha: fade))
            }
        }
    }

    private func stepMarquee(_ scene: TrackingScene, dt: Float, speed: Float, size: Float, aspect: Float, lines: Float) {
        letters = []
        marqueeOffset -= dt * 0.12 * speed
        let words = pool.words(at: time).map(\.text)
        guard !words.isEmpty else { return }
        let sentence = words.joined(separator: "   ") + "   "
        let chars = Array(sentence)
        let advance = advanceUV("M", size: size) * 0.95
        let total = advance * Float(chars.count)
        var rows: [Float] = scene.persons.filter { $0.confidence > 0 && $0.visible[0] }.map { $0.joints[0].y }
        rows += scene.animals.filter { $0.confidence > 0 && $0.visible[0] }.map { $0.joints[0].y }
        if rows.isEmpty { rows = [0.5] }
        let vp = viewport
        for (ri, row) in rows.prefix(Int(max(lines, 1))).enumerated() {
            var x = fmodf(marqueeOffset + Float(ri) * 0.37, total)
            if x < 0 { x += total }
            var start = vp.max.x - x
            while start > vp.min.x - total {
                for (ci, c) in chars.enumerated() where !c.isWhitespace {
                    let px = start + Float(ci) * advance
                    if px > vp.min.x - 0.05, px < vp.max.x + 0.05, letters.count < Self.capacity {
                        letters.append(Letter(character: c, word: ri, position: SIMD2(px, row), size: 1, colourT: Float(ci) / Float(chars.count) + Float(ri) * 0.2))
                    }
                }
                start -= total
            }
        }
    }

    private func layBoxLabels(_ scene: TrackingScene, size: Float) {
        letters = []
        for (ti, text) in scene.texts.enumerated() {
            let chars = Array(text.text)
            let advance = advanceUV("M", size: size) * 0.9
            let width = advance * Float(chars.count)
            let start = text.centre.x - width / 2
            for (ci, c) in chars.enumerated() where !c.isWhitespace {
                letters.append(Letter(character: c, word: ti, position: SIMD2(start + Float(ci) * advance, text.centre.y), size: 1, colourT: text.isCode ? 0.8 : 0.2 + Float(ti) * 0.1))
            }
        }
    }

    private func stepRain(_ g: SceneGeometryLite, dt: Float, speed: Float, density: Int, aspect: Float, sway: Float) {
        let vp = viewport
        fill(to: density) { c, w, i in
            Letter(character: c, word: w, position: SIMD2(Float.random(in: vp.min.x...vp.max.x), Float.random(in: (vp.min.y - 1.5)...vp.max.y)), size: 1, colourT: Float(w) * 0.15 + Float.random(in: 0...0.1))
        }
        for i in letters.indices {
            var l = letters[i]
            var v = SIMD2(sinf(time * 1.5 + l.seed * 20) * 0.03 * sway, (0.15 + l.seed * 0.2) * speed)
            if let near = g.nearestBone(to: l.position), near.distance < 0.03 {
                let away = simd_normalize(l.position - near.point + SIMD2(1e-5, 0))
                v += away * 0.35
                v.y *= 0.3
                l.rotation += away.x * 3 * dt
            }
            l.position += v * dt
            l.rotation = l.rotation * 0.98 + sinf(time + l.seed * 10) * 0.002
            if l.position.y > vp.max.y + 0.08 { l.position = SIMD2(Float.random(in: vp.min.x...vp.max.x), vp.min.y - Float.random(in: 0.05...0.3)) }
            letters[i] = l
        }
    }

    // MARK: - Output

    private func write(palette: Palette, size: Float, atlas: GlyphAtlas, aspect: Float) -> SpriteBatch {
        let out = buffers.next()
        var n = 0
        let words = pool.words(at: time)
        for l in letters {
            if behaviour == .wordCloud {
                // Draw the whole word as a run starting at the letter's position.
                guard words.indices.contains(l.word) else { continue }
                let text = words[l.word].text
                let scale = 0.8 + 0.4 * (1 - Float(l.word) / Float(max(words.count, 1)))
                var x = l.position.x
                for c in text {
                    guard let g = atlas.glyph(for: c), n < buffers.spriteCapacity else { continue }
                    let rgb = palette.color(at: l.colourT)
                    let h = size * scale
                    out.sprites[n] = .glyph(g, at: SIMD2(x, l.position.y), height: h, color: SIMD4(rgb.r, rgb.g, rgb.b, l.alpha), rotation: l.rotation, atlasFontSize: Float(atlas.fontSize))
                    n += 1
                    x += g.advance * (h / Float(atlas.fontSize)) / pixelsPerUV.x
                }
                continue
            }
            guard let g = atlas.glyph(for: l.character), n < buffers.spriteCapacity else { continue }
            let rgb = palette.color(at: l.colourT)
            out.sprites[n] = .glyph(g, at: l.position, height: size, color: SIMD4(rgb.r, rgb.g, rgb.b, l.alpha), rotation: l.rotation, atlasFontSize: Float(atlas.fontSize))
            n += 1
        }
        return SpriteBatch(sprites: out.spriteBuffer, spriteCount: n, lines: nil, lineVertexCount: 0, atlas: atlas.texture, blend: .normal)
    }
}

/// Just what the letter behaviours need from a scene.
struct SceneGeometryLite {
    var anchors: [SIMD2<Float>] = []
    var bones: [(SIMD2<Float>, SIMD2<Float>)] = []
    var fastJoints: [(position: SIMD2<Float>, velocity: SIMD2<Float>)] = []

    init(scene: TrackingScene) {
        let bodyEdges: [(Int, Int)] = [(5, 6), (5, 7), (7, 9), (6, 8), (8, 10), (5, 11), (6, 12), (11, 12), (11, 13), (13, 15), (12, 14), (14, 16)]
        for person in scene.persons where person.confidence > 0 {
            for (j, joint) in person.joints.enumerated() where person.visible[j] && j >= 5 {
                anchors.append(joint)
                if simd_length(person.velocities[j]) > 0.6 { fastJoints.append((joint, person.velocities[j])) }
            }
            anchors += person.headAnchors
            for (a, b) in bodyEdges where person.visible[a] && person.visible[b] { bones.append((person.joints[a], person.joints[b])) }
            // The head: landmark features when they arrive, else a circle.
            for outline in person.headOutlines(aspect: scene.frameAspect) where outline.count >= 2 {
                for i in 1..<outline.count { bones.append((outline[i - 1], outline[i])) }
            }
        }
        let animalEdges: [(Int, Int)] = [(0, 9), (9, 10), (10, 11), (11, 12), (9, 13), (13, 14), (14, 15), (9, 22), (22, 16), (16, 17), (17, 18), (22, 19), (19, 20), (20, 21), (22, 23), (23, 24)]
        for animal in scene.animals where animal.confidence > 0 {
            for (j, joint) in animal.joints.enumerated() where animal.visible[j] { anchors.append(joint) }
            for (a, b) in animalEdges where animal.visible[a] && animal.visible[b] { bones.append((animal.joints[a], animal.joints[b])) }
        }
        for hand in scene.hands {
            anchors.append(hand.centre)
            for j in stride(from: 1, to: hand.joints.count, by: 4) where hand.visible[j] && hand.visible[0] { bones.append((hand.joints[0], hand.joints[j])) }
        }
    }

    func nearestBone(to p: SIMD2<Float>) -> (point: SIMD2<Float>, distance: Float)? {
        var best: (SIMD2<Float>, Float)?
        for (a, b) in bones {
            let ab = b - a
            let t = max(0, min(1, simd_dot(p - a, ab) / max(simd_dot(ab, ab), 1e-6)))
            let q = a + ab * t
            let d = simd_distance(q, p)
            if best == nil || d < best!.1 { best = (q, d) }
        }
        return best
    }
}
