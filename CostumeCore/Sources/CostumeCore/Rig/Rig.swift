//
//  Rig.swift
//  CostumeCore
//
//  Puts a costume on a tracked person: for every layer, the affine
//  transform from document space to the stage. Bones map their art axis
//  onto a live joint pair; the head onto the ears; face parts onto
//  landmark clusters (falling back to the head); hand parts onto the 21
//  hand joints (falling back to the body's wrist). Facing away mirrors
//  the art; missing joints fade the layer out and hold its last place.
//

import CoreGraphics
import Foundation

/// One person's tracking, in stage pixels (y down).
public struct RigInput: Sendable {
    /// 17 body joints in PoseNet order; `bodyVisible` marks the ones seen.
    public var body: [CGPoint]
    public var bodyVisible: [Bool]
    /// 21-joint hands (MediaPipe order) with their handedness when known.
    public var hands: [RigHand]
    public var face: RigFace?
    public init(body: [CGPoint], bodyVisible: [Bool], hands: [RigHand] = [], face: RigFace? = nil) {
        self.body = body; self.bodyVisible = bodyVisible; self.hands = hands; self.face = face
    }
}

public struct RigHand: Sendable {
    public var joints: [CGPoint]
    public var visible: [Bool]
    public var isLeft: Bool?
    public init(joints: [CGPoint], visible: [Bool], isLeft: Bool?) { self.joints = joints; self.visible = visible; self.isLeft = isLeft }
}

public struct RigFace: Sendable {
    /// 76 landmarks in the sender's layout (see FaceLandmarks in PoseioscShared), or empty.
    public var landmarks: [CGPoint]
    public var rollDegrees: CGFloat
    public var mouthOpenness: CGFloat
    public init(landmarks: [CGPoint], rollDegrees: CGFloat, mouthOpenness: CGFloat) {
        self.landmarks = landmarks; self.rollDegrees = rollDegrees; self.mouthOpenness = mouthOpenness
    }
    // The 76-point layout (duplicated from PoseioscShared.FaceLandmarks so the package stands alone).
    static let leftEye = 0..<6, rightEye = 7..<13, leftBrow = 14..<20, rightBrow = 20..<26
    static let outerLips = 26..<40, nose = 46..<54, contour = 59..<76
    static let leftPupil = 6, rightPupil = 13
}

/// Where a layer goes this frame.
public struct LayerPlacement: Sendable {
    public var layerID: Int
    public var transform: CGAffineTransform
    public var opacity: CGFloat
    public var isVisible: Bool { opacity > 0.005 }
}

/// Body joint indices (PoseNet order).
public enum BodyJoint {
    public static let nose = 0, leftEye = 1, rightEye = 2, leftEar = 3, rightEar = 4
    public static let leftShoulder = 5, rightShoulder = 6, leftElbow = 7, rightElbow = 8, leftWrist = 9, rightWrist = 10
    public static let leftHip = 11, rightHip = 12, leftKnee = 13, rightKnee = 14, leftAnkle = 15, rightAnkle = 16
}

public struct Rig {
    /// Seconds for a layer to fade when its joints go missing (and to return).
    public var fadeSeconds: CGFloat = 0.3
    /// Facing-away hysteresis: shoulder separation over torso length that flips the state.
    public var facingThreshold: CGFloat = 0.12
    /// True when the scene is mirrored (a mirror on the wall), which swaps which way "facing" reads.
    public var mirrored = false

    private var opacities: [Int: CGFloat] = [:]
    private var lastTransforms: [Int: CGAffineTransform] = [:]
    private var facingAway = false
    private var figureScale: CGFloat = 1
    private var hasFigureScale = false

    public init() {}

    public private(set) var isFacingAway: Bool {
        get { facingAway }
        set { facingAway = newValue }
    }

    public mutating func reset() {
        opacities.removeAll()
        lastTransforms.removeAll()
        facingAway = false
        hasFigureScale = false
    }

    // MARK: - Solve

