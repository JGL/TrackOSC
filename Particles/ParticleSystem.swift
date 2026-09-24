//
//  ParticleSystem.swift
//  TrackOSC Particles
//
//  A structure-of-arrays particle simulation on the CPU, written straight
//  into the sprite buffers each frame. Behaviours differ in how particles
//  are born, what pushes them and how they are coloured; the geometry they
//  react to (joints, bones, history) comes from the tracking scene.
//

import Foundation
import Metal
import simd

enum ParticleBehaviour: String, CaseIterable, Sendable {
    case attract, repel, orbit, sparks, skeletonFire, ghostParade, longExposure,
         flowField, constellation, rainSnow, particleBody, handFountains
}

/// Points and bones gathered from a scene, in scene uv.
struct SceneGeometry {
    var anchors: [SIMD2<Float>] = []           // joints of people, animals, hands; face centres
    var anchorVelocities: [SIMD2<Float>] = []
    var bones: [(SIMD2<Float>, SIMD2<Float>)] = []
    var centroids: [SIMD2<Float>] = []         // one per person/animal
    var hands: [(centre: SIMD2<Float>, openness: Float, isLeft: Bool?)] = []
    var fastJoints: [(position: SIMD2<Float>, velocity: SIMD2<Float>)] = []

    init(scene: TrackingScene, speedThreshold: Float = 0.6) {
        let bodyEdges: [(Int, Int)] = [(5, 6), (5, 7), (7, 9), (6, 8), (8, 10), (5, 11), (6, 12), (11, 12), (11, 13), (13, 15), (12, 14), (14, 16)]
        for person in scene.persons where person.confidence > 0 {
            centroids.append(person.centroid)
            for (j, joint) in person.joints.enumerated() where person.visible[j] {
                anchors.append(joint)
                anchorVelocities.append(person.velocities[j])
                if simd_length(person.velocities[j]) > speedThreshold {
                    fastJoints.append((joint, person.velocities[j]))
                }
            }
            for (a, b) in bodyEdges where person.visible[a] && person.visible[b] {
                bones.append((person.joints[a], person.joints[b]))
            }
            // The head as a ring of short bones.
            let headJoints = (0..<5).filter { person.visible[$0] }.map { person.joints[$0] }
            if !headJoints.isEmpty {
                let centre = headJoints.reduce(.zero, +) / Float(headJoints.count)
                let radius: Float = person.visible[3] && person.visible[4] ? simd_distance(person.joints[3], person.joints[4]) * 0.6 : 0.03
                let n = 10
                for i in 0..<n {
                    let a0 = Float(i) / Float(n) * 2 * .pi, a1 = Float(i + 1) / Float(n) * 2 * .pi
                    let aspect = max(scene.frameAspect, 0.1)
                    bones.append((centre + SIMD2(cosf(a0) * radius / aspect, sinf(a0) * radius), centre + SIMD2(cosf(a1) * radius / aspect, sinf(a1) * radius)))
                }
            }
        }
        let animalEdges: [(Int, Int)] = [(0, 1), (0, 2), (1, 5), (5, 4), (4, 3), (2, 8), (8, 7), (7, 6), (0, 9), (9, 10), (10, 11), (11, 12), (9, 13), (13, 14), (14, 15), (9, 22), (22, 16), (16, 17), (17, 18), (22, 19), (19, 20), (20, 21), (22, 23), (23, 24)]
        for animal in scene.animals where animal.confidence > 0 {
            centroids.append(animal.centroid)
            for (j, joint) in animal.joints.enumerated() where animal.visible[j] {
                anchors.append(joint)
                anchorVelocities.append(animal.velocities[j])
                if simd_length(animal.velocities[j]) > speedThreshold { fastJoints.append((joint, animal.velocities[j])) }
            }
            for (a, b) in animalEdges where animal.visible[a] && animal.visible[b] {
                bones.append((animal.joints[a], animal.joints[b]))
            }
        }
        let handEdges: [(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8), (0, 9), (9, 10), (10, 11), (11, 12), (0, 13), (13, 14), (14, 15), (15, 16), (0, 17), (17, 18), (18, 19), (19, 20)]
        for hand in scene.hands {
            hands.append((hand.centre, hand.openness, hand.isLeft))
            for j in stride(from: 0, to: hand.joints.count, by: 4) where hand.visible[j] {
                anchors.append(hand.joints[j])
                anchorVelocities.append(.zero)
            }
            for (a, b) in handEdges where hand.visible[a] && hand.visible[b] {
                bones.append((hand.joints[a], hand.joints[b]))
            }
        }
        for face in scene.faces where face.personID == nil {
            anchors.append(face.centre)
            anchorVelocities.append(.zero)
        }
    }

