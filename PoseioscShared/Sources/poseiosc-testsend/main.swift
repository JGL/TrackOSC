//
//  main.swift
//  poseiosc-testsend
//
//  Sends synthetic animated Poseiosc/VisionOSC frames over OSC so the macOS
//  receiver can be tested without an iPhone.
//
//  Usage: swift run poseiosc-testsend [--landscape] [host] [port]
//  Defaults: portrait frames to 127.0.0.1 9527
//

import Foundation
import PoseioscShared
import SwiftOSC

var arguments = Array(CommandLine.arguments.dropFirst())
let isLandscape = arguments.contains("--landscape")
arguments.removeAll { $0 == "--landscape" }
let host = arguments.count > 0 ? arguments[0] : "127.0.0.1"
let port = arguments.count > 1 ? UInt16(arguments[1]) ?? 9527 : 9527

// Mimics the sender's 720p capture: portrait 720x1280, landscape 1280x720.
let frameWidth: Int32 = isLandscape ? 1280 : 720
let frameHeight: Int32 = isLandscape ? 720 : 1280
let cameraInfo = CameraInfo(
    width: frameWidth, height: frameHeight,
    orientationDegrees: isLandscape ? 0 : 90,
    facing: 1
)
let fps = 30.0

let client = OSCUDPClient()
do {
    try client.start()
} catch {
    FileHandle.standardError.write("Failed to start OSC client: \(error)\n".data(using: .utf8)!)
    exit(1)
}

print("poseiosc-testsend → \(host):\(port) at \(Int(fps)) fps, \(frameWidth)x\(frameHeight) \(cameraInfo.orientationName) (Ctrl-C to stop)")

/// A stick figure whose limbs sway with sine waves, roughly centered in frame.
func syntheticPose(time t: Double) -> PoseDetection {
    let w = Float(frameWidth), h = Float(frameHeight)
    let cx = w / 2 + sinf(Float(t) * 0.7) * w * 0.1
    let sway = sinf(Float(t) * 2) * 60
    let step = sinf(Float(t) * 4) * 80

    func p(_ x: Float, _ y: Float) -> WirePoint { WirePoint(x: x, y: y, confidence: 0.9) }

    let headY = h * 0.2
    let shoulderY = h * 0.32
    let hipY = h * 0.55
    let kneeY = h * 0.72
    let ankleY = h * 0.9

    return PoseDetection(confidence: 0.95, joints: [
        p(cx, headY),                        // nose
        p(cx - 25, headY - 15),              // leftEye
        p(cx + 25, headY - 15),              // rightEye
        p(cx - 50, headY),                   // leftEar
        p(cx + 50, headY),                   // rightEar
        p(cx - 110, shoulderY),              // leftShoulder
        p(cx + 110, shoulderY),              // rightShoulder
        p(cx - 150 - sway, shoulderY + 180), // leftElbow
        p(cx + 150 + sway, shoulderY + 180), // rightElbow
        p(cx - 170 - sway * 1.5, shoulderY + 360), // leftWrist
        p(cx + 170 + sway * 1.5, shoulderY + 360), // rightWrist
        p(cx - 80, hipY),                    // leftHip
        p(cx + 80, hipY),                    // rightHip
        p(cx - 90 - step, kneeY),            // leftKnee
        p(cx + 90 + step, kneeY),            // rightKnee
        p(cx - 95 - step, ankleY),           // leftAnkle
        p(cx + 95 + step, ankleY)            // rightAnkle
    ])
}

/// A waving hand: wrist fixed, fingers fanning with time.
func syntheticHand(time t: Double) -> HandDetection {
    let w = Float(frameWidth), h = Float(frameHeight)
    let wristX = w * 0.75, wristY = h * 0.45
    let wave = sinf(Float(t) * 3) * 0.3

    var joints: [WirePoint] = [WirePoint(x: wristX, y: wristY, confidence: 0.9)]
    for finger in 0..<5 {
        let baseAngle = -Float.pi / 2 + (Float(finger) - 2) * (0.28 + wave * 0.15)
        for segment in 1...4 {
            let radius = Float(segment) * 45
            joints.append(WirePoint(
                x: wristX + cosf(baseAngle) * radius,
                y: wristY + sinf(baseAngle) * radius,
                confidence: 0.85
            ))
        }
    }
    return HandDetection(confidence: 0.9, joints: joints)
}

/// A ring of 76 points bobbing around a face center, so the receiver has
/// something plausible to draw.
func syntheticFace(time t: Double) -> FaceDetection {
    let w = Float(frameWidth), h = Float(frameHeight)
    let cx = w * 0.3, cy = h * 0.25 + sinf(Float(t)) * 30
    var points: [WirePoint] = []
    for i in 0..<WireCounts.facePoints {
        let angle = Float(i) / Float(WireCounts.facePoints) * 2 * .pi
        let radius: Float = 90 + sinf(angle * 3 + Float(t) * 2) * 12
        points.append(WirePoint(
            x: cx + cosf(angle) * radius,
            y: cy + sinf(angle) * radius * 1.3,
            confidence: 0.8
        ))
    }
    return FaceDetection(confidence: 0.92, points: points)
}

