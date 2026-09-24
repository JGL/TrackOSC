//
//  SceneBuilder.swift
//  TrackOSC (ReceiverCore)
//
//  Turns the receiver's latest frames into a TrackingScene at display
//  rate: normalises and mirrors, tracks people, attaches hands and faces,
//  smooths presence and activity, keeps a short history, and switches to
//  the attract scene when nothing has arrived for a while.
//

import Foundation
import simd
import PoseioscShared

@MainActor
final class SceneBuilder {
    var mirror = false
    var smoothing: Float = 0.08 { didSet { tracker.smoothing = smoothing; animalTracker.smoothing = smoothing } }
    /// Seconds without live tracking before the attract scene takes over (0 = never).
    var attractDelay: Float = 20
    var staleInterval: TimeInterval = ReceiverModel.staleInterval

    private(set) var scene = TrackingScene.empty
    private(set) var history = SceneHistory()
    private var tracker = PersonTracker()
    private var animalTracker = PersonTracker()
    private var attract = AttractScene()
    private var lastTime: Float?
    private var lastLive: Float?
    private var presence: Float = 0
    private var activity: Float = 0
    private let start = ContinuousClock.now

    /// Build the scene for now from the receiver's latest frames.
    @discardableResult
    func update(latest: [FrameKind: TimestampedFrame], now: Date = .now) -> TrackingScene {
        let time = Float((ContinuousClock.now - start).components.seconds) + Float((ContinuousClock.now - start).components.attoseconds) / 1e18
        let dt = max(1 / 240, min(0.1, lastTime.map { time - $0 } ?? 1 / 60))
        lastTime = time

        func fresh(_ kind: FrameKind) -> DecodedFrame? {
            guard let frame = latest[kind], now.timeIntervalSince(frame.receivedAt) < staleInterval else { return nil }
            return frame.decoded
        }

        var aspect: Float = scene.frameAspect
        func normalise(_ p: WirePoint, _ w: Int32, _ h: Int32) -> ScenePoint {
            let x = Float(p.x) / Float(max(w, 1))
            return ScenePoint(mirror ? 1 - x : x, Float(p.y) / Float(max(h, 1)))
        }
        func normaliseRect(_ r: WireRect, _ w: Int32, _ h: Int32) -> (centre: ScenePoint, size: ScenePoint) {
            let cx = (r.left + r.width / 2) / Float(max(w, 1))
            return (ScenePoint(mirror ? 1 - cx : cx, (r.top + r.height / 2) / Float(max(h, 1))),
                    ScenePoint(r.width / Float(max(w, 1)), r.height / Float(max(h, 1))))
        }

        // Bodies → tracker.
        var detections: [(joints: [ScenePoint], visible: [Bool])] = []
        if case .poses(let f)? = fresh(.poses) {
            aspect = Float(f.width) / Float(max(f.height, 1))
            for pose in f.detections {
                detections.append((pose.joints.map { normalise($0, f.width, f.height) }, pose.joints.map { $0.confidence > 0 }))
            }
        }
        tracker.update(detections: detections, time: time, dt: dt)

        var persons: [ScenePerson] = tracker.tracked.map { t in
            let visibleJoints = zip(t.joints, t.visible).filter { $0.1 }.map { $0.0 }
            let minP = visibleJoints.reduce(ScenePoint(1, 1)) { simd_min($0, $1) }
            let maxP = visibleJoints.reduce(ScenePoint(0, 0)) { simd_max($0, $1) }
            return ScenePerson(
                id: t.id, joints: t.joints, visible: t.visible, velocities: t.velocities,
                centroid: PersonTracker.centroid(t.joints, t.visible),
                boundingBox: visibleJoints.isEmpty ? (ScenePoint(0.5, 0.5), ScenePoint(0.5, 0.5)) : (minP, maxP),
                hands: [], face: nil, age: time - t.firstSeen, confidence: t.missing ? 0 : 1, speed: t.speed
            )
        }

        // Hands → nearest wrist.
        var hands: [SceneHand] = []
        if case .hands(let f)? = fresh(.hands) {
            aspect = Float(f.width) / Float(max(f.height, 1))
            for hand in f.detections {
                let joints = hand.joints.map { normalise($0, f.width, f.height) }
                let visible = hand.joints.map { $0.confidence > 0 }
                guard visible[0] else { continue }
                let wrist = joints[0]
                let tips = [4, 8, 12, 16, 20].filter { visible[$0] }.map { simd_distance(joints[$0], wrist) }
                let knuckles = [5, 9, 13, 17].filter { visible[$0] }.map { simd_distance(joints[$0], wrist) }
                let size = knuckles.max() ?? 0.05
                let openness = tips.isEmpty || size <= 0 ? 0.5 : min(1, max(0, ((tips.reduce(0, +) / Float(tips.count)) / size - 1.0) / 0.9))
                var best: (person: Int, isLeft: Bool, distance: Float)?
                for (i, person) in persons.enumerated() {
                    for (index, isLeft) in [(FrameMetrics.leftWristIndex, true), (FrameMetrics.rightWristIndex, false)] where person.visible[index] {
                        let d = simd_distance(person.joints[index], wrist)
                        if best == nil || d < best!.distance { best = (i, isLeft, d) }
                    }
                }
                var sceneHand = SceneHand(joints: joints, visible: visible, centre: PersonTracker.centroid(joints, visible),
                                          openness: openness, isLeft: nil, personID: nil)
                if let best, best.distance < 0.12 {
                    sceneHand.isLeft = mirror ? !best.isLeft : best.isLeft
                    sceneHand.personID = persons[best.person].id
                    persons[best.person].hands.append(sceneHand)
                }
                hands.append(sceneHand)
            }
        }

        // Faces → nearest nose.
        var faces: [SceneFace] = []
        var landmarksByIndex: [[ScenePoint]] = []
        if case .faces(let f)? = fresh(.faces) {
            landmarksByIndex = f.detections.map { $0.points.map { normalise($0, f.width, f.height) } }
        }
        if case .faceBoxes(let f)? = fresh(.faceBoxes) {
            aspect = Float(f.width) / Float(max(f.height, 1))
            for (i, box) in f.detections.enumerated() {
                let rect = normaliseRect(box.box, f.width, f.height)
                var mouth: Float = 0
                var landmarks: [ScenePoint] = []
                if i < landmarksByIndex.count {
                    landmarks = landmarksByIndex[i]
                    if case .faces(let lf)? = fresh(.faces), i < lf.detections.count,
                       let openness = FaceLandmarks.mouthOpenness(lf.detections[i].points) {
                        mouth = min(1, openness / 0.7)
                    }
                }
                var face = SceneFace(centre: rect.centre, size: rect.size,
                                     yawDegrees: mirror ? -box.yawDegrees : box.yawDegrees,
                                     pitchDegrees: box.pitchDegrees, rollDegrees: mirror ? -box.rollDegrees : box.rollDegrees,
                                     mouthOpenness: mouth, landmarks: landmarks, personID: nil)
                var best: (person: Int, distance: Float)?
                for (p, person) in persons.enumerated() where person.visible[FrameMetrics.noseIndex] {
                    let d = simd_distance(person.joints[FrameMetrics.noseIndex], rect.centre)
                    if best == nil || d < best!.distance { best = (p, d) }
                }
                if let best, best.distance < max(0.15, rect.size.y) {
                    face.personID = persons[best.person].id
                    persons[best.person].face = face
                }
                faces.append(face)
            }
        }

        // Cats and dogs → their own tracker (same identity and smoothing rules).
        var animalDetections: [(joints: [ScenePoint], visible: [Bool])] = []
        if case .animalPoses(let f)? = fresh(.animalPoses) {
            aspect = Float(f.width) / Float(max(f.height, 1))
            for animal in f.detections {
                animalDetections.append((animal.joints.map { normalise($0, f.width, f.height) }, animal.joints.map { $0.confidence > 0 }))
            }
        }
        animalTracker.update(detections: animalDetections, time: time, dt: dt)
        let animals: [SceneAnimal] = animalTracker.tracked.map { t in
            SceneAnimal(id: t.id, joints: t.joints, visible: t.visible, velocities: t.velocities,
                        centroid: PersonTracker.centroid(t.joints, t.visible),
                        age: time - t.firstSeen, confidence: t.missing ? 0 : 1, speed: t.speed)
        }

        // Text and codes.
        var texts: [SceneText] = []
        if case .texts(let f)? = fresh(.texts) {
            for box in f.detections where !box.label.isEmpty {
                let rect = normaliseRect(box.box, f.width, f.height)
                texts.append(SceneText(text: box.label, centre: rect.centre, size: rect.size, isCode: false))
            }
        }
        if case .barcodes(let f)? = fresh(.barcodes) {
            for code in f.detections where !code.payload.isEmpty {
                let rect = normaliseRect(code.box, f.width, f.height)
                texts.append(SceneText(text: code.payload, centre: rect.centre, size: rect.size, isCode: true))
            }
        }

        var contours: [[ScenePoint]] = []
        if case .contours(let f)? = fresh(.contours) {
            contours = f.detections.map { contour in
                contour.points.map { p in
                    let x = Float(p.x) / Float(max(f.width, 1))
                    return ScenePoint(mirror ? 1 - x : x, Float(p.y) / Float(max(f.height, 1)))
                }
            }
            .filter { $0.count >= 4 }
            .sorted { $0.count > $1.count }
        }

        // Moods.
        let live = !persons.isEmpty || !hands.isEmpty || !faces.isEmpty || !animals.isEmpty
        if live { lastLive = time }
        let presenceTarget: Float = live ? 1 : 0
        presence += (presenceTarget - presence) * min(1, dt / (live ? 0.3 : 1.5))
        let speeds = persons.map(\.speed) + animals.map(\.speed)
        let meanSpeed = speeds.isEmpty ? 0 : speeds.reduce(0, +) / Float(speeds.count)
        let activityTarget = min(1, meanSpeed / 0.8)
        activity += (activityTarget - activity) * min(1, dt / 0.5)

        var built = TrackingScene(time: time, deltaTime: dt, frameAspect: aspect, persons: persons, hands: hands,
                                  faces: faces, animals: animals, texts: texts, contours: contours, presence: presence, activity: activity, isAttract: false)

        let idleFor = lastLive.map { time - $0 } ?? .infinity
        if !live, attractDelay > 0, idleFor > attractDelay {
            built = attract.scene(at: time, dt: dt, aspect: aspect)
            built.presence = presence
            built.activity = activity
        }

        history.record(built)
        scene = built
        return built
    }

    func reset() {
        tracker.reset()
        animalTracker.reset()
        history = SceneHistory()
        scene = .empty
    }
}