    var isEmpty: Bool { anchors.isEmpty && bones.isEmpty }

    func nearestAnchor(to p: SIMD2<Float>) -> (point: SIMD2<Float>, velocity: SIMD2<Float>, distance: Float)? {
        var best: (SIMD2<Float>, SIMD2<Float>, Float)?
        for (i, a) in anchors.enumerated() {
            let d = simd_distance(a, p)
            if best == nil || d < best!.2 { best = (a, anchorVelocities[i], d) }
        }
        return best
    }

    func nearestBone(to p: SIMD2<Float>) -> (point: SIMD2<Float>, distance: Float, tangent: SIMD2<Float>)? {
        var best: (SIMD2<Float>, Float, SIMD2<Float>)?
        for (a, b) in bones {
            let ab = b - a
            let t = max(0, min(1, simd_dot(p - a, ab) / max(simd_dot(ab, ab), 1e-6)))
            let q = a + ab * t
            let d = simd_distance(q, p)
            if best == nil || d < best!.1 { best = (q, d, simd_normalize(ab + SIMD2(1e-5, 0))) }
        }
        return best
    }

    /// A random point on a random bone.
    func randomBonePoint() -> SIMD2<Float>? {
        guard let (a, b) = bones.randomElement() else { return nil }
        return a + (b - a) * Float.random(in: 0...1)
    }
}

@MainActor
final class ParticleSystem {
    static let capacity = 100_000

    private var position: [SIMD2<Float>]
    private var velocity: [SIMD2<Float>]
    private var home: [SIMD2<Float>]
    private var life: [Float]
    private var maxLife: [Float]
    private var seed: [Float]
    private var alive: [Bool]
    private var count = 0
    private var behaviour: ParticleBehaviour?
    private var time: Float = 0
    private var emitCarry: Float = 0
    let buffers: SpriteBuffers

    init(device: MTLDevice) {
        buffers = SpriteBuffers(device: device, spriteCapacity: Self.capacity, lineCapacity: 16_384)
        position = Array(repeating: .zero, count: Self.capacity)
        velocity = Array(repeating: .zero, count: Self.capacity)
        home = Array(repeating: .zero, count: Self.capacity)
        life = Array(repeating: 0, count: Self.capacity)
        maxLife = Array(repeating: 1, count: Self.capacity)
        seed = (0..<Self.capacity).map { _ in Float.random(in: 0...1) }
        alive = Array(repeating: false, count: Self.capacity)
    }

    // MARK: - Step

    var viewport = SceneViewport()

