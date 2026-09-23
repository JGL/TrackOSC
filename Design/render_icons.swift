// Renders every TrackOSC app icon: a pose skeleton with OSC arcs.
//
// Usage: swift render_icons.swift <outputDir> [icon names…]
//
// Icon names (all when none are given):
//   receiver, sender-mac, sender-ios, recorder, speaker, router,
//   colours, particles, text, synth, costumes, costumes3d
//
// Every receiver-type app keeps the Receiver's figure and inbound arcs so
// the family reads as one; each gets its own background gradient and a
// small badge drawn with CG primitives in the lower-left corner (never
// SF Symbols, which may not be used in icons).

import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
let outputDir = arguments.first ?? "."
let requested = Set(arguments.dropFirst())
let size = 1024

let limbGreen = NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
let jointGreen = NSColor(calibratedRed: 0.55, green: 0.95, blue: 0.55, alpha: 1)
let arcCyan = NSColor(calibratedRed: 0.39, green: 0.82, blue: 1.0, alpha: 1)
let badgeWhite = NSColor(calibratedWhite: 1, alpha: 0.92)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
}

enum ArtMode {
    case sending    // arcs radiate outward from the raised hand
    case receiving  // arcs arrive from beyond the corner, with an inbound arrow
}

enum Badge {
    case none
    case speechBubble   // Speaker
    case recordDot      // Recorder
    case splitArrows    // Router
    case gradientBar    // Colours
    case dotSpray       // Particles
    case glyph          // Text
    case waveform       // Synth
    case mask           // Costumes
    case maskDepth      // 3D Costumes
}

enum Shape {
    case macSquircle    // Big Sur squircle with margin on a transparent canvas
    case iosSquare      // full bleed; iOS applies its own mask
}

struct IconSpec {
    let name: String
    let filename: String
    let top: NSColor
    let bottom: NSColor
    let mode: ArtMode
    let badge: Badge
    let shape: Shape
}

let receiverTop = rgb(0.05, 0.09, 0.13), receiverBottom = rgb(0.08, 0.19, 0.27)
let senderTop = rgb(0.09, 0.05, 0.15), senderBottom = rgb(0.21, 0.11, 0.32)

let specs: [IconSpec] = [
    IconSpec(name: "receiver", filename: "AppIcon-macOS-1024.png", top: receiverTop, bottom: receiverBottom, mode: .receiving, badge: .none, shape: .macSquircle),
    IconSpec(name: "sender-mac", filename: "AppIcon-macOS-sender-1024.png", top: senderTop, bottom: senderBottom, mode: .sending, badge: .none, shape: .macSquircle),
    IconSpec(name: "sender-ios", filename: "AppIcon-iOS-1024.png", top: senderTop, bottom: senderBottom, mode: .sending, badge: .none, shape: .iosSquare),
    IconSpec(name: "recorder", filename: "AppIcon-macOS-recorder-1024.png", top: rgb(0.14, 0.04, 0.06), bottom: rgb(0.42, 0.09, 0.14), mode: .receiving, badge: .recordDot, shape: .macSquircle),
    IconSpec(name: "speaker", filename: "AppIcon-macOS-speaker-1024.png", top: rgb(0.16, 0.09, 0.02), bottom: rgb(0.48, 0.28, 0.05), mode: .receiving, badge: .speechBubble, shape: .macSquircle),
    IconSpec(name: "router", filename: "AppIcon-macOS-router-1024.png", top: rgb(0.03, 0.12, 0.13), bottom: rgb(0.07, 0.30, 0.32), mode: .receiving, badge: .splitArrows, shape: .macSquircle),
    IconSpec(name: "colours", filename: "AppIcon-macOS-colours-1024.png", top: rgb(0.12, 0.05, 0.18), bottom: rgb(0.30, 0.12, 0.42), mode: .receiving, badge: .gradientBar, shape: .macSquircle),
    IconSpec(name: "particles", filename: "AppIcon-macOS-particles-1024.png", top: rgb(0.16, 0.04, 0.12), bottom: rgb(0.44, 0.10, 0.32), mode: .receiving, badge: .dotSpray, shape: .macSquircle),
    IconSpec(name: "text", filename: "AppIcon-macOS-text-1024.png", top: rgb(0.08, 0.09, 0.11), bottom: rgb(0.22, 0.25, 0.30), mode: .receiving, badge: .glyph, shape: .macSquircle),
    IconSpec(name: "synth", filename: "AppIcon-macOS-synth-1024.png", top: rgb(0.03, 0.05, 0.16), bottom: rgb(0.08, 0.13, 0.40), mode: .receiving, badge: .waveform, shape: .macSquircle),
    IconSpec(name: "costumes", filename: "AppIcon-macOS-costumes-1024.png", top: rgb(0.16, 0.11, 0.02), bottom: rgb(0.48, 0.34, 0.06), mode: .receiving, badge: .mask, shape: .macSquircle),
    IconSpec(name: "costumes3d", filename: "AppIcon-macOS-costumes3d-1024.png", top: rgb(0.15, 0.08, 0.03), bottom: rgb(0.44, 0.24, 0.10), mode: .receiving, badge: .maskDepth, shape: .macSquircle),
]

