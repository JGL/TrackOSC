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
        WireCodec.encodeAnimals(DetectionFrame(width: frameWidth, height: frameHeight, detections: [syntheticAnimal(time: t)]))
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