    func step(scene: TrackingScene, behaviour: ParticleBehaviour, params: ParameterValues, palette: Palette,
              history: SceneHistory, viewport: SceneViewport, dt rawDt: Float) -> SpriteBatch {
        self.viewport = viewport
        let dt = min(max(rawDt, 1 / 240), 1 / 20)
        time += dt
        let wanted = min(Int(params["count"] ?? 8000), Self.capacity)
        let size = params["size"] ?? 6
        let speed = params["speed"] ?? 1
        let extra = params["extra"] ?? 1
        let aspect = max(scene.frameAspect, 0.1)
        let geometry = SceneGeometry(scene: scene)

        if behaviour != self.behaviour || count != wanted {
            reset(count: wanted, behaviour: behaviour, aspect: aspect)
            self.behaviour = behaviour
        }

        switch behaviour {
        case .attract: stepAttract(geometry, dt: dt, speed: speed, strength: extra, aspect: aspect)
        case .repel: stepRepel(geometry, dt: dt, speed: speed, radius: 0.12 * extra, aspect: aspect)
        case .orbit: stepOrbit(geometry, dt: dt, speed: speed, radius: 0.15 * extra, aspect: aspect)
        case .sparks: stepSparks(geometry, dt: dt, speed: speed, gravity: extra)
        case .skeletonFire: stepFire(geometry, dt: dt, speed: speed, rise: extra)
        case .ghostParade: stepGhosts(history, dt: dt, speed: speed, spacing: extra, scene: scene)
        case .longExposure: stepLongExposure(geometry, dt: dt, hold: extra * 3)
        case .flowField: stepFlow(geometry, dt: dt, speed: speed, scale: extra * 3, aspect: aspect)
        case .constellation: stepConstellation(geometry, dt: dt, speed: speed, aspect: aspect)
        case .rainSnow: stepRain(geometry, dt: dt, speed: speed, snow: extra, aspect: aspect)
        case .particleBody: stepParticleBody(geometry, dt: dt, jitter: extra)
        case .handFountains: stepFountains(geometry, dt: dt, speed: speed, spread: extra)
        }

        return write(behaviour: behaviour, geometry: geometry, palette: palette, size: size, aspect: aspect)
    }

    private func reset(count: Int, behaviour: ParticleBehaviour, aspect: Float) {
        self.count = count
        for i in 0..<count {
            position[i] = viewport.random()
            velocity[i] = .zero
            home[i] = position[i]
            life[i] = 0
            maxLife[i] = 1
            alive[i] = behaviour == .attract || behaviour == .repel || behaviour == .orbit || behaviour == .flowField || behaviour == .constellation || behaviour == .rainSnow
            if behaviour == .rainSnow { position[i].y = Float.random(in: (viewport.min.y - 1)...viewport.max.y) }
        }
        emitCarry = 0
    }

    /// Emit `rate` particles per second into dead slots.
    private func emit(perSecond rate: Float, dt: Float, _ make: (Int) -> Void) {
        emitCarry += rate * dt
        var toEmit = Int(emitCarry)
        emitCarry -= Float(toEmit)
        guard toEmit > 0 else { return }
        var i = Int.random(in: 0..<max(count, 1))
        var scanned = 0
        while toEmit > 0, scanned < count {
            if !alive[i] {
                make(i)
                alive[i] = true
                toEmit -= 1
            }
            i = (i + 1) % count
            scanned += 1
        }
    }

    private func age(_ i: Int, dt: Float) {
        life[i] += dt
        if life[i] >= maxLife[i] { alive[i] = false }
    }

    // MARK: - Behaviours

    private func stepAttract(_ g: SceneGeometry, dt: Float, speed: Float, strength: Float, aspect: Float) {
        for i in 0..<count {
            if let target = g.nearestAnchor(to: position[i]) {
                let dir = target.point - position[i]
                velocity[i] += dir * (2.5 * strength * speed) * dt
                velocity[i] *= 0.92
            } else {
                velocity[i] += SIMD2(curl(position[i] * 3 + time * 0.1) * 0.3) * dt * speed
                velocity[i] *= 0.98
            }
            position[i] += velocity[i] * dt
            wrap(i)
        }
    }

    private func stepRepel(_ g: SceneGeometry, dt: Float, speed: Float, radius: Float, aspect: Float) {
        for i in 0..<count {
            velocity[i] += (home[i] - position[i]) * 3 * dt * speed
            if let near = g.nearestBone(to: position[i]), near.distance < radius {
                let away = position[i] - near.point
                let d = max(near.distance, 0.005)
                velocity[i] += simd_normalize(away + SIMD2(1e-5, 0)) * (radius - d) / d * 0.6 * speed * dt
            }
            velocity[i] *= 0.9
            position[i] += velocity[i] * dt
        }
    }