/// The synthetic face's boundary: a box hugging the same ellipse as
/// syntheticFace (so box, contour, and landmark ring coincide on screen),
/// with an animated roll.
func syntheticFaceBox(time t: Double) -> FaceBoxDetection {
    let w = Float(frameWidth), h = Float(frameHeight)
    let cx = w * 0.3, cy = h * 0.25 + sinf(Float(t)) * 30
    let radiusX: Float = 102, radiusY: Float = 102 * 1.3  // max landmark radius (90 + 12)
    return FaceBoxDetection(
        confidence: 0.92,
        box: WireRect(left: cx - radiusX, top: cy - radiusY, width: radiusX * 2, height: radiusY * 2),
        rollDegrees: sinf(Float(t)) * 20,
        yawDegrees: cosf(Float(t) * 0.5) * 15,
        pitchDegrees: 0
    )
}

/// The synthetic face's jawline: an open 17-point arc across the lower half
/// of the same ellipse, ear → chin → ear.
func syntheticFaceContour(time t: Double) -> FaceContourDetection {
    let w = Float(frameWidth), h = Float(frameHeight)
    let cx = w * 0.3, cy = h * 0.25 + sinf(Float(t)) * 30
    let pointCount = 17
    let points = (0..<pointCount).map { i -> WireXY in
        // Sweep 0…π (left ear to right ear through the chin, y down).
        let angle = Float(i) / Float(pointCount - 1) * .pi
        return WireXY(
            x: cx + cosf(angle) * 95,
            y: cy + sinf(angle) * 95 * 1.3
        )
    }
    return FaceContourDetection(confidence: 0.92, points: points)
}

func syntheticText(time t: Double) -> BoxDetection {
    let w = Float(frameWidth), h = Float(frameHeight)
    return BoxDetection(
        confidence: 0.88,
        box: WireRect(
            left: w * 0.1 + sinf(Float(t) * 0.5) * w * 0.05,
            top: h * 0.65,
            width: w * 0.35,
            height: h * 0.05
        ),
        label: "HELLO"
    )
}

func syntheticAnimal(time t: Double) -> BoxDetection {
    let w = Float(frameWidth), h = Float(frameHeight)
    return BoxDetection(
        confidence: 0.8,
        box: WireRect(
            left: w * 0.55 + cosf(Float(t) * 0.8) * w * 0.08,
            top: h * 0.75,
            width: w * 0.3,
            height: h * 0.15
        ),
        label: "Cat"
    )
}

/// A 1.75 m figure walking on the spot about 2 m from the camera, in metres
/// (Vision camera-relative space: x right, y up), with each joint's pixel
/// projection computed by a simple pinhole model so the 2D and 3D pictures
/// agree. The sign of z is provisional until confirmed on device.
func syntheticPose3D(time t: Double) -> Pose3DDetection {
    let w = Float(frameWidth), h = Float(frameHeight)
    let tf = Float(t)
    let drift = sinf(tf * 0.5) * 0.4          // sway left/right
    let swing = sinf(tf * 4) * 0.15           // arm/leg swing along z
    let distance: Float = 2.0                 // metres from the camera
    let focal = h * 0.7                       // pinhole focal length in pixels
    let ry: Float = -0.2                      // root (hip) height relative to the camera

    func j(_ x: Float, _ y: Float, _ dz: Float = 0) -> WirePoint3D {
        let z = distance + dz
        return WirePoint3D(x: x, y: y, z: z, px: w / 2 + x * focal / z, py: h / 2 - y * focal / z)
    }

    return Pose3DDetection(confidence: 0.93, bodyHeight: 1.75, joints: [
        j(drift, ry),                                   // root
        j(drift, ry + 0.25),                            // spine
        j(drift, ry + 0.50),                            // centerShoulder
        j(drift, ry + 0.65),                            // centerHead
        j(drift, ry + 0.78),                            // topHead
        j(drift - 0.20, ry + 0.50),                     // leftShoulder
        j(drift - 0.25, ry + 0.25, swing),              // leftElbow
        j(drift - 0.28, ry, swing * 2),                 // leftWrist
        j(drift + 0.20, ry + 0.50),                     // rightShoulder
        j(drift + 0.25, ry + 0.25, -swing),             // rightElbow
        j(drift + 0.28, ry, -swing * 2),                // rightWrist
        j(drift - 0.10, ry),                            // leftHip
        j(drift - 0.12, ry - 0.45, -swing),             // leftKnee
        j(drift - 0.12, ry - 0.90, -swing * 1.5),       // leftAnkle
        j(drift + 0.10, ry),                            // rightHip
        j(drift + 0.12, ry - 0.45, swing),              // rightKnee
        j(drift + 0.12, ry - 0.90, swing * 1.5)         // rightAnkle
    ])
}

