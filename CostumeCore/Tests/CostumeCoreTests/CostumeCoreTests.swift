//
//  CostumeCoreTests.swift
//  CostumeCoreTests
//
//  Parser fixtures in the shapes Illustrator, Inkscape, Figma and Affinity
//  export, the path grammar, the layer grammar and the rig maths.
//

import CoreGraphics
import Foundation
import Testing
@testable import CostumeCore

// MARK: - Fixtures

let illustratorSVG = """
<?xml version="1.0" encoding="utf-8"?>
<!-- Generator: Adobe Illustrator 28.0.0, SVG Export Plug-In -->
<svg version="1.1" id="Layer_1" xmlns="http://www.w3.org/2000/svg" x="0px" y="0px" viewBox="0 0 200 400" style="enable-background:new 0 0 200 400;" xml:space="preserve">
<style type="text/css">
	.st0{fill:#E53935;stroke:#000000;stroke-width:2;}
	.st1{fill:none;stroke:#1E88E5;stroke-width:4;stroke-linecap:round;}
	.st2{fill:#43A047;}
</style>
<g id="bone_x3A_torso">
	<rect x="70" y="100" class="st0" width="60" height="120"/>
</g>
<g id="bone_x3A_upperArm_x3A_left_1_">
	<path class="st2" d="M60,100h20v80H60z"/>
	<line id="pivot" class="st1" x1="70" y1="100" x2="70" y2="180"/>
</g>
<g id="head">
	<circle class="st2" cx="100" cy="60" r="40"/>
</g>
<g id="guide_x3A_shoulders" style="display:none;">
	<line x1="60" y1="100" x2="140" y2="100"/>
</g>
<g id="Backdrop">
	<rect x="0" y="380" width="200" height="20" style="fill:#888"/>
</g>
</svg>
"""

let inkscapeSVG = """
<svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd" width="100mm" height="200mm" viewBox="0 0 100 200">
  <sodipodi:namedview id="namedview1" pagecolor="#ffffff"/>
  <defs id="defs1"><linearGradient id="grad"><stop offset="0"/></linearGradient></defs>
  <g inkscape:groupmode="layer" id="layer1" inkscape:label="bone:forearm:right.stretch" transform="translate(10,20)">
    <path style="fill:#ff0000;stroke:none" d="m 0,0 10,0 0,40 -10,0 z" id="path1"/>
    <path inkscape:label="pivot" d="M 5,0 5,40" id="path2"/>
  </g>
  <g inkscape:groupmode="layer" id="layer2" inkscape:label="face:mouth">
    <ellipse cx="50" cy="30" rx="8" ry="3" style="fill:rgb(255, 128, 0)"/>
  </g>
  <g inkscape:groupmode="layer" id="layer3" inkscape:label="Hidden thing" style="display:none">
    <rect x="0" y="0" width="5" height="5"/>
  </g>
  <use href="#path1" x="10"/>
</svg>
"""

let figmaSVG = """
<svg width="300" height="600" viewBox="0 0 300 600" fill="none" xmlns="http://www.w3.org/2000/svg">
<g id="hand:index:2:left">
<path d="M10 10C20 0 30 0 40 10L40 30A10 10 0 0 1 20 30Z" fill="#00FF00" fill-opacity="0.5"/>
</g>
<g id="bone:thigh:right" transform="rotate(90 150 300) scale(2)">
<rect x="0" y="0" width="10" height="50" fill="blue" stroke="black" stroke-width="1"/>
</g>
<g id="face:leftEye.noflip">
<circle cx="120" cy="80" r="6" fill="#123456AA"/>
</g>
</svg>
"""

let affinitySVG = """
<svg xmlns="http://www.w3.org/2000/svg" xmlns:serif="http://www.serif.com/" viewBox="0 0 400 400" xml:space="preserve" style="fill-rule:evenodd;">
  <g id="Bone-torso" serif:id="bone:torso">
    <path d="M100,100L300,100L300,300L100,300Z" style="fill:rgb(255,0,0);"/>
  </g>
  <g serif:id="hand:palm:right">
    <polygon points="10,10 30,10 30,30 10,30" style="fill:#0f0"/>
  </g>
</svg>
"""