func makeContext(_ pixels: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Flip so design coordinates are top-left origin.
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: 1, y: -1)
    return ctx
}

func fillBackground(_ ctx: CGContext, rect: CGRect, rounded radius: CGFloat, top: NSColor, bottom: NSColor) {
    ctx.saveGState()
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [top.cgColor, bottom.cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.minY),
        end: CGPoint(x: rect.midX, y: rect.maxY),
        options: []
    )
    ctx.restoreGState()
}

/// Draws the figure + arcs. `rect` is where the 0-1024 design space lands.
func drawArt(_ ctx: CGContext, rect: CGRect, mode: ArtMode) {
    let s = rect.width / 1024.0
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
    }

    // Waving stick figure. Right arm raised toward the signal arcs.
    let neck = pt(430, 350)
    let lShoulder = pt(330, 395), rShoulder = pt(530, 380)
    let lElbow = pt(285, 545), rElbow = pt(625, 300)
    let lWrist = pt(262, 690), rWrist = pt(700, 185)
    let lHip = pt(370, 660), rHip = pt(495, 660)
    let lKnee = pt(330, 810), rKnee = pt(545, 805)
    let lAnkle = pt(315, 950), rAnkle = pt(590, 945)
    let headCenter = pt(430, 245)

    let limbs: [(CGPoint, CGPoint)] = [
        (neck, lShoulder), (neck, rShoulder),
        (lShoulder, lElbow), (lElbow, lWrist),
        (rShoulder, rElbow), (rElbow, rWrist),
        (lShoulder, lHip), (rShoulder, rHip), (lHip, rHip),
        (lHip, lKnee), (lKnee, lAnkle),
        (rHip, rKnee), (rKnee, rAnkle)
    ]

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    ctx.setStrokeColor(limbGreen.cgColor)
    ctx.setLineWidth(34 * s)
    for (a, b) in limbs {
        ctx.move(to: a)
        ctx.addLine(to: b)
    }
    ctx.strokePath()

    ctx.setLineWidth(34 * s)
    ctx.strokeEllipse(in: CGRect(
        x: headCenter.x - 68 * s, y: headCenter.y - 68 * s,
        width: 136 * s, height: 136 * s
    ))

    ctx.setFillColor(jointGreen.cgColor)
    let joints = [neck, lShoulder, rShoulder, lElbow, rElbow, lWrist, rWrist,
                  lHip, rHip, lKnee, rKnee, lAnkle, rAnkle]
    for joint in joints {
        let r = 27 * s
        ctx.fillEllipse(in: CGRect(x: joint.x - r, y: joint.y - r, width: r * 2, height: r * 2))
    }

    switch mode {
    case .sending:
        for (index, radius) in [95.0, 155.0, 215.0].enumerated() {
            ctx.setStrokeColor(arcCyan.withAlphaComponent(1.0 - CGFloat(index) * 0.28).cgColor)
            ctx.setLineWidth(26 * s)
            ctx.addArc(
                center: rWrist, radius: radius * s,
                startAngle: -0.25 * .pi, endAngle: -0.75 * .pi,
                clockwise: true
            )
            ctx.strokePath()
        }

    case .receiving:
        let source = pt(1050, -110)
        let towardWrist = atan2(rWrist.y - source.y, rWrist.x - source.x)
        for (index, radius) in [420.0, 340.0, 260.0].enumerated() {
            ctx.setStrokeColor(arcCyan.withAlphaComponent(0.44 + CGFloat(index) * 0.28).cgColor)
            ctx.setLineWidth(26 * s)
            ctx.addArc(
                center: source, radius: radius * s,
                startAngle: towardWrist - 0.22 * .pi,
                endAngle: towardWrist + 0.22 * .pi,
                clockwise: false
            )
            ctx.strokePath()
        }

        let tip = pt(760, 128)
        let tail = CGPoint(
            x: tip.x - cos(towardWrist) * 150 * s,
            y: tip.y - sin(towardWrist) * 150 * s
        )
        ctx.setStrokeColor(arcCyan.cgColor)
        ctx.setLineWidth(30 * s)
        ctx.move(to: tail)
        ctx.addLine(to: tip)
        for side in [towardWrist + .pi * 0.8, towardWrist - .pi * 0.8] {
            ctx.move(to: tip)
            ctx.addLine(to: CGPoint(
                x: tip.x + cos(side) * 62 * s,
                y: tip.y + sin(side) * 62 * s
            ))
        }
        ctx.strokePath()
    }
}

