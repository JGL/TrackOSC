//
//  WireCodecTests.swift
//  PoseioscSharedTests
//

import Foundation
import Testing
import SwiftOSC
@testable import PoseioscShared

// MARK: - Fixtures

private func makePose(seed: Float) -> PoseDetection {
    PoseDetection(
        confidence: 0.9 + seed * 0.001,
        joints: (0..<WireCounts.bodyJoints).map { i in
            WirePoint(x: Float(i) * 10 + seed, y: Float(i) * 20 + seed, confidence: 0.5)
        }
    )
}

private func makeHand(seed: Float) -> HandDetection {
    HandDetection(
        confidence: 0.8,
        joints: (0..<WireCounts.handJoints).map { i in
            WirePoint(x: Float(i) + seed, y: Float(i) * 2 + seed, confidence: 0.7)
        }
    )
}

private func makeFace(seed: Float) -> FaceDetection {
    FaceDetection(
        confidence: 0.95,
        points: (0..<WireCounts.facePoints).map { i in
            WirePoint(x: Float(i) * 3 + seed, y: Float(i) * 4 + seed, confidence: 0.6)
        }
    )
}

private func makeBox(label: String) -> BoxDetection {
    BoxDetection(confidence: 0.85, box: WireRect(left: 12, top: 34, width: 56, height: 78), label: label)
}

private func makeFaceBox(seed: Float) -> FaceBoxDetection {
    FaceBoxDetection(
        confidence: 0.9,
        box: WireRect(left: 10 + seed, top: 20 + seed, width: 30, height: 40),
        rollDegrees: 5 + seed,
        yawDegrees: -10 + seed,
        pitchDegrees: 2 + seed
    )
}

private func makeFaceContour(seed: Float, pointCount: Int) -> FaceContourDetection {
    FaceContourDetection(
        confidence: 0.9,
        points: (0..<pointCount).map { i in
            WireXY(x: Float(i) * 5 + seed, y: Float(i) * 7 + seed)
        }
    )
}

private func makePose3D(seed: Float) -> Pose3DDetection {
    Pose3DDetection(
        confidence: 0.9 + seed * 0.001,
        bodyHeight: 1.7 + seed * 0.01,
        joints: (0..<WireCounts.body3DJoints).map { i in
            WirePoint3D(
                x: Float(i) * 0.1 + seed, y: Float(i) * 0.2 - seed, z: -2 + Float(i) * 0.01,
                px: Float(i) * 10 + seed, py: Float(i) * 20 + seed
            )
        }
    )
}

private func makeAnimalPose(seed: Float) -> AnimalPoseDetection {
    AnimalPoseDetection(
        confidence: 0.8,
        joints: (0..<WireCounts.animalJoints).map { i in
            // Every fifth joint is "missing", exercising the sentinel.
            i % 5 == 4
                ? WirePoint.missing(frameHeight: 1280)
                : WirePoint(x: Float(i) * 3 + seed, y: Float(i) * 4 + seed, confidence: 0.7)
        }
    )
}

private func makeHuman(seed: Float) -> HumanDetection {
    HumanDetection(confidence: 0.75, box: WireRect(left: 100 + seed, top: 200 + seed, width: 300, height: 400))
}

private func makeBarcode(payload: String, symbology: String = "QR") -> BarcodeDetection {
    BarcodeDetection(
        confidence: 0.99,
        box: WireRect(left: 10, top: 20, width: 30, height: 40),
        corners: [WireXY(x: 10, y: 20), WireXY(x: 40, y: 20), WireXY(x: 40, y: 60), WireXY(x: 10, y: 60)],
        symbology: symbology,
        payload: payload
    )
}

// MARK: - Round trips