func costume(_ svg: String, name: String = "test") throws -> Costume {
    Costume(name: name, document: try SVGParser.parse(data: Data(svg.utf8)))
}

@Suite("SVG parsing")
struct ParserTests {
    @Test func illustratorLayersClassesAndEscapes() throws {
        let c = try costume(illustratorSVG)
        #expect(c.document.viewBox == CGRect(x: 0, y: 0, width: 200, height: 400))
        let roles = c.layers.map(\.name.role)
        #expect(roles.contains(.bone(.torso, nil)))
        #expect(roles.contains(.bone(.upperArm, .left)))
        #expect(roles.contains(.head))
        #expect(roles.contains(.scenery))
        // The hidden guide still counts (guides are never drawn anyway).
        #expect(c.guides["shoulders"] != nil)
        let torso = try #require(c.layers(with: .bone(.torso, nil)).first)
        #expect(torso.shapes.count == 1)
        #expect(torso.shapes[0].style.fill == SVGColor(red: 0xE5 / 255, green: 0x39 / 255, blue: 0x35 / 255))
        #expect(torso.shapes[0].style.stroke == .black)
        #expect(torso.shapes[0].style.strokeWidth == 2)
        #expect(torso.boundingBox == CGRect(x: 70, y: 100, width: 60, height: 120))
        let arm = try #require(c.layers(with: .bone(.upperArm, .left)).first)
        #expect(arm.pivot?.0 == CGPoint(x: 70, y: 100))
        #expect(arm.pivot?.1 == CGPoint(x: 70, y: 180))
        #expect(arm.shapes.count == 1)   // the pivot is not drawn
        #expect(c.warnings.isEmpty, "\(c.warnings)")
    }

    @Test func inkscapeLabelsTransformsAndWarnings() throws {
        let c = try costume(inkscapeSVG)
        let forearm = try #require(c.layers(with: .bone(.forearm, .right)).first)
        #expect(forearm.name.flags.contains(.stretch))
        // translate(10,20) baked in: the rect runs x 10…20, y 20…60.
        #expect(forearm.boundingBox == CGRect(x: 10, y: 20, width: 10, height: 40))
        #expect(forearm.pivot?.0 == CGPoint(x: 15, y: 20))
        #expect(forearm.pivot?.1 == CGPoint(x: 15, y: 60))
        let mouth = try #require(c.layers(with: .face(.mouth)).first)
        #expect(mouth.shapes[0].style.fill == SVGColor(red: 1, green: 128 / 255, blue: 0))
        #expect(!c.layers.contains { $0.label == "Hidden thing" })
        #expect(c.warnings.contains { $0.contains("<use>") })
        #expect(!c.warnings.contains { $0.contains("linearGradient") })   // inside <defs>, silently skipped
    }

    @Test func figmaIDsArcsAndRotatedTransforms() throws {
        let c = try costume(figmaSVG)
        let finger = try #require(c.layers.first { $0.name.role == .hand(.index, phalanx: 2, .left) })
        #expect(finger.shapes[0].style.fillOpacity == 0.5)
        let box = finger.boundingBox
        #expect(abs(box.minX - 10) < 0.01 && abs(box.maxX - 40) < 0.01)
        #expect(box.maxY > 30)   // the arc bulges below y = 30
        let thigh = try #require(c.layers(with: .bone(.thigh, .right)).first)
        // rotate(90 about 150,300) then scale(2): the 10×50 rect becomes 100 wide and 20 tall.
        #expect(abs(thigh.boundingBox.width - 100) < 0.01)
        #expect(abs(thigh.boundingBox.height - 20) < 0.01)
        #expect(abs(thigh.shapes[0].style.strokeWidth - 2) < 0.01)
        let eye = try #require(c.layers(with: .face(.leftEye)).first)
        #expect(eye.name.flags.contains(.noflip))
        #expect(abs((eye.shapes[0].style.fill?.alpha ?? 0) - 0xAA / 255) < 0.01)
    }