    public mutating func solve(costume: Costume, input: RigInput, deltaTime: CGFloat) -> [LayerPlacement] {
        let joints = input.body
        let seen = input.bodyVisible
        func joint(_ i: Int) -> CGPoint? { seen.indices.contains(i) && seen[i] ? joints[i] : nil }
        func mid(_ a: Int, _ b: Int) -> CGPoint? {
            guard let p = joint(a), let q = joint(b) else { return joint(a) ?? joint(b) }
            return CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
        }

        // Figure scale: live torso over art torso (or shoulders over guide:shoulders).
        let shoulderMid = mid(BodyJoint.leftShoulder, BodyJoint.rightShoulder)
        let hipMid = mid(BodyJoint.leftHip, BodyJoint.rightHip)
        var scaleSample: CGFloat?
        if let s = shoulderMid, let h = hipMid, let artTorso = artTorsoLength(costume) {
            scaleSample = distance(s, h) / artTorso
        } else if let l = joint(BodyJoint.leftShoulder), let r = joint(BodyJoint.rightShoulder), let g = costume.guides["shoulders"] {
            scaleSample = distance(l, r) / max(1, distance(g.0, g.1))
        }
        if let sample = scaleSample, sample.isFinite, sample > 0 {
            figureScale = hasFigureScale ? figureScale + (sample - figureScale) * min(1, deltaTime * 8) : sample
            hasFigureScale = true
        }

        // Facing: the person's left shoulder appears on the image's right when facing the camera.
        if let l = joint(BodyJoint.leftShoulder), let r = joint(BodyJoint.rightShoulder), let s = shoulderMid, let h = hipMid {
            let torso = max(1, distance(s, h))
            var dx = (l.x - r.x) / torso
            if mirrored { dx = -dx }
            if dx > facingThreshold { facingAway = false } else if dx < -facingThreshold { facingAway = true }
        }

        // Head frame: centre and the ear line (or eyes, or nose with a default width).
        let headTarget = headSegment(joints: joints, seen: seen, face: input.face)

        var placements: [LayerPlacement] = []
        placements.reserveCapacity(costume.layers.count)
        for layer in costume.layers {
            var target: (CGPoint, CGPoint)?
            var mode = Mode.uniform
            var horizontal = false
            var perpendicularScale: CGFloat? = nil
            var isStatic = false

            switch layer.name.role {
            case .scenery:
                isStatic = true
            case .bone(let bone, let side):
                horizontal = bone.defaultAxisIsHorizontal
                target = boneSegment(bone, side, joint: joint, mid: mid)
            case .head:
                horizontal = true
                target = headTarget
            case .face(let part):
                horizontal = true
                if let face = input.face, face.landmarks.count >= 76, let seg = faceSegment(part, face: face) {
                    target = seg
                    if part == .mouth { perpendicularScale = 1 + face.mouthOpenness * 1.2 }
                } else {
                    // No landmarks: follow the head as a group, keeping the art's placement relative to the head layer.
                    if let head = costume.layers(with: .head).first, let headTarget {
                        let (a0, a1) = head.axis(horizontal: true)
                        let t = Self.transform(from: (a0, a1), to: headTarget, mode: .uniform, perpendicular: nil, mirror: facingAway && !layer.name.flags.contains(.noflip))
                        placements.append(place(layer, transform: t, visible: true, deltaTime: deltaTime))
                        continue
                    }
                    target = headTarget
                }
            case .hand(let part, let phalanx, let handSide):
                if let hand = pickHand(input.hands, side: handSide, body: joints, seen: seen), let seg = handSegment(part, phalanx: phalanx, hand: hand) {
                    target = seg
                } else if let seg = wristFallback(handSide, joint: joint) {
                    target = seg
                    mode = .fixed
                }
            case .guide, .pivot:
                continue
            }

            if layer.name.flags.contains(.front) && facingAway { placements.append(place(layer, transform: lastTransforms[layer.id] ?? .identity, visible: false, deltaTime: deltaTime)); continue }
            if layer.name.flags.contains(.back) && !facingAway { placements.append(place(layer, transform: lastTransforms[layer.id] ?? .identity, visible: false, deltaTime: deltaTime)); continue }

            if isStatic {
                placements.append(place(layer, transform: .identity, visible: true, deltaTime: deltaTime))
                continue
            }
            guard let target else {
                placements.append(place(layer, transform: lastTransforms[layer.id] ?? .identity, visible: false, deltaTime: deltaTime))
                continue
            }
            if layer.name.flags.contains(.stretch) { mode = .stretch }
            if layer.name.flags.contains(.fixed) { mode = .fixed }
            let axis = layer.axis(horizontal: horizontal)
            let mirror = facingAway && !layer.name.flags.contains(.noflip)
            let perpendicular: CGFloat? = {
                switch mode {
                case .uniform: return perpendicularScale.map { $0 * distance(target.0, target.1) / max(0.001, distance(axis.0, axis.1)) }
                case .stretch: return figureScale * (perpendicularScale ?? 1)
                case .fixed: return figureScale
                }
            }()
            let t = Self.transform(from: axis, to: target, mode: mode, perpendicular: perpendicular, fixedScale: figureScale, mirror: mirror)
            placements.append(place(layer, transform: t, visible: true, deltaTime: deltaTime))
        }
        return placements
    }