    private func stepOrbit(_ g: SceneGeometry, dt: Float, speed: Float, radius: Float, aspect: Float) {
        let centres = g.centroids.isEmpty ? [(viewport.min + viewport.max) / 2] : g.centroids
        for i in 0..<count {
            let centre = centres[i % centres.count]
            var offset = position[i] - centre
            offset.x *= aspect
            let d = max(simd_length(offset), 0.01)
            let tangent = SIMD2(-offset.y, offset.x) / d
            let wanted = radius * (0.4 + seed[i] * 1.2)
            var force = tangent * (0.5 + seed[i]) * speed
            force -= offset / d * (d - wanted) * 4
            force.x /= aspect
            velocity[i] += force * dt
            velocity[i] *= 0.96
            position[i] += velocity[i] * dt
        }
    }

    private func stepSparks(_ g: SceneGeometry, dt: Float, speed: Float, gravity: Float) {
        for joint in g.fastJoints {
            emit(perSecond: 400 * min(simd_length(joint.velocity), 3), dt: dt) { i in
                position[i] = joint.position
                let jitter = SIMD2(Float.random(in: -0.3...0.3), Float.random(in: -0.3...0.3))
                velocity[i] = joint.velocity * 0.5 * speed + jitter * speed
                life[i] = 0
                maxLife[i] = Float.random(in: 0.4...1.2)
            }
        }
        for i in 0..<count where alive[i] {
            velocity[i].y += 0.6 * gravity * dt
            velocity[i] *= 0.98
            position[i] += velocity[i] * dt
            age(i, dt: dt)
        }
    }

    private func stepFire(_ g: SceneGeometry, dt: Float, speed: Float, rise: Float) {
        if !g.bones.isEmpty {
            emit(perSecond: Float(count) * 1.2, dt: dt) { i in
                position[i] = g.randomBonePoint() ?? SIMD2(0.5, 0.5)
                velocity[i] = SIMD2(Float.random(in: -0.05...0.05), Float.random(in: -0.1...0) * speed)
                life[i] = 0
                maxLife[i] = Float.random(in: 0.5...1.1)
            }
        }
        for i in 0..<count where alive[i] {
            let n = curl(position[i] * 8 + time * 0.5)
            velocity[i] += SIMD2(n.x * 0.4, -0.35 * rise) * dt * speed
            velocity[i] *= 0.97
            position[i] += velocity[i] * dt
            age(i, dt: dt)
        }
    }

    private func stepGhosts(_ history: SceneHistory, dt: Float, speed: Float, spacing: Float, scene: TrackingScene) {
        // Ghosts sit where each person was 0.5, 1, 1.5 … seconds ago.
        let bodyEdges: [(Int, Int)] = [(5, 6), (5, 7), (7, 9), (6, 8), (8, 10), (5, 11), (6, 12), (11, 12), (11, 13), (13, 15), (12, 14), (14, 16)]
        var ghostBones: [(SIMD2<Float>, SIMD2<Float>, Float)] = []
        for k in 1...5 {
            let ago = Float(k) * 0.4 * spacing
            guard let sample = history.sample(secondsAgo: ago) else { continue }
            for (_, joints) in sample.joints {
                for (a, b) in bodyEdges where a < joints.count && b < joints.count {
                    ghostBones.append((joints[a], joints[b], Float(k)))
                }
            }
        }
        if ghostBones.isEmpty {
            // No history yet (or nobody moved): show the present as ghost 1.
            for person in scene.persons where person.confidence > 0 {
                for (a, b) in bodyEdges where person.visible[a] && person.visible[b] { ghostBones.append((person.joints[a], person.joints[b], 1)) }
            }
        }
        if !ghostBones.isEmpty {
            emit(perSecond: Float(count) * 1.5, dt: dt) { i in
                let bone = ghostBones[Int.random(in: 0..<ghostBones.count)]
                position[i] = bone.0 + (bone.1 - bone.0) * Float.random(in: 0...1)
                velocity[i] = SIMD2(Float.random(in: -0.02...0.02), Float.random(in: -0.02...0.02)) * speed
                life[i] = 0
                maxLife[i] = 0.5
                seed[i] = bone.2 / 5   // which ghost, for colour
            }
        }
        for i in 0..<count where alive[i] {
            position[i] += velocity[i] * dt
            age(i, dt: dt)
        }
    }