/// Draws the app badge in a 300×300 design-space box in the lower-left corner.
func drawBadge(_ ctx: CGContext, rect: CGRect, badge: Badge) {
    guard badge != .none else { return }
    let s = rect.width / 1024.0
    // Badge box: x 60…340, y 690…970 (the figure's left foot is at x≈315, y≈950,
    // so the badge sits just left of it and reads as a corner mark).
    let box = CGRect(x: rect.minX + 40 * s, y: rect.minY + 700 * s, width: 250 * s, height: 250 * s)
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: box.minX + x * box.width, y: box.minY + y * box.height)
    }
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(badgeWhite.cgColor)
    ctx.setFillColor(badgeWhite.cgColor)
    let stroke = 26 * s
    ctx.setLineWidth(stroke)

    switch badge {
    case .none:
        break

    case .recordDot:
        ctx.strokeEllipse(in: CGRect(x: p(0.1, 0.1).x, y: p(0.1, 0.1).y, width: box.width * 0.8, height: box.height * 0.8))
        ctx.setFillColor(rgb(0.95, 0.20, 0.25).cgColor)
        ctx.fillEllipse(in: CGRect(x: p(0.28, 0.28).x, y: p(0.28, 0.28).y, width: box.width * 0.44, height: box.height * 0.44))

    case .speechBubble:
        let bubble = CGRect(x: p(0.05, 0.1).x, y: p(0.05, 0.1).y, width: box.width * 0.9, height: box.height * 0.62)
        ctx.addPath(CGPath(roundedRect: bubble, cornerWidth: bubble.height * 0.35, cornerHeight: bubble.height * 0.35, transform: nil))
        ctx.move(to: p(0.25, 0.68))
        ctx.addLine(to: p(0.18, 0.95))
        ctx.addLine(to: p(0.48, 0.72))
        ctx.closePath()
        ctx.fillPath()
        // Three sound dots inside, in the background colour.
        ctx.setBlendMode(.destinationOut)
        for x in [0.3, 0.5, 0.7] {
            let c = p(CGFloat(x), 0.41)
            ctx.fillEllipse(in: CGRect(x: c.x - 16 * s, y: c.y - 16 * s, width: 32 * s, height: 32 * s))
        }
        ctx.setBlendMode(.normal)

    case .splitArrows:
        // One input from the left forking to three outputs.
        ctx.move(to: p(0.05, 0.5)); ctx.addLine(to: p(0.4, 0.5))
        for (y, endY) in [(0.5, 0.15), (0.5, 0.5), (0.5, 0.85)] {
            ctx.move(to: p(0.4, CGFloat(y)))
            ctx.addCurve(to: p(0.85, CGFloat(endY)), control1: p(0.62, CGFloat(y)), control2: p(0.62, CGFloat(endY)))
            ctx.move(to: p(0.85, CGFloat(endY)))
            ctx.addLine(to: p(0.72, CGFloat(endY) - 0.1))
            ctx.move(to: p(0.85, CGFloat(endY)))
            ctx.addLine(to: p(0.72, CGFloat(endY) + 0.1))
        }
        ctx.strokePath()

    case .gradientBar:
        let bar = CGRect(x: p(0.05, 0.3).x, y: p(0.05, 0.3).y, width: box.width * 0.9, height: box.height * 0.4)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: bar.height / 2, cornerHeight: bar.height / 2, transform: nil))
        ctx.clip()
        let colours = [rgb(1.0, 0.35, 0.35), rgb(1.0, 0.85, 0.25), rgb(0.35, 0.95, 0.55), rgb(0.35, 0.65, 1.0), rgb(0.85, 0.45, 1.0)]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colours.map(\.cgColor) as CFArray, locations: [0, 0.25, 0.5, 0.75, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: bar.minX, y: bar.midY), end: CGPoint(x: bar.maxX, y: bar.midY), options: [])
        ctx.restoreGState()

    case .dotSpray:
        // A fan of dots shrinking away from a source in the lower left.
        let dots: [(CGFloat, CGFloat, CGFloat)] = [
            (0.12, 0.88, 0.11), (0.32, 0.72, 0.09), (0.55, 0.60, 0.075), (0.78, 0.52, 0.06),
            (0.22, 0.52, 0.08), (0.42, 0.38, 0.065), (0.62, 0.26, 0.05), (0.80, 0.16, 0.04),
            (0.48, 0.80, 0.06), (0.70, 0.78, 0.045), (0.16, 0.24, 0.05), (0.90, 0.36, 0.035),
        ]
        for (x, y, r) in dots {
            let c = p(x, y)
            let radius = r * box.width
            ctx.fillEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }

    case .glyph:
        // A bold "A" drawn as strokes.
        ctx.setLineWidth(stroke * 1.4)
        ctx.move(to: p(0.12, 0.92)); ctx.addLine(to: p(0.5, 0.08)); ctx.addLine(to: p(0.88, 0.92))
        ctx.move(to: p(0.27, 0.62)); ctx.addLine(to: p(0.73, 0.62))
        ctx.strokePath()

    case .waveform:
        // A resonant saw-ish wave.
        ctx.move(to: p(0.04, 0.5))
        let points: [(CGFloat, CGFloat)] = [(0.14, 0.5), (0.22, 0.12), (0.3, 0.88), (0.38, 0.22), (0.46, 0.78), (0.54, 0.32), (0.62, 0.68), (0.70, 0.42), (0.78, 0.58), (0.86, 0.5), (0.96, 0.5)]
        for (x, y) in points { ctx.addLine(to: p(x, y)) }
        ctx.strokePath()

    case .mask, .maskDepth:
        // A theatre mask: rounded outline with two eye holes and a smile.
        func maskPath(offset: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let r = CGRect(x: p(0.1 + offset, 0.08 + offset).x, y: p(0.1 + offset, 0.08 + offset).y, width: box.width * 0.72, height: box.height * 0.84)
            path.addRoundedRect(in: r, cornerWidth: r.width * 0.45, cornerHeight: r.height * 0.3)
            return path
        }
        if badge == .maskDepth {
            ctx.saveGState()
            ctx.setStrokeColor(badgeWhite.withAlphaComponent(0.45).cgColor)
            ctx.addPath(maskPath(offset: 0.14))
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.addPath(maskPath(offset: 0))
        ctx.fillPath()
        ctx.setBlendMode(.destinationOut)
        for x in [0.31, 0.61] {
            let c = p(CGFloat(x), 0.38)
            ctx.fillEllipse(in: CGRect(x: c.x - 34 * s, y: c.y - 24 * s, width: 68 * s, height: 48 * s))
        }
        ctx.setLineWidth(stroke * 0.8)
        ctx.move(to: p(0.28, 0.62))
        ctx.addQuadCurve(to: p(0.64, 0.62), control: p(0.46, 0.84))
        ctx.strokePath()
        ctx.setBlendMode(.normal)
    }
    ctx.restoreGState()
}

func writePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

func render(_ spec: IconSpec) {
    let ctx = makeContext(size)
    switch spec.shape {
    case .macSquircle:
        let squircle = CGRect(x: 100, y: 100, width: 824, height: 824)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(spec.bottom.cgColor)
        ctx.addPath(CGPath(roundedRect: squircle, cornerWidth: 185, cornerHeight: 185, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        fillBackground(ctx, rect: squircle, rounded: 185, top: spec.top, bottom: spec.bottom)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: squircle, cornerWidth: 185, cornerHeight: 185, transform: nil))
        ctx.clip()
        let art = squircle.insetBy(dx: 30, dy: 30)
        drawArt(ctx, rect: art, mode: spec.mode)
        drawBadge(ctx, rect: art, badge: spec.badge)
        ctx.restoreGState()
    case .iosSquare:
        let full = CGRect(x: 0, y: 0, width: size, height: size)
        fillBackground(ctx, rect: full, rounded: 0, top: spec.top, bottom: spec.bottom)
        drawArt(ctx, rect: full, mode: spec.mode)
        drawBadge(ctx, rect: full, badge: spec.badge)
    }
    writePNG(ctx.makeImage()!, to: "\(outputDir)/\(spec.filename)")
}

for spec in specs where requested.isEmpty || requested.contains(spec.name) {
    render(spec)
}