    private mutating func place(_ layer: CostumeLayer, transform: CGAffineTransform, visible: Bool, deltaTime: CGFloat) -> LayerPlacement {
        var opacity = opacities[layer.id] ?? 0
        let step = fadeSeconds <= 0 ? 1 : min(1, deltaTime / fadeSeconds)
        opacity = visible ? min(1, opacity + step) : max(0, opacity - step)
        opacities[layer.id] = opacity
        if visible { lastTransforms[layer.id] = transform }
        return LayerPlacement(layerID: layer.id, transform: visible ? transform : (lastTransforms[layer.id] ?? transform), opacity: opacity)
    }

    // MARK: - Segments

    enum Mode { case uniform, stretch, fixed }

    private func artTorsoLength(_ costume: Costume) -> CGFloat? {
        if let g = costume.guides["torso"] { return max(1, distance(g.0, g.1)) }
        if let torso = costume.layers(with: .bone(.torso, nil)).first {
            let a = torso.axis(horizontal: false)
            return max(1, distance(a.0, a.1))
        }
        return nil
    }

    private func boneSegment(_ bone: BodyBone, _ side: Side?, joint: (Int) -> CGPoint?, mid: (Int, Int) -> CGPoint?) -> (CGPoint, CGPoint)? {
        let left = side == .left
        switch bone {
        case .torso:
            guard let s = mid(BodyJoint.leftShoulder, BodyJoint.rightShoulder), let h = mid(BodyJoint.leftHip, BodyJoint.rightHip) else { return nil }
            return (s, h)
        case .shoulders:
            guard let l = joint(BodyJoint.leftShoulder), let r = joint(BodyJoint.rightShoulder) else { return nil }
            return (l, r)
        case .hips:
            guard let l = joint(BodyJoint.leftHip), let r = joint(BodyJoint.rightHip) else { return nil }
            return (l, r)
        case .neck:
            guard let s = mid(BodyJoint.leftShoulder, BodyJoint.rightShoulder) else { return nil }
            let head = mid(BodyJoint.leftEar, BodyJoint.rightEar) ?? mid(BodyJoint.leftEye, BodyJoint.rightEye) ?? joint(BodyJoint.nose)
            guard let head else { return nil }
            return (head, s)
        case .upperArm:
            guard let a = joint(left ? BodyJoint.leftShoulder : BodyJoint.rightShoulder), let b = joint(left ? BodyJoint.leftElbow : BodyJoint.rightElbow) else { return nil }
            return (a, b)
        case .forearm:
            guard let a = joint(left ? BodyJoint.leftElbow : BodyJoint.rightElbow), let b = joint(left ? BodyJoint.leftWrist : BodyJoint.rightWrist) else { return nil }
            return (a, b)
        case .hand:
            guard let e = joint(left ? BodyJoint.leftElbow : BodyJoint.rightElbow), let w = joint(left ? BodyJoint.leftWrist : BodyJoint.rightWrist) else { return nil }
            return (w, CGPoint(x: w.x + (w.x - e.x) * 0.45, y: w.y + (w.y - e.y) * 0.45))
        case .thigh:
            guard let a = joint(left ? BodyJoint.leftHip : BodyJoint.rightHip), let b = joint(left ? BodyJoint.leftKnee : BodyJoint.rightKnee) else { return nil }
            return (a, b)
        case .shin:
            guard let a = joint(left ? BodyJoint.leftKnee : BodyJoint.rightKnee), let b = joint(left ? BodyJoint.leftAnkle : BodyJoint.rightAnkle) else { return nil }
            return (a, b)
        case .foot:
            guard let k = joint(left ? BodyJoint.leftKnee : BodyJoint.rightKnee), let a = joint(left ? BodyJoint.leftAnkle : BodyJoint.rightAnkle) else { return nil }
            return (a, CGPoint(x: a.x + (a.x - k.x) * 0.3, y: a.y + (a.y - k.y) * 0.3))
        }
    }