    private func stepLongExposure(_ g: SceneGeometry, dt: Float, hold: Float) {
        if !g.anchors.isEmpty {
            emit(perSecond: Float(g.anchors.count) * 60, dt: dt) { i in
                let a = g.anchors[Int.random(in: 0..<g.anchors.count)]
                position[i] = a + SIMD2(Float.random(in: -0.004...0.004), Float.random(in: -0.004...0.004))
                velocity[i] = .zero
                life[i] = 0
                maxLife[i] = hold
            }
        }
        for i in 0..<count where alive[i] { age(i, dt: dt) }
    }

    private func stepFlow(_ g: SceneGeometry, dt: Float, speed: Float, scale: Float, aspect: Float) {
        for i in 0..<count {
            var v = curl(position[i] * scale + time * 0.15) * 0.25
            if let near = g.nearestAnchor(to: position[i]), near.distance < 0.25 {
                v += near.velocity * 0.8 + (near.point - position[i]) * 0.2
            }
            velocity[i] += (v * speed - velocity[i]) * min(1, dt * 4)
            position[i] += velocity[i] * dt
            wrap(i)
        }
    }

    private func stepConstellation(_ g: SceneGeometry, dt: Float, speed: Float, aspect: Float) {
        for i in 0..<count {
            velocity[i] = curl(position[i] * 2 + time * 0.03 + seed[i]) * 0.03 * speed
            position[i] += velocity[i] * dt
            wrap(i)
        }
    }

    private func stepRain(_ g: SceneGeometry, dt: Float, speed: Float, snow: Float, aspect: Float) {
        for i in 0..<count {
            let fall = (0.25 + seed[i] * 0.35) * speed / (0.5 + snow)
            var v = SIMD2(sinf(time * 1.3 + seed[i] * 20) * 0.02 * snow, fall)
            if let near = g.nearestBone(to: position[i]), near.distance < 0.02 {
                let away = simd_normalize(position[i] - near.point + SIMD2(1e-5, 0))
                v += away * 0.3
                v.y *= 0.2
            }
            position[i] += v * dt
            if position[i].y > viewport.max.y + 0.05 || position[i].x < viewport.min.x - 0.05 || position[i].x > viewport.max.x + 0.05 {
                position[i] = SIMD2(Float.random(in: viewport.min.x...viewport.max.x), viewport.min.y - Float.random(in: 0.02...0.2))
            }
        }
    }

    private func stepParticleBody(_ g: SceneGeometry, dt: Float, jitter: Float) {
        if !g.bones.isEmpty {
            emit(perSecond: Float(count) * 3, dt: dt) { i in
                position[i] = (g.randomBonePoint() ?? SIMD2(0.5, 0.5)) + SIMD2(Float.random(in: -0.008...0.008), Float.random(in: -0.008...0.008)) * jitter
                velocity[i] = SIMD2(Float.random(in: -0.03...0.03), Float.random(in: -0.03...0.03)) * jitter
                life[i] = 0
                maxLife[i] = 0.35
            }
        }
        for i in 0..<count where alive[i] {
            position[i] += velocity[i] * dt
            age(i, dt: dt)
        }
    }

    private func stepFountains(_ g: SceneGeometry, dt: Float, speed: Float, spread: Float) {
        for hand in g.hands {
            emit(perSecond: 1500, dt: dt) { i in
                position[i] = hand.centre
                let angle = -Float.pi / 2 + Float.random(in: -0.5...0.5) * spread * (0.3 + hand.openness)
                velocity[i] = SIMD2(cosf(angle), sinf(angle)) * (0.5 + Float.random(in: 0...0.4)) * speed
                life[i] = 0
                maxLife[i] = Float.random(in: 0.8...1.6)
                seed[i] = hand.isLeft == true ? 0.2 : 0.7
            }
        }
        for i in 0..<count where alive[i] {
            velocity[i].y += 0.5 * dt
            position[i] += velocity[i] * dt
            age(i, dt: dt)
        }
    }

    // MARK: - Helpers

    private func wrap(_ i: Int) {
        position[i] = viewport.wrap(position[i])
    }