    @Test func styleInsideDefsStillApplies() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <defs><style>.bone{fill:#f5f5f0;stroke:#263238}</style><linearGradient id="g"/></defs>
          <g data-name="head"><circle class="bone" cx="5" cy="5" r="4"/></g>
        </svg>
        """
        let c = try costume(svg)
        let head = try #require(c.layers(with: .head).first)
        #expect(head.shapes[0].style.fill == SVGColor(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF0 / 255))
        #expect(head.shapes[0].style.stroke != nil)
        #expect(c.warnings.isEmpty)
    }

    @Test func affinitySerifIDsAndEvenOdd() throws {
        let c = try costume(affinitySVG)
        #expect(c.layers(with: .bone(.torso, nil)).count == 1)
        #expect(c.layers.contains { $0.name.role == .hand(.palm, phalanx: nil, .right) })
        #expect(c.layers[0].shapes[0].style.fillRule == .evenOdd)
    }

    @Test func pathGrammar() throws {
        // Relative commands, implicit repeats, H/V, S reflection, quadratic, arc flags without separators.
        let p = try #require(SVGPath.parse("M10 10 l10 0 0 10 h-10 v-10 z m20 0 c0 5 5 5 5 0 s5-5 5 0 q5 5 10 0 t10 0 a5 5 0 01 10 0"))
        let b = p.boundingBoxOfPath
        #expect(abs(b.minX - 10) < 0.01)
        #expect(abs(b.maxX - 70) < 0.01)
        #expect(SVGPath.parse("") == nil)
        #expect(SVGPath.parse("garbage") == nil)
        let arc = try #require(SVGPath.parse("M0 0 A10 10 0 0 0 20 0"))
        let ab = arc.boundingBoxOfPath
        #expect(abs(ab.width - 20) < 0.05)
        #expect(abs(ab.height - 10) < 0.1)   // a semicircle
    }

    @Test func transformsAndColours() {
        let t = SVGTransform.parse("translate(10, 20) scale(2)")
        let p = CGPoint(x: 1, y: 1).applying(t)
        #expect(p == CGPoint(x: 12, y: 22))
        let r = SVGTransform.parse("rotate(90)")
        let q = CGPoint(x: 1, y: 0).applying(r)
        #expect(abs(q.x) < 0.001 && abs(q.y - 1) < 0.001)
        #expect(SVGColorParser.parse("#abc") == .some(SVGColor(red: 0xAA / 255, green: 0xBB / 255, blue: 0xCC / 255)))
        #expect(SVGColorParser.parse("none") == .some(nil))
        #expect(SVGColorParser.parse("url(#grad)") == nil)
        #expect(SVGColorParser.parse("rgba(0, 0, 255, 0.5)") == .some(SVGColor(red: 0, green: 0, blue: 1, alpha: 0.5)))
        #expect(SVGColorParser.parse("Orange") == .some(SVGColor(red: 1, green: 165 / 255, blue: 0)))
    }
}

@Suite("Layer names")
struct LayerNameTests {
    @Test func grammar() {
        #expect(LayerName.parse("bone:upperArm:left")?.role == .bone(.upperArm, .left))
        #expect(LayerName.parse("Bone:Upper Arm:L")?.role == .bone(.upperArm, .left))
        #expect(LayerName.parse("bone:torso:left")?.role == .bone(.torso, nil))
        #expect(LayerName.parse("bone:forearm:right.stretch.noflip")?.flags == [.stretch, .noflip])
        #expect(LayerName.parse("head")?.role == .head)
        #expect(LayerName.parse("face:mouth")?.role == .face(.mouth))
        #expect(LayerName.parse("face")?.role == .face(.face))
        #expect(LayerName.parse("hand:index:2:left")?.role == .hand(.index, phalanx: 2, .left))
        #expect(LayerName.parse("hand:thumb")?.role == .hand(.thumb, phalanx: nil, .any))
        #expect(LayerName.parse("hand:palm:right")?.role == .hand(.palm, phalanx: nil, .right))
        #expect(LayerName.parse("guide:torso")?.role == .guide("torso"))
        #expect(LayerName.parse("pivot")?.role == .pivot)
        #expect(LayerName.parse("Layer 1") == nil)
        #expect(LayerName.parse("bone:wing") == nil)
        #expect(SVGParser.unescapeIllustrator("bone_x3A_upperArm_x3A_left_1_") == "bone:upperArm:left")
        #expect(SVGParser.unescapeIllustrator("face_x3A_mouth_x2E_stretch") == "face:mouth.stretch")
    }
}

@Suite("Rig")
struct RigTests {
    /// A figure standing in a 1000×1000 stage, facing the camera (left shoulder on the image's right).
    static func standing() -> RigInput {
        var j = [CGPoint](repeating: .zero, count: 17)
        j[BodyJoint.nose] = CGPoint(x: 500, y: 200)
        j[BodyJoint.leftEye] = CGPoint(x: 515, y: 190); j[BodyJoint.rightEye] = CGPoint(x: 485, y: 190)
        j[BodyJoint.leftEar] = CGPoint(x: 540, y: 200); j[BodyJoint.rightEar] = CGPoint(x: 460, y: 200)
        j[BodyJoint.leftShoulder] = CGPoint(x: 600, y: 300); j[BodyJoint.rightShoulder] = CGPoint(x: 400, y: 300)
        j[BodyJoint.leftElbow] = CGPoint(x: 650, y: 420); j[BodyJoint.rightElbow] = CGPoint(x: 350, y: 420)
        j[BodyJoint.leftWrist] = CGPoint(x: 680, y: 540); j[BodyJoint.rightWrist] = CGPoint(x: 320, y: 540)
        j[BodyJoint.leftHip] = CGPoint(x: 560, y: 540); j[BodyJoint.rightHip] = CGPoint(x: 440, y: 540)
        j[BodyJoint.leftKnee] = CGPoint(x: 570, y: 720); j[BodyJoint.rightKnee] = CGPoint(x: 430, y: 720)
        j[BodyJoint.leftAnkle] = CGPoint(x: 575, y: 900); j[BodyJoint.rightAnkle] = CGPoint(x: 425, y: 900)
        return RigInput(body: j, bodyVisible: Array(repeating: true, count: 17))
    }

    func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 0.5) -> Bool { abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance }

    @Test func boneAxisLandsOnTheJoints() throws {
        let c = try costume(illustratorSVG)
        var rig = Rig()
        let input = Self.standing()
        let placements = rig.solve(costume: c, input: input, deltaTime: 1)
        let torso = try #require(c.layers(with: .bone(.torso, nil)).first)
        let p = try #require(placements.first { $0.layerID == torso.id })
        #expect(p.opacity == 1)
        // Art axis: top-centre (100,100) → bottom-centre (100,220) maps onto shoulder mid → hip mid.
        #expect(near(CGPoint(x: 100, y: 100).applying(p.transform), CGPoint(x: 500, y: 300)))
        #expect(near(CGPoint(x: 100, y: 220).applying(p.transform), CGPoint(x: 500, y: 540)))
        // Uniform: the 60-wide box is scaled by 240/120 = 2.
        #expect(abs(distance(CGPoint(x: 70, y: 100).applying(p.transform), CGPoint(x: 130, y: 100).applying(p.transform)) - 120) < 0.5)
        // The arm uses its pivot.
        let arm = try #require(c.layers(with: .bone(.upperArm, .left)).first)
        let ap = try #require(placements.first { $0.layerID == arm.id })
        #expect(near(CGPoint(x: 70, y: 100).applying(ap.transform), input.body[BodyJoint.leftShoulder]))
        #expect(near(CGPoint(x: 70, y: 180).applying(ap.transform), input.body[BodyJoint.leftElbow]))
        // The head spans the ears.
        let head = try #require(c.layers(with: .head).first)
        let hp = try #require(placements.first { $0.layerID == head.id })
        #expect(near(CGPoint(x: 60, y: 60).applying(hp.transform), input.body[BodyJoint.leftEar]))
        #expect(near(CGPoint(x: 140, y: 60).applying(hp.transform), input.body[BodyJoint.rightEar]))
        // Facing the camera: no mirroring (positive determinant).
        #expect(hp.transform.a * hp.transform.d - hp.transform.b * hp.transform.c > 0)
        #expect(!rig.isFacingAway)
    }

    @Test func stretchKeepsWidthAtFigureScale() throws {
        let c = try costume(inkscapeSVG)
        var rig = Rig()
        // No torso layer or guide here: figure scale falls back to 1, so a stretched layer keeps its art width.
        let placements = rig.solve(costume: c, input: Self.standing(), deltaTime: 1)
        let forearm = try #require(c.layers(with: .bone(.forearm, .right)).first)
        let p = try #require(placements.first { $0.layerID == forearm.id })
        let a = CGPoint(x: 10, y: 20).applying(p.transform), b = CGPoint(x: 20, y: 20).applying(p.transform)
        #expect(abs(distance(a, b) - 10) < 0.5)   // across: unchanged
        let top = CGPoint(x: 15, y: 20).applying(p.transform), bottom = CGPoint(x: 15, y: 60).applying(p.transform)
        let input = Self.standing()
        #expect(near(top, input.body[BodyJoint.rightElbow]))
        #expect(near(bottom, input.body[BodyJoint.rightWrist]))
    }

    @Test func facingAwayMirrorsWithHysteresis() throws {
        let c = try costume(illustratorSVG)
        var rig = Rig()
        var input = Self.standing()
        _ = rig.solve(costume: c, input: input, deltaTime: 1)
        #expect(!rig.isFacingAway)
        // Swap the shoulders and everything else left/right: seen from behind.
        func swap(_ a: Int, _ b: Int) { input.body.swapAt(a, b) }
        swap(BodyJoint.leftShoulder, BodyJoint.rightShoulder); swap(BodyJoint.leftHip, BodyJoint.rightHip)
        swap(BodyJoint.leftEar, BodyJoint.rightEar); swap(BodyJoint.leftEye, BodyJoint.rightEye)
        let placements = rig.solve(costume: c, input: input, deltaTime: 1)
        #expect(rig.isFacingAway)
        let head = try #require(c.layers(with: .head).first)
        let hp = try #require(placements.first { $0.layerID == head.id })
        #expect(hp.transform.a * hp.transform.d - hp.transform.b * hp.transform.c < 0)
        // Sideways (shoulders nearly overlapping) keeps the last state.
        input.body[BodyJoint.leftShoulder] = CGPoint(x: 505, y: 300)
        input.body[BodyJoint.rightShoulder] = CGPoint(x: 495, y: 300)
        _ = rig.solve(costume: c, input: input, deltaTime: 1)
        #expect(rig.isFacingAway)
    }

    @Test func missingJointsFadeOutAndHold() throws {
        let c = try costume(illustratorSVG)
        var rig = Rig()
        rig.fadeSeconds = 0.5
        var input = Self.standing()
        _ = rig.solve(costume: c, input: input, deltaTime: 1)
        let arm = try #require(c.layers(with: .bone(.upperArm, .left)).first)
        input.bodyVisible[BodyJoint.leftElbow] = false
        let p1 = try #require(rig.solve(costume: c, input: input, deltaTime: 0.25).first { $0.layerID == arm.id })
        #expect(abs(p1.opacity - 0.5) < 0.01)
        #expect(near(CGPoint(x: 70, y: 100).applying(p1.transform), input.body[BodyJoint.leftShoulder]))   // held
        let p2 = try #require(rig.solve(costume: c, input: input, deltaTime: 0.25).first { $0.layerID == arm.id })
        #expect(p2.opacity == 0)
        #expect(!p2.isVisible)
        input.bodyVisible[BodyJoint.leftElbow] = true
        let p3 = try #require(rig.solve(costume: c, input: input, deltaTime: 0.5).first { $0.layerID == arm.id })
        #expect(p3.opacity == 1)
    }

    @Test func facePartsSitOnLandmarksAndFallBackToTheHead() throws {
        let c = try costume(inkscapeSVG)
        var rig = Rig()
        var input = Self.standing()
        // Synthetic landmarks: 76 points, lips around (500, 240) 40 wide, pupils level.
        var lm = [CGPoint](repeating: CGPoint(x: 500, y: 220), count: 76)
        lm[RigFace.leftPupil] = CGPoint(x: 520, y: 195); lm[RigFace.rightPupil] = CGPoint(x: 480, y: 195)
        for (n, i) in RigFace.outerLips.enumerated() {
            let a = CGFloat(n) / 14 * 2 * .pi
            lm[i] = CGPoint(x: 500 + cos(a) * 20, y: 240 + sin(a) * 8)
        }
        input.face = RigFace(landmarks: lm, rollDegrees: 0, mouthOpenness: 0.5)
        let placements = rig.solve(costume: c, input: input, deltaTime: 1)
        let mouth = try #require(c.layers(with: .face(.mouth)).first)
        let p = try #require(placements.first { $0.layerID == mouth.id })
        // The art ellipse (centre 50,30; 16 wide) is centred on the lips and 40 wide.
        #expect(near(CGPoint(x: 50, y: 30).applying(p.transform), CGPoint(x: 500, y: 240), 1))
        #expect(abs(distance(CGPoint(x: 42, y: 30).applying(p.transform), CGPoint(x: 58, y: 30).applying(p.transform)) - 40) < 1)
        // Opened mouth: taller than uniform.
        let uniformHeight: CGFloat = 6 * 40 / 16
        let height = distance(CGPoint(x: 50, y: 27).applying(p.transform), CGPoint(x: 50, y: 33).applying(p.transform))
        #expect(height > uniformHeight * 1.4)

        // Without landmarks and without a head layer, the mouth follows the head segment.
        input.face = nil
        var rig2 = Rig()
        let fallback = try #require(rig2.solve(costume: c, input: input, deltaTime: 1).first { $0.layerID == mouth.id })
        #expect(fallback.isVisible)
    }

    @Test func handsFollowFingersAndFallBackToTheWrist() throws {
        let c = try costume(figmaSVG)
        var rig = Rig()
        var input = Self.standing()
        let finger = try #require(c.layers.first { $0.name.role == .hand(.index, phalanx: 2, .left) })
        // Without hand data: at the left wrist (fixed mode).
        let fallback = try #require(rig.solve(costume: c, input: input, deltaTime: 1).first { $0.layerID == finger.id })
        let axis = finger.axis(horizontal: false)
        #expect(near(axis.0.applying(fallback.transform), input.body[BodyJoint.leftWrist], 1))
        // With a left hand: phalanx 2 of the index runs joint 6 → 7.
        var hj = [CGPoint](repeating: CGPoint(x: 680, y: 540), count: 21)
        hj[6] = CGPoint(x: 700, y: 560); hj[7] = CGPoint(x: 710, y: 580)
        input.hands = [RigHand(joints: hj, visible: Array(repeating: true, count: 21), isLeft: true)]
        let p = try #require(rig.solve(costume: c, input: input, deltaTime: 1).first { $0.layerID == finger.id })
        #expect(near(axis.0.applying(p.transform), hj[6], 1))
        #expect(near(axis.1.applying(p.transform), hj[7], 1))
    }

    @Test func rendererDrawsWithoutCrashing() throws {
        let c = try costume(illustratorSVG)
        var rig = Rig()
        let placements = rig.solve(costume: c, input: Self.standing(), deltaTime: 1)
        let ctx = try #require(CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        CostumeRenderer.draw(costume: c, placements: placements, base: CostumeRenderer.fit(viewBox: c.document.viewBox, into: CGRect(x: 0, y: 0, width: 200, height: 200)), in: ctx)
        let data = try #require(ctx.data)
        let bytes = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * 200)
        var painted = 0
        for i in stride(from: 3, to: ctx.bytesPerRow * 200, by: 4) where bytes[i] > 0 { painted += 1 }
        #expect(painted > 100)
    }
}