@Suite("Round-trip encoding/decoding")
struct RoundTripTests {
    @Test func poses() throws {
        let frame = DetectionFrame(width: 1080, height: 1920, detections: [makePose(seed: 1), makePose(seed: 2)])
        let decoded = try WireCodec.decode(WireCodec.encodePoses(frame))
        guard case .poses(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func hands() throws {
        let frame = DetectionFrame(width: 640, height: 480, detections: [makeHand(seed: 5)])
        let decoded = try WireCodec.decode(WireCodec.encodeHands(frame))
        guard case .hands(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func faces() throws {
        let frame = DetectionFrame(width: 1920, height: 1080, detections: [makeFace(seed: 3)])
        let decoded = try WireCodec.decode(WireCodec.encodeFaces(frame))
        guard case .faces(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func texts() throws {
        let frame = DetectionFrame(width: 100, height: 200, detections: [makeBox(label: "HELLO WORLD")])
        let decoded = try WireCodec.decode(WireCodec.encodeTexts(frame))
        guard case .texts(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func animals() throws {
        let frame = DetectionFrame(width: 100, height: 200, detections: [makeBox(label: "Cat"), makeBox(label: "Dog")])
        let decoded = try WireCodec.decode(WireCodec.encodeAnimals(frame))
        guard case .animals(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func emptyFrameStillCarriesHeader() throws {
        let frame = DetectionFrame<PoseDetection>(width: 1080, height: 1920, detections: [])
        let message = WireCodec.encodePoses(frame)
        #expect(message.values.count == 3)
        let decoded = try WireCodec.decode(message)
        guard case .poses(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func detectionsCappedAtMax() throws {
        let many = (0..<40).map { makePose(seed: Float($0)) }
        let message = WireCodec.encodePoses(DetectionFrame(width: 10, height: 10, detections: many))
        let decoded = try WireCodec.decode(message)
        guard case .poses(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out.detections.count == WireCounts.maxDetections)
    }

    @Test func cameraInfo() throws {
        let info = CameraInfo(width: 1280, height: 720, orientationDegrees: 0, facing: 1)
        let decoded = try WireCodec.decode(WireCodec.encodeCameraInfo(info))
        guard case .cameraInfo(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == info)
    }

    @Test func faceBoxes() throws {
        let frame = DetectionFrame(width: 1080, height: 1920, detections: [makeFaceBox(seed: 1), makeFaceBox(seed: 2)])
        let decoded = try WireCodec.decode(WireCodec.encodeFaceBoxes(frame))
        guard case .faceBoxes(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func faceContours() throws {
        // Variable point counts per face, including the m=0 "no contour" sentinel.
        let frame = DetectionFrame(width: 1080, height: 1920, detections: [
            makeFaceContour(seed: 1, pointCount: 17),
            makeFaceContour(seed: 2, pointCount: 0)
        ])
        let decoded = try WireCodec.decode(WireCodec.encodeFaceContours(frame))
        guard case .faceContours(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func faceBoxesEmptyFrame() throws {
        let frame = DetectionFrame<FaceBoxDetection>(width: 640, height: 480, detections: [])
        let message = WireCodec.encodeFaceBoxes(frame)
        #expect(message.values.count == 3)
        let decoded = try WireCodec.decode(message)
        guard case .faceBoxes(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func faceContoursThroughRawBytes() throws {
        // The variable-length layout is the risky one: full serialize → parse cycle.
        let frame = DetectionFrame(width: 1920, height: 1080, detections: [
            makeFaceContour(seed: 3, pointCount: 17),
            makeFaceContour(seed: 4, pointCount: 21)
        ])
        let data = try WireCodec.encodeFaceContours(frame).rawData()
        let reparsed = try OSCMessage(from: data)
        let decoded = try WireCodec.decode(reparsed)
        guard case .faceContours(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func roundTripThroughRawBytes() throws {
        // Full serialize → parse cycle, not just in-memory value copying.
        let frame = DetectionFrame(width: 1080, height: 1920, detections: [makePose(seed: 7)])
        let data = try WireCodec.encodePoses(frame).rawData()
        let reparsed = try OSCMessage(from: data)
        let decoded = try WireCodec.decode(reparsed)
        guard case .poses(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    // MARK: v1.4 additive messages

    @Test func poses3D() throws {
        let frame = DetectionFrame(width: 720, height: 1280, detections: [makePose3D(seed: 1), makePose3D(seed: 2)])
        let decoded = try WireCodec.decode(WireCodec.encodePoses3D(frame))
        guard case .poses3D(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func poses3DEmptyFrame() throws {
        let frame = DetectionFrame<Pose3DDetection>(width: 720, height: 1280, detections: [])
        let message = WireCodec.encodePoses3D(frame)
        #expect(message.values.count == 3)
        let decoded = try WireCodec.decode(message)
        guard case .poses3D(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func poses3DThroughRawBytes() throws {
        let frame = DetectionFrame(width: 1280, height: 720, detections: [makePose3D(seed: 3)])
        let data = try WireCodec.encodePoses3D(frame).rawData()
        let decoded = try WireCodec.decode(OSCMessage(from: data))
        guard case .poses3D(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func animalPoses() throws {
        let frame = DetectionFrame(width: 720, height: 1280, detections: [makeAnimalPose(seed: 1), makeAnimalPose(seed: 2)])
        let decoded = try WireCodec.decode(WireCodec.encodeAnimalPoses(frame))
        guard case .animalPoses(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
        // The sentinel survives the trip untouched.
        #expect(out.detections[0].joints[4] == WirePoint.missing(frameHeight: 1280))
    }

    @Test func animalPosesEmptyFrame() throws {
        let frame = DetectionFrame<AnimalPoseDetection>(width: 720, height: 1280, detections: [])
        let message = WireCodec.encodeAnimalPoses(frame)
        #expect(message.values.count == 3)
        let decoded = try WireCodec.decode(message)
        guard case .animalPoses(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func animalPosesThroughRawBytes() throws {
        let frame = DetectionFrame(width: 720, height: 1280, detections: [makeAnimalPose(seed: 5)])
        let data = try WireCodec.encodeAnimalPoses(frame).rawData()
        let decoded = try WireCodec.decode(OSCMessage(from: data))
        guard case .animalPoses(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func contoursHorizonRectangles() throws {
        let contours = DetectionFrame(width: 720, height: 1280, detections: [
            ContourDetection(confidence: 1, points: [WireXY(x: 1, y: 2), WireXY(x: 3, y: 4), WireXY(x: 5, y: 6)]),
            ContourDetection(confidence: 0.5, points: [])
        ])
        guard case .contours(let c) = try WireCodec.decode(WireCodec.encodeContours(contours)) else { Issue.record("wrong kind"); return }
        #expect(c == contours)

        let horizon = DetectionFrame(width: 720, height: 1280, detections: [
            HorizonDetection(confidence: 0.9, angleDegrees: -3.5, start: WireXY(x: 0, y: 660), end: WireXY(x: 720, y: 616))
        ])
        guard case .horizon(let h) = try WireCodec.decode(WireCodec.encodeHorizon(horizon)) else { Issue.record("wrong kind"); return }
        #expect(h == horizon)
        let noHorizon = DetectionFrame<HorizonDetection>(width: 720, height: 1280, detections: [])
        #expect(WireCodec.encodeHorizon(noHorizon).values.count == 3)

        let rectangles = DetectionFrame(width: 720, height: 1280, detections: [
            RectangleDetection(confidence: 0.8, box: WireRect(left: 10, top: 20, width: 100, height: 50),
                               corners: [WireXY(x: 10, y: 20), WireXY(x: 110, y: 22), WireXY(x: 108, y: 70), WireXY(x: 12, y: 68)])
        ])
        guard case .rectangles(let r) = try WireCodec.decode(WireCodec.encodeRectangles(rectangles)) else { Issue.record("wrong kind"); return }
        #expect(r == rectangles)
    }

    @Test func contoursAreCapped() throws {
        let many = (0..<(WireCounts.maxContours + 10)).map { i in
            ContourDetection(confidence: 1, points: [WireXY(x: Float(i), y: 0)])
        }
        let message = WireCodec.encodeContours(DetectionFrame(width: 10, height: 10, detections: many))
        guard case .contours(let out) = try WireCodec.decode(message) else { Issue.record("wrong kind"); return }
        #expect(out.detections.count == WireCounts.maxContours)
    }

    @Test func humans() throws {
        let frame = DetectionFrame(width: 720, height: 1280, detections: [makeHuman(seed: 1), makeHuman(seed: 2)])
        let decoded = try WireCodec.decode(WireCodec.encodeHumans(frame))
        guard case .humans(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func humansEmptyFrame() throws {
        let frame = DetectionFrame<HumanDetection>(width: 720, height: 1280, detections: [])
        let message = WireCodec.encodeHumans(frame)
        #expect(message.values.count == 3)
        let decoded = try WireCodec.decode(message)
        guard case .humans(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func barcodes() throws {
        // Second barcode has an empty payload (Vision reports none).
        let frame = DetectionFrame(width: 720, height: 1280, detections: [
            makeBarcode(payload: "https://github.com/JGL/TrackOSC"),
            makeBarcode(payload: "", symbology: "EAN13")
        ])
        let decoded = try WireCodec.decode(WireCodec.encodeBarcodes(frame))
        guard case .barcodes(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func barcodesEmptyFrame() throws {
        let frame = DetectionFrame<BarcodeDetection>(width: 720, height: 1280, detections: [])
        let message = WireCodec.encodeBarcodes(frame)
        #expect(message.values.count == 3)
        let decoded = try WireCodec.decode(message)
        guard case .barcodes(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }

    @Test func barcodesThroughRawBytes() throws {
        // String lengths 3, 4 and 0 exercise every OSC string-padding case.
        let frame = DetectionFrame(width: 720, height: 1280, detections: [
            makeBarcode(payload: "abc"),
            makeBarcode(payload: "abcd", symbology: "Code128"),
            makeBarcode(payload: "", symbology: "PDF417")
        ])
        let data = try WireCodec.encodeBarcodes(frame).rawData()
        let decoded = try WireCodec.decode(OSCMessage(from: data))
        guard case .barcodes(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out == frame)
    }
}

// MARK: - Golden bytes

@Suite("Golden wire bytes (VisionOSC compatibility)")
struct GoldenBytesTests {
    /// Pins the exact on-the-wire OSC encoding for a minimal /texts/arr message:
    /// address, type tag string, big-endian int32/float32, padded string.
    /// If this test breaks, the wire format changed and VisionOSC compatibility is lost.
    @Test func textsMessageBytes() throws {
        let frame = DetectionFrame(
            width: 640, height: 480,
            detections: [BoxDetection(
                confidence: 1.0,
                box: WireRect(left: 1, top: 2, width: 3, height: 4),
                label: "Hi"
            )]
        )
        let data = try WireCodec.encodeTexts(frame).rawData()

        var expected = Data()
        func pad4(_ d: inout Data) { while d.count % 4 != 0 { d.append(0) } }
        func appendString(_ s: String, to d: inout Data) {
            d.append(s.data(using: .ascii)!)
            d.append(0)
            pad4(&d)
        }
        func appendInt32(_ v: Int32, to d: inout Data) {
            withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) }
        }
        func appendFloat32(_ v: Float32, to d: inout Data) {
            withUnsafeBytes(of: v.bitPattern.bigEndian) { d.append(contentsOf: $0) }
        }

        appendString("/texts/arr", to: &expected)
        appendString(",iiifffffs", to: &expected)  // 3 ints, 5 floats, 1 string
        appendInt32(640, to: &expected)
        appendInt32(480, to: &expected)
        appendInt32(1, to: &expected)
        appendFloat32(1.0, to: &expected)  // confidence
        appendFloat32(1, to: &expected)    // left
        appendFloat32(2, to: &expected)    // top
        appendFloat32(3, to: &expected)    // width
        appendFloat32(4, to: &expected)    // height
        appendString("Hi", to: &expected)

        #expect(data == expected)
    }

    /// Pins the /camerainfo encoding: four big-endian int32s.
    @Test func cameraInfoMessageBytes() throws {
        let data = try WireCodec.encodeCameraInfo(
            CameraInfo(width: 720, height: 1280, orientationDegrees: 90, facing: 1)
        ).rawData()

        var expected = Data()
        func pad4(_ d: inout Data) { while d.count % 4 != 0 { d.append(0) } }
        func appendString(_ s: String, to d: inout Data) {
            d.append(s.data(using: .ascii)!)
            d.append(0)
            pad4(&d)
        }
        func appendInt32(_ v: Int32, to d: inout Data) {
            withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) }
        }

        appendString("/camerainfo", to: &expected)
        appendString(",iiii", to: &expected)
        appendInt32(720, to: &expected)
        appendInt32(1280, to: &expected)
        appendInt32(90, to: &expected)
        appendInt32(1, to: &expected)

        #expect(data == expected)
    }

    /// Pins the /faces/box encoding (TrackOSC additive, v1.3): header ints,
    /// then 8 big-endian float32s per face (conf, box, roll/yaw/pitch degrees).
    @Test func faceBoxMessageBytes() throws {
        let frame = DetectionFrame(
            width: 640, height: 480,
            detections: [FaceBoxDetection(
                confidence: 1.0,
                box: WireRect(left: 1, top: 2, width: 3, height: 4),
                rollDegrees: 5, yawDegrees: 6, pitchDegrees: 7
            )]
        )
        let data = try WireCodec.encodeFaceBoxes(frame).rawData()

        var expected = Data()
        func pad4(_ d: inout Data) { while d.count % 4 != 0 { d.append(0) } }
        func appendString(_ s: String, to d: inout Data) {
            d.append(s.data(using: .ascii)!)
            d.append(0)
            pad4(&d)
        }
        func appendInt32(_ v: Int32, to d: inout Data) {
            withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) }
        }
        func appendFloat32(_ v: Float32, to d: inout Data) {
            withUnsafeBytes(of: v.bitPattern.bigEndian) { d.append(contentsOf: $0) }
        }

        appendString("/faces/box", to: &expected)
        appendString(",iiiffffffff", to: &expected)  // 3 ints, 8 floats
        appendInt32(640, to: &expected)
        appendInt32(480, to: &expected)
        appendInt32(1, to: &expected)
        appendFloat32(1.0, to: &expected)  // confidence
        appendFloat32(1, to: &expected)    // left
        appendFloat32(2, to: &expected)    // top
        appendFloat32(3, to: &expected)    // width
        appendFloat32(4, to: &expected)    // height
        appendFloat32(5, to: &expected)    // roll°
        appendFloat32(6, to: &expected)    // yaw°
        appendFloat32(7, to: &expected)    // pitch°

        #expect(data == expected)
    }

    /// Pins the /faces/contour encoding (TrackOSC additive, v1.3): header ints,
    /// then per face float32 confidence, int32 point count, count × (x, y).
    /// Two faces pin the interleaving: one with 3 points, one with 0.
    @Test func faceContourMessageBytes() throws {
        let frame = DetectionFrame(
            width: 640, height: 480,
            detections: [
                FaceContourDetection(confidence: 1.0, points: [
                    WireXY(x: 1, y: 2), WireXY(x: 3, y: 4), WireXY(x: 5, y: 6)
                ]),
                FaceContourDetection(confidence: 0.5, points: [])
            ]
        )
        let data = try WireCodec.encodeFaceContours(frame).rawData()

        var expected = Data()
        func pad4(_ d: inout Data) { while d.count % 4 != 0 { d.append(0) } }
        func appendString(_ s: String, to d: inout Data) {
            d.append(s.data(using: .ascii)!)
            d.append(0)
            pad4(&d)
        }
        func appendInt32(_ v: Int32, to d: inout Data) {
            withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) }
        }
        func appendFloat32(_ v: Float32, to d: inout Data) {
            withUnsafeBytes(of: v.bitPattern.bigEndian) { d.append(contentsOf: $0) }
        }

        appendString("/faces/contour", to: &expected)
        appendString(",iiififffffffi", to: &expected)  // header; f i ff ff ff; f i
        appendInt32(640, to: &expected)
        appendInt32(480, to: &expected)
        appendInt32(2, to: &expected)
        appendFloat32(1.0, to: &expected)  // face 0 confidence
        appendInt32(3, to: &expected)      // face 0 point count
        appendFloat32(1, to: &expected)
        appendFloat32(2, to: &expected)
        appendFloat32(3, to: &expected)
        appendFloat32(4, to: &expected)
        appendFloat32(5, to: &expected)
        appendFloat32(6, to: &expected)
        appendFloat32(0.5, to: &expected)  // face 1 confidence
        appendInt32(0, to: &expected)      // face 1 point count (no contour)

        #expect(data == expected)
    }

    /// Pins the poses type tag layout: header ints then 52 floats per pose.
    @Test func posesTypeTags() throws {
        let frame = DetectionFrame(width: 10, height: 20, detections: [makePose(seed: 0)])
        let data = try WireCodec.encodePoses(frame).rawData()

        // Type tag string begins right after "/poses/arr\0\0" (12 bytes).
        let tagStart = 12
        let expectedTags = ",iii" + String(repeating: "f", count: 1 + WireCounts.bodyJoints * 3)
        let tagLength = expectedTags.count
        let tags = String(data: data[tagStart..<(tagStart + tagLength)], encoding: .ascii)
        #expect(tags == expectedTags)
    }

    // MARK: v1.4 additive messages

    /// Pins the /poses3d/arr encoding (TrackOSC additive, v1.4): header ints,
    /// then per pose float32 confidence, float32 body height, and
    /// 17 × (x, y, z, px, py) big-endian float32s.
    @Test func poses3DMessageBytes() throws {
        let joints = (0..<WireCounts.body3DJoints).map { i in
            WirePoint3D(x: Float(i), y: Float(i) + 0.5, z: -Float(i), px: Float(i) * 10, py: Float(i) * 20)
        }
        let frame = DetectionFrame(
            width: 720, height: 1280,
            detections: [Pose3DDetection(confidence: 1.0, bodyHeight: 1.75, joints: joints)]
        )
        let data = try WireCodec.encodePoses3D(frame).rawData()

        var expected = Data()
        func pad4(_ d: inout Data) { while d.count % 4 != 0 { d.append(0) } }
        func appendString(_ s: String, to d: inout Data) {
            d.append(s.data(using: .ascii)!)
            d.append(0)
            pad4(&d)
        }
        func appendInt32(_ v: Int32, to d: inout Data) {
            withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) }
        }
        func appendFloat32(_ v: Float32, to d: inout Data) {
            withUnsafeBytes(of: v.bitPattern.bigEndian) { d.append(contentsOf: $0) }
        }

        appendString("/poses3d/arr", to: &expected)
        appendString(",iii" + String(repeating: "f", count: 2 + WireCounts.body3DJoints * 5), to: &expected)
        appendInt32(720, to: &expected)
        appendInt32(1280, to: &expected)
        appendInt32(1, to: &expected)
        appendFloat32(1.0, to: &expected)   // confidence
        appendFloat32(1.75, to: &expected)  // body height (m)
        for joint in joints {
            appendFloat32(joint.x, to: &expected)
            appendFloat32(joint.y, to: &expected)
            appendFloat32(joint.z, to: &expected)
            appendFloat32(joint.px, to: &expected)
            appendFloat32(joint.py, to: &expected)
        }

        #expect(data == expected)
    }

    /// Pins the /poses3d/arr type tags: header ints then 87 floats per pose.
    @Test func poses3DTypeTags() throws {
        let frame = DetectionFrame(width: 10, height: 20, detections: [makePose3D(seed: 0)])
        let data = try WireCodec.encodePoses3D(frame).rawData()

        // "/poses3d/arr" is 12 chars + NUL, padded to 16 bytes.
        let tagStart = 16
        let expectedTags = ",iii" + String(repeating: "f", count: 2 + WireCounts.body3DJoints * 5)
        let tags = String(data: data[tagStart..<(tagStart + expectedTags.count)], encoding: .ascii)
        #expect(tags == expectedTags)
    }

    /// Pins the /animalposes/arr type tags: header ints then 76 floats per animal.
    @Test func animalPosesTypeTags() throws {
        let frame = DetectionFrame(width: 10, height: 20, detections: [makeAnimalPose(seed: 0)])
        let data = try WireCodec.encodeAnimalPoses(frame).rawData()

        // "/animalposes/arr" is 16 chars + NUL, padded to 20 bytes.
        let tagStart = 20
        let expectedTags = ",iii" + String(repeating: "f", count: 1 + WireCounts.animalJoints * 3)
        let tags = String(data: data[tagStart..<(tagStart + expectedTags.count)], encoding: .ascii)
        #expect(tags == expectedTags)
    }

    /// Pins the v1.6 messages' type tags and layout: contours carry an int32
    /// point count per contour; horizon and rectangles are all floats.
    @Test func v16MessageTypeTags() throws {
        func tags(_ data: Data, addressPadded: Int, count: Int) -> String? {
            String(data: data[addressPadded..<(addressPadded + count)], encoding: .ascii)
        }
        let contours = DetectionFrame(width: 10, height: 20, detections: [
            ContourDetection(confidence: 1, points: [WireXY(x: 1, y: 2), WireXY(x: 3, y: 4)])
        ])
        // "/contours/arr" is 13 chars + NUL, padded to 16.
        #expect(tags(try WireCodec.encodeContours(contours).rawData(), addressPadded: 16, count: 10) == ",iiififfff")

        let horizon = DetectionFrame(width: 10, height: 20, detections: [
            HorizonDetection(confidence: 1, angleDegrees: 2, start: WireXY(x: 0, y: 10), end: WireXY(x: 10, y: 10))
        ])
        // "/horizon" is 8 chars + NUL, padded to 12.
        #expect(tags(try WireCodec.encodeHorizon(horizon).rawData(), addressPadded: 12, count: 10) == ",iiiffffff")

        let rectangles = DetectionFrame(width: 10, height: 20, detections: [
            RectangleDetection(confidence: 1, box: WireRect(left: 1, top: 2, width: 3, height: 4),
                               corners: [WireXY(x: 1, y: 2), WireXY(x: 4, y: 2), WireXY(x: 4, y: 6), WireXY(x: 1, y: 6)])
        ])
        // "/rectangles/arr" is 15 chars + NUL, padded to 16.
        #expect(tags(try WireCodec.encodeRectangles(rectangles).rawData(), addressPadded: 16, count: 17) == ",iii" + String(repeating: "f", count: 13))
    }

    /// Pins the /humans/arr encoding (TrackOSC additive, v1.4): header ints,
    /// then 5 big-endian float32s per human (conf, box).
    @Test func humansMessageBytes() throws {
        let frame = DetectionFrame(
            width: 640, height: 480,
            detections: [HumanDetection(confidence: 1.0, box: WireRect(left: 1, top: 2, width: 3, height: 4))]
        )
        let data = try WireCodec.encodeHumans(frame).rawData()

        var expected = Data()
        func pad4(_ d: inout Data) { while d.count % 4 != 0 { d.append(0) } }
        func appendString(_ s: String, to d: inout Data) {
            d.append(s.data(using: .ascii)!)
            d.append(0)
            pad4(&d)
        }
        func appendInt32(_ v: Int32, to d: inout Data) {
            withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) }
        }
        func appendFloat32(_ v: Float32, to d: inout Data) {
            withUnsafeBytes(of: v.bitPattern.bigEndian) { d.append(contentsOf: $0) }
        }

        appendString("/humans/arr", to: &expected)
        appendString(",iiifffff", to: &expected)  // 3 ints, 5 floats
        appendInt32(640, to: &expected)
        appendInt32(480, to: &expected)
        appendInt32(1, to: &expected)
        appendFloat32(1.0, to: &expected)  // confidence
        appendFloat32(1, to: &expected)    // left
        appendFloat32(2, to: &expected)    // top
        appendFloat32(3, to: &expected)    // width
        appendFloat32(4, to: &expected)    // height

        #expect(data == expected)
    }

    /// Pins the /barcodes/arr encoding (TrackOSC additive, v1.4): header ints,
    /// then per barcode 13 float32s (conf, box, 4 corners) and two strings.
    /// Two barcodes pin the interleaving, the second with an empty payload
    /// (encoded as a lone NUL padded to four bytes).
    @Test func barcodesMessageBytes() throws {
        let frame = DetectionFrame(
            width: 640, height: 480,
            detections: [
                BarcodeDetection(
                    confidence: 1.0,
                    box: WireRect(left: 1, top: 2, width: 3, height: 4),
                    corners: [WireXY(x: 5, y: 6), WireXY(x: 7, y: 8), WireXY(x: 9, y: 10), WireXY(x: 11, y: 12)],
                    symbology: "QR", payload: "Hi"
                ),
                BarcodeDetection(
                    confidence: 0.5,
                    box: WireRect(left: 0, top: 0, width: 0, height: 0),
                    corners: [WireXY(x: 0, y: 0), WireXY(x: 0, y: 0), WireXY(x: 0, y: 0), WireXY(x: 0, y: 0)],
                    symbology: "EAN13", payload: ""
                )
            ]
        )
        let data = try WireCodec.encodeBarcodes(frame).rawData()

        var expected = Data()
        func pad4(_ d: inout Data) { while d.count % 4 != 0 { d.append(0) } }
        func appendString(_ s: String, to d: inout Data) {
            d.append(s.data(using: .ascii)!)
            d.append(0)
            pad4(&d)
        }
        func appendInt32(_ v: Int32, to d: inout Data) {
            withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) }
        }
        func appendFloat32(_ v: Float32, to d: inout Data) {
            withUnsafeBytes(of: v.bitPattern.bigEndian) { d.append(contentsOf: $0) }
        }

        let perBarcode = String(repeating: "f", count: 13) + "ss"
        appendString("/barcodes/arr", to: &expected)
        appendString(",iii" + perBarcode + perBarcode, to: &expected)
        appendInt32(640, to: &expected)
        appendInt32(480, to: &expected)
        appendInt32(2, to: &expected)
        // barcode 0
        appendFloat32(1.0, to: &expected)
        for v: Float32 in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] { appendFloat32(v, to: &expected) }
        appendString("QR", to: &expected)
        appendString("Hi", to: &expected)
        // barcode 1
        appendFloat32(0.5, to: &expected)
        for _ in 0..<12 { appendFloat32(0, to: &expected) }
        appendString("EAN13", to: &expected)
        appendString("", to: &expected)

        #expect(data == expected)
    }
}

// MARK: - Malformed input

@Suite("Malformed messages")
struct MalformedTests {
    @Test func unknownAddressThrows() {
        let message = OSCMessage("/bogus/arr", values: [Int32(1), Int32(2), Int32(0)])
        #expect(throws: WireCodecError.unknownAddress("/bogus/arr")) {
            _ = try WireCodec.decode(message)
        }
    }

    @Test func truncatedMessageThrows() {
        // Claims 1 pose but carries no pose data.
        let message = OSCMessage(OSCAddress.poses, values: [Int32(10), Int32(20), Int32(1)])
        #expect(throws: WireCodecError.self) {
            _ = try WireCodec.decode(message)
        }
    }

    @Test func truncatedContourThrows() {
        // Claims 5 contour points but carries only 2.
        let message = OSCMessage(OSCAddress.faceContour, values: [
            Int32(10), Int32(20), Int32(1),
            Float32(0.9), Int32(5),
            Float32(1), Float32(2), Float32(3), Float32(4)
        ])
        #expect(throws: WireCodecError.self) {
            _ = try WireCodec.decode(message)
        }
    }

    @Test func wrongValueTypeThrows() {
        let message = OSCMessage(OSCAddress.texts, values: [Int32(10), Int32(20), Int32(1), "not a float", "x", "y", "z", "w", "label"])
        #expect(throws: WireCodecError.self) {
            _ = try WireCodec.decode(message)
        }
    }

    @Test func lenientAboutIntWhereFloatExpected() throws {
        // Another sender might encode confidence as int 1; accept it.
        var values: OSCValues = [Int32(10), Int32(20), Int32(1)]
        values.append(Int32(1))  // confidence as int
        values.append(contentsOf: [Float32(1), Float32(2), Float32(3), Float32(4)] as OSCValues)
        values.append("Cat")
        let message = OSCMessage(OSCAddress.animals, values: values)
        let decoded = try WireCodec.decode(message)
        guard case .animals(let out) = decoded else { Issue.record("wrong kind"); return }
        #expect(out.detections[0].confidence == 1.0)
    }

    @Test func truncatedPoses3DThrows() {
        // Claims 1 pose but carries only 10 of its 87 floats.
        var values: OSCValues = [Int32(720), Int32(1280), Int32(1)]
        for i in 0..<10 { values.append(Float32(i)) }
        let message = OSCMessage(OSCAddress.poses3D, values: values)
        #expect(throws: WireCodecError.self) {
            _ = try WireCodec.decode(message)
        }
    }

    @Test func truncatedBarcodeThrows() {
        // 13 floats and the symbology, but no payload string.
        var values: OSCValues = [Int32(720), Int32(1280), Int32(1)]
        for i in 0..<13 { values.append(Float32(i)) }
        values.append("QR")
        let message = OSCMessage(OSCAddress.barcodes, values: values)
        #expect(throws: WireCodecError.self) {
            _ = try WireCodec.decode(message)
        }
    }

    @Test func negativeCountThrows() {
        // A negative detection count must be rejected, not trap in a range loop.
        for address in [OSCAddress.humans, OSCAddress.poses, OSCAddress.texts, OSCAddress.faceBox, OSCAddress.faceContour] {
            let message = OSCMessage(address, values: [Int32(720), Int32(1280), Int32(-1)])
            #expect(throws: WireCodecError.self, "\(address)") {
                _ = try WireCodec.decode(message)
            }
        }
        // Same for a negative contour point count.
        let contour = OSCMessage(OSCAddress.faceContour, values: [Int32(720), Int32(1280), Int32(1), Float32(0.9), Int32(-3)])
        #expect(throws: WireCodecError.self) {
            _ = try WireCodec.decode(contour)
        }
    }

    @Test func barcodeSymbologyWrongTypeThrows() {
        var values: OSCValues = [Int32(720), Int32(1280), Int32(1)]
        for i in 0..<13 { values.append(Float32(i)) }
        values.append(Float32(7))  // symbology should be a string
        values.append("payload")
        let message = OSCMessage(OSCAddress.barcodes, values: values)
        #expect(throws: WireCodecError.self) {
            _ = try WireCodec.decode(message)
        }
    }
}

// MARK: - Skeletons

@Suite("Skeleton edge lists")
struct SkeletonTests {
    @Test func edgesIndexIntoJointOrders() {
        func check(_ edges: [(Int, Int)], count: Int, _ name: String) {
            for (a, b) in edges {
                #expect(a >= 0 && a < count, "\(name) edge (\(a), \(b))")
                #expect(b >= 0 && b < count, "\(name) edge (\(a), \(b))")
                #expect(a != b, "\(name) self-edge (\(a), \(b))")
            }
        }
        check(Skeleton.body17Edges, count: JointOrder.body17.count, "body17")
        check(Skeleton.hand21Edges, count: JointOrder.hand21.count, "hand21")
        check(Skeleton.body3D17Edges, count: JointOrder.body3D17.count, "body3D17")
        check(Skeleton.animal25Edges, count: JointOrder.animal25.count, "animal25")
    }

    @Test func jointOrdersMatchWireCounts() {
        #expect(JointOrder.body17.count == WireCounts.bodyJoints)
        #expect(JointOrder.hand21.count == WireCounts.handJoints)
        #expect(JointOrder.body3D17.count == WireCounts.body3DJoints)
        #expect(JointOrder.animal25.count == WireCounts.animalJoints)
        #expect(OSCAddress.all.count == 15)
    }
}

// MARK: - Coordinate mapping

@Suite("Coordinate mapping")
struct CoordinateMapperTests {
    @Test func flipsYAndScalesToPixels() {
        let point = CoordinateMapper.point(
            normalizedX: 0.5, normalizedY: 0.25, confidence: 0.9,
            frameWidth: 100, frameHeight: 200
        )
        #expect(point.x == 50)
        #expect(point.y == 150)  // (1 - 0.25) * 200
        #expect(point.confidence == 0.9)
    }

    @Test func rectConvertsBottomLeftToTopLeft() {
        // Vision box: origin (0.1, 0.2) bottom-left, size 0.3 × 0.4 in a 100×100 frame.
        let rect = CoordinateMapper.rect(
            normalized: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            frameWidth: 100, frameHeight: 100
        )
        #expect(abs(rect.left - 10) < 0.001)
        #expect(abs(rect.top - 40) < 0.001)  // (1 - 0.2 - 0.4) * 100
        #expect(abs(rect.width - 30) < 0.001)
        #expect(abs(rect.height - 40) < 0.001)
    }

    @Test func xyFlipsYAndScalesToPixels() {
        let point = CoordinateMapper.xy(normalizedX: 0.25, normalizedY: 0.75, frameWidth: 400, frameHeight: 200)
        #expect(point.x == 100)
        #expect(point.y == 50)  // (1 - 0.75) * 200
    }

    @Test func missingJointSentinelMatchesVisionOSC() {
        let missing = WirePoint.missing(frameHeight: 1920)
        #expect(missing.x == 0)
        #expect(missing.y == 1920)
        #expect(missing.confidence == 0)
    }
}