    private func hash(_ p: SIMD2<Float>) -> Float {
        var h = simd_dot(p, SIMD2(127.1, 311.7))
        h = sinf(h) * 43758.5453
        return h - floorf(h)
    }

    private func noise(_ p: SIMD2<Float>) -> Float {
        let i = SIMD2(floorf(p.x), floorf(p.y)), f = p - i
        let s = f * f * (3 - 2 * f)
        let a = hash(i), b = hash(i + SIMD2(1, 0)), c = hash(i + SIMD2(0, 1)), d = hash(i + SIMD2(1, 1))
        return simd_mix(simd_mix(a, b, s.x), simd_mix(c, d, s.x), s.y)
    }

    /// Divergence-free flow from a noise potential.
    private func curl(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let e: Float = 0.01
        let dx = noise(p + SIMD2(e, 0)) - noise(p - SIMD2(e, 0))
        let dy = noise(p + SIMD2(0, e)) - noise(p - SIMD2(0, e))
        return SIMD2(dy, -dx) / (2 * e)
    }

    // MARK: - Output

    private func write(behaviour: ParticleBehaviour, geometry g: SceneGeometry, palette: Palette, size: Float, aspect: Float) -> SpriteBatch {
        let out = buffers.next()
        var n = 0
        for i in 0..<count where alive[i] {
            var t: Float
            var brightness: Float = 1
            var pixelSize = size
            switch behaviour {
            case .sparks, .skeletonFire, .particleBody, .handFountains, .longExposure, .ghostParade:
                let l = life[i] / max(maxLife[i], 0.01)
                brightness = 1 - l
                pixelSize = size * (behaviour == .skeletonFire ? (1 - l * 0.7) : 1)
                t = behaviour == .skeletonFire ? l * 0.6 : (behaviour == .ghostParade || behaviour == .handFountains ? seed[i] : seed[i] * 0.3 + l * 0.2)
            case .rainSnow:
                t = 0.7 + seed[i] * 0.2
                brightness = 0.7
            case .attract, .flowField:
                t = seed[i] * 0.4 + simd_length(velocity[i]) * 0.8
                brightness = 0.3
            default:
                t = seed[i] * 0.4 + simd_length(velocity[i]) * 0.8
                brightness = 0.55
            }
            let c = palette.color(at: t)
            out.sprites[n] = .dot(at: position[i], size: pixelSize * (0.6 + seed[i] * 0.8), color: SIMD4(c.r, c.g, c.b, brightness), softness: 0.7)
            n += 1
            if n >= buffers.spriteCapacity { break }
        }
        var lineCount = 0
        if behaviour == .constellation {
            // Bones as constellation lines, joints as bright stars, and each
            // star tied to a joint when close enough.
            let line = palette.color(at: 0.5)
            for (a, b) in g.bones where lineCount + 2 <= buffers.lineCapacity {
                out.lines[lineCount] = GPULineVertex(position: a, color: SIMD4(line.r, line.g, line.b, 0.9)); lineCount += 1
                out.lines[lineCount] = GPULineVertex(position: b, color: SIMD4(line.r, line.g, line.b, 0.9)); lineCount += 1
            }
            for anchor in g.anchors where n < buffers.spriteCapacity {
                let c = palette.color(at: 0.2)
                out.sprites[n] = .dot(at: anchor, size: size * 2.2, color: SIMD4(c.r, c.g, c.b, 1), softness: 0.5)
                n += 1
            }
            for i in 0..<count where lineCount + 2 <= buffers.lineCapacity {
                guard let near = g.nearestAnchor(to: position[i]), near.distance < 0.12 else { continue }
                let fade = 1 - near.distance / 0.12
                out.lines[lineCount] = GPULineVertex(position: position[i], color: SIMD4(line.r, line.g, line.b, 0.6 * fade)); lineCount += 1
                out.lines[lineCount] = GPULineVertex(position: near.point, color: SIMD4(line.r, line.g, line.b, 0.6 * fade)); lineCount += 1
            }
        }
        return SpriteBatch(sprites: out.spriteBuffer, spriteCount: n, lines: out.lineBuffer, lineVertexCount: lineCount, atlas: nil, blend: .additive)
    }
}