    /// Left ear → right ear (or eyes widened, or a nose-sized default), oriented so the art's "up" is away from the shoulders.
    private func headSegment(joints: [CGPoint], seen: [Bool], face: RigFace?) -> (CGPoint, CGPoint)? {
        func j(_ i: Int) -> CGPoint? { seen.indices.contains(i) && seen[i] ? joints[i] : nil }
        if let l = j(BodyJoint.leftEar), let r = j(BodyJoint.rightEar) { return (l, r) }
        if let face, face.landmarks.count >= 76 {
            let contour = Array(face.landmarks[RigFace.contour])
            if let first = contour.first, let last = contour.last { return (first, last) }
        }
        if let l = j(BodyJoint.leftEye), let r = j(BodyJoint.rightEye) {
            let c = CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
            let dx = (l.x - r.x) * 1.4, dy = (l.y - r.y) * 1.4
            return (CGPoint(x: c.x + dx / 2, y: c.y + dy / 2), CGPoint(x: c.x - dx / 2, y: c.y - dy / 2))
        }
        if let n = j(BodyJoint.nose), let ls = j(BodyJoint.leftShoulder), let rs = j(BodyJoint.rightShoulder) {
            let w = distance(ls, rs) * 0.55
            let sign: CGFloat = ls.x >= rs.x ? 1 : -1
            return (CGPoint(x: n.x + sign * w / 2, y: n.y), CGPoint(x: n.x - sign * w / 2, y: n.y))
        }
        return nil
    }

    /// The extent of a landmark cluster along the eye line, as a left→right segment.
    private func faceSegment(_ part: FacePart, face: RigFace) -> (CGPoint, CGPoint)? {
        let lm = face.landmarks
        let range: Range<Int>
        switch part {
        case .leftEye: range = RigFace.leftEye
        case .rightEye: range = RigFace.rightEye
        case .leftBrow: range = RigFace.leftBrow
        case .rightBrow: range = RigFace.rightBrow
        case .nose: range = RigFace.nose
        case .mouth: range = RigFace.outerLips
        case .jaw, .face: range = RigFace.contour
        }
        let points = Array(lm[range])
        guard !points.isEmpty else { return nil }
        // Eye line direction from the pupils (left pupil → right pupil).
        let lp = lm[RigFace.leftPupil], rp = lm[RigFace.rightPupil]
        var ux = rp.x - lp.x, uy = rp.y - lp.y
        let len = sqrt(ux * ux + uy * uy)
        if len < 0.001 { ux = 1; uy = 0 } else { ux /= len; uy /= len }
        // Orient the segment the way the art reads (art left = person's left = image right when facing camera).
        // The art's horizontal axis runs from the art's left to its right; the person's left eye is on the art's left
        // when the art is drawn as seen from the front, so the segment runs left-pupil → right-pupil.
        let centre = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let c = CGPoint(x: centre.x / CGFloat(points.count), y: centre.y / CGFloat(points.count))
        var minP = CGFloat.greatestFiniteMagnitude, maxP = -CGFloat.greatestFiniteMagnitude
        for p in points {
            let proj = (p.x - c.x) * ux + (p.y - c.y) * uy
            minP = min(minP, proj); maxP = max(maxP, proj)
        }
        var half = max(maxP - minP, 1) / 2
        if part == .face { half *= 1.1 }
        // Pupil-to-pupil runs from the person's left to right, which is image right→left when facing the camera; the head
        // segment convention is left ear → right ear, so keep the same person-left → person-right order here.
        return (CGPoint(x: c.x - ux * half, y: c.y - uy * half), CGPoint(x: c.x + ux * half, y: c.y + uy * half))
    }