/// A QR code held in the lower-right quarter, rocking gently so the corner
/// order (TL, TR, BR, BL) is visible on screen.
func syntheticBarcode(time t: Double) -> BarcodeDetection {
    let w = Float(frameWidth), h = Float(frameHeight)
    let cx = w * 0.62, cy = h * 0.58
    let half: Float = 90
    let angle = sinf(Float(t) * 0.8) * 0.2
    func corner(_ dx: Float, _ dy: Float) -> WireXY {
        WireXY(
            x: cx + dx * cosf(angle) - dy * sinf(angle),
            y: cy + dx * sinf(angle) + dy * cosf(angle)
        )
    }
    let corners = [corner(-half, -half), corner(half, -half), corner(half, half), corner(-half, half)]
    let xs = corners.map(\.x), ys = corners.map(\.y)
    return BarcodeDetection(
        confidence: 1.0,
        box: WireRect(left: xs.min()!, top: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!),
        corners: corners,
        symbology: "QR",
        payload: "https://github.com/JGL/TrackOSC"
    )
}

/// A side-view quadruped in the lower-right, legs stepping and tail wagging,
/// with one joint (the far eye) missing to exercise the sentinel.
func syntheticAnimalPose(time t: Double) -> AnimalPoseDetection {
    let w = Float(frameWidth), h = Float(frameHeight)
    let cx = w * 0.7 + cosf(Float(t) * 0.8) * w * 0.08, cy = h * 0.82
    let step = sinf(Float(t) * 4) * 18
    let wag = sinf(Float(t) * 6) * 12
    func p(_ x: Float, _ y: Float) -> WirePoint { WirePoint(x: cx + x, y: cy + y, confidence: 0.85) }
    let missing = WirePoint.missing(frameHeight: h)

    return AnimalPoseDetection(confidence: 0.88, joints: [
        p(110, -40),                 // nose
        p(85, -60),                  // leftEye
        missing,                     // rightEye (occluded in side view)
        p(60, -95), p(65, -80), p(70, -65),     // leftEarTop/Middle/Bottom
        p(48, -92), p(53, -78), p(58, -64),     // rightEarTop/Middle/Bottom
        p(50, -40),                  // neck
        p(45, 5), p(45 + step, 40), p(45 + step * 1.5, 75),          // left front leg
        p(57, 5), p(57 - step, 40), p(57 - step * 1.5, 75),          // right front leg
        p(-55, 5), p(-55 - step, 40), p(-55 - step * 1.5, 75),       // left back leg
        p(-43, 5), p(-43 + step, 40), p(-43 + step * 1.5, 75),       // right back leg
        p(-80, -30), p(-115, -45 + wag), p(-145, -40 + wag * 2)      // tailTop/Middle/Bottom
    ])
}

/// A whole-body box hugging the synthetic 2D pose.
func syntheticHuman(time t: Double) -> HumanDetection {
    let joints = syntheticPose(time: t).joints
    let xs = joints.map(\.x), ys = joints.map(\.y)
    let margin: Float = 40
    return HumanDetection(
        confidence: 0.97,
        box: WireRect(
            left: xs.min()! - margin,
            top: ys.min()! - margin,
            width: xs.max()! - xs.min()! + margin * 2,
            height: ys.max()! - ys.min()! + margin * 2
        )
    )
}

let start = Date()
while true {
    let t = Date().timeIntervalSince(start)
    let messages: [OSCMessage] = [
        WireCodec.encodeCameraInfo(cameraInfo),
        WireCodec.encodePoses(DetectionFrame(width: frameWidth, height: frameHeight, detections: [syntheticPose(time: t)])),
        WireCodec.encodeHands(DetectionFrame(width: frameWidth, height: frameHeight, detections: [syntheticHand(time: t)])),
        WireCodec.encodeFaces(DetectionFrame(width: frameWidth, height: frameHeight, detections: [syntheticFace(time: t)])),
        WireCodec.encodeFaceBoxes(DetectionFrame(width: frameWidth, height: frameHeight, detections: [syntheticFaceBox(time: t)])),
        WireCodec.encodeFaceContours(DetectionFrame(width: frameWidth, height: frameHeight, detections: [syntheticFaceContour(time: t)])),
        WireCodec.encodeTexts(DetectionFrame(width: frameWidth, height: frameHeight, detections: [syntheticText(time: t)])),
        WireCodec.encodeAnimals(DetectionFrame(width: frameWidth, height: frameHeight, detections: [syntheticAnimal(time: t)])),
        WireCodec.encodePoses3D(DetectionFrame(width: frameWidth, height: frameHeight, detections: [syntheticPose3D(time: t)])),
        WireCodec.encodeBarcodes(DetectionFrame(width: frameWidth, height: frameHeight, detections: [syntheticBarcode(time: t)])),
        WireCodec.encodeAnimalPoses(DetectionFrame(width: frameWidth, height: frameHeight, detections: [syntheticAnimalPose(time: t)])),
        WireCodec.encodeHumans(DetectionFrame(width: frameWidth, height: frameHeight, detections: [syntheticHuman(time: t)]))
    ]
    for message in messages {
        do {
            try client.send(message, to: host, port: port)
        } catch {
            FileHandle.standardError.write("send failed: \(error)\n".data(using: .utf8)!)
        }
    }
    Thread.sleep(forTimeInterval: 1.0 / fps)
}
