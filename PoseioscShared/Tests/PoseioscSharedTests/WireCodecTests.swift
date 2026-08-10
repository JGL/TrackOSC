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

    @Test func missingJointSentinelMatchesVisionOSC() {
        let missing = WirePoint.missing(frameHeight: 1920)
        #expect(missing.x == 0)
        #expect(missing.y == 1920)
        #expect(missing.confidence == 0)
    }
}