    private func pickHand(_ hands: [RigHand], side: HandSide, body: [CGPoint], seen: [Bool]) -> RigHand? {
        switch side {
        case .any: return hands.first
        case .left: return hands.first { $0.isLeft == true } ?? (hands.count == 1 && hands[0].isLeft == nil ? hands[0] : nil)
        case .right: return hands.first { $0.isLeft == false } ?? (hands.count == 1 && hands[0].isLeft == nil ? hands[0] : nil)
        }
    }

    private func handSegment(_ part: HandPart, phalanx: Int?, hand: RigHand) -> (CGPoint, CGPoint)? {
        guard hand.joints.count >= 21 else { return nil }
        func j(_ i: Int) -> CGPoint? { hand.visible.indices.contains(i) && hand.visible[i] ? hand.joints[i] : nil }
        let chain: [Int]
        switch part {
        case .palm:
            guard let w = j(0), let m = j(9) else { return nil }
            return (w, m)
        case .thumb: chain = [1, 2, 3, 4]
        case .index: chain = [5, 6, 7, 8]
        case .middle: chain = [9, 10, 11, 12]
        case .ring: chain = [13, 14, 15, 16]
        case .pinky: chain = [17, 18, 19, 20]
        }
        if let phalanx {
            let i = min(max(phalanx, 1), 3) - 1
            guard let a = j(chain[i]), let b = j(chain[i + 1]) else { return nil }
            return (a, b)
        }
        guard let a = j(chain[0]), let b = j(chain[3]) else { return nil }
        return (a, b)
    }

    private func wristFallback(_ side: HandSide, joint: (Int) -> CGPoint?) -> (CGPoint, CGPoint)? {
        let left = side != .right
        guard let e = joint(left ? BodyJoint.leftElbow : BodyJoint.rightElbow), let w = joint(left ? BodyJoint.leftWrist : BodyJoint.rightWrist) else { return nil }
        return (w, CGPoint(x: w.x + (w.x - e.x) * 0.5, y: w.y + (w.y - e.y) * 0.5))
    }

    // MARK: - Transform maths

    /// Maps art segment a onto target segment b: translate(−a0), rotate the art axis to +x, scale, rotate to the
    /// target's angle, translate(b0). `mirror` flips the perpendicular so the art reads from behind.
    static func transform(from a: (CGPoint, CGPoint), to b: (CGPoint, CGPoint), mode: Mode, perpendicular: CGFloat?, fixedScale: CGFloat = 1, mirror: Bool) -> CGAffineTransform {
        let artLength = max(0.001, distance(a.0, a.1))
        let targetLength = distance(b.0, b.1)
        let artAngle = atan2(a.1.y - a.0.y, a.1.x - a.0.x)
        let targetAngle = atan2(b.1.y - b.0.y, b.1.x - b.0.x)
        let along: CGFloat
        let across: CGFloat
        switch mode {
        case .uniform:
            along = targetLength / artLength
            across = perpendicular ?? along
        case .stretch:
            along = targetLength / artLength
            across = perpendicular ?? fixedScale
        case .fixed:
            along = fixedScale
            across = perpendicular ?? fixedScale
        }
        var t = CGAffineTransform(translationX: -a.0.x, y: -a.0.y)
        t = t.concatenating(CGAffineTransform(rotationAngle: -artAngle))
        t = t.concatenating(CGAffineTransform(scaleX: along, y: mirror ? -across : across))
        t = t.concatenating(CGAffineTransform(rotationAngle: targetAngle))
        t = t.concatenating(CGAffineTransform(translationX: b.0.x, y: b.0.y))
        return t
    }
}

@inline(__always)
func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x, dy = a.y - b.y
    return sqrt(dx * dx + dy * dy)
}
