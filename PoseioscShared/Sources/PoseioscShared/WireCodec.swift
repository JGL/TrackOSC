//
//  WireCodec.swift
//  PoseioscShared
//
//  Encode/decode of the VisionOSC OSC wire format. This is the contract between
//  the iOS sender and the macOS receiver (and any third-party VisionOSC consumer).
//
//  Every message: int32 width, int32 height, int32 nDetections, then per detection:
//    poses/hands/faces: float confidence + N × (float x, float y, float confidence)
//    texts/animals:     float confidence, float left, top, width, height, string
//
//  All OSC types must be exactly int32 / float32 / string to match VisionOSC.
//

import SwiftOSC

public enum WireCodecError: Error, Equatable {
    case unknownAddress(String)
    case truncatedMessage(address: String, expectedAtLeast: Int, got: Int)
    case badValue(address: String, index: Int)
}

public enum WireCodec {
    // MARK: - Encoding

    public static func encodePoses(_ frame: DetectionFrame<PoseDetection>) -> OSCMessage {
        encodeKeypoints(address: OSCAddress.poses, frame: frame, joints: \.joints, confidence: \.confidence)
    }

    public static func encodeHands(_ frame: DetectionFrame<HandDetection>) -> OSCMessage {
        encodeKeypoints(address: OSCAddress.hands, frame: frame, joints: \.joints, confidence: \.confidence)
    }

    public static func encodeFaces(_ frame: DetectionFrame<FaceDetection>) -> OSCMessage {
        encodeKeypoints(address: OSCAddress.faces, frame: frame, joints: \.points, confidence: \.confidence)
    }

    public static func encodeTexts(_ frame: DetectionFrame<BoxDetection>) -> OSCMessage {
        encodeBoxes(address: OSCAddress.texts, frame: frame)
    }

    public static func encodeAnimals(_ frame: DetectionFrame<BoxDetection>) -> OSCMessage {
        encodeBoxes(address: OSCAddress.animals, frame: frame)
    }

    public static func encodeCameraInfo(_ info: CameraInfo) -> OSCMessage {
        OSCMessage(OSCAddress.cameraInfo, values: [
            info.width, info.height, info.orientationDegrees, info.facing
        ])
    }

    public static func encodeFaceBoxes(_ frame: DetectionFrame<FaceBoxDetection>) -> OSCMessage {
        var values: OSCValues = header(frame.width, frame.height, frame.detections.count)
        for detection in frame.detections.prefix(WireCounts.maxDetections) {
            values.append(Float32(detection.confidence))
            values.append(Float32(detection.box.left))
            values.append(Float32(detection.box.top))
            values.append(Float32(detection.box.width))
            values.append(Float32(detection.box.height))
            values.append(Float32(detection.rollDegrees))
            values.append(Float32(detection.yawDegrees))
            values.append(Float32(detection.pitchDegrees))
        }
        return OSCMessage(OSCAddress.faceBox, values: values)
    }

    public static func encodeFaceContours(_ frame: DetectionFrame<FaceContourDetection>) -> OSCMessage {
        var values: OSCValues = header(frame.width, frame.height, frame.detections.count)
        for detection in frame.detections.prefix(WireCounts.maxDetections) {
            values.append(Float32(detection.confidence))
            values.append(Int32(detection.points.count))
            for point in detection.points {
                values.append(Float32(point.x))
                values.append(Float32(point.y))
            }
        }
        return OSCMessage(OSCAddress.faceContour, values: values)
    }

    private static func encodeKeypoints<D: Sendable & Equatable>(
        address: String,
        frame: DetectionFrame<D>,
        joints: KeyPath<D, [WirePoint]>,
        confidence: KeyPath<D, Float>
    ) -> OSCMessage {
        var values: OSCValues = header(frame.width, frame.height, frame.detections.count)
        for detection in frame.detections.prefix(WireCounts.maxDetections) {
            values.append(Float32(detection[keyPath: confidence]))
            for point in detection[keyPath: joints] {
                values.append(Float32(point.x))
                values.append(Float32(point.y))
                values.append(Float32(point.confidence))
            }
        }
        return OSCMessage(address, values: values)
    }

    private static func encodeBoxes(address: String, frame: DetectionFrame<BoxDetection>) -> OSCMessage {
        var values: OSCValues = header(frame.width, frame.height, frame.detections.count)
        for detection in frame.detections.prefix(WireCounts.maxDetections) {
            values.append(Float32(detection.confidence))
            values.append(Float32(detection.box.left))
            values.append(Float32(detection.box.top))
            values.append(Float32(detection.box.width))
            values.append(Float32(detection.box.height))
            values.append(detection.label)
        }
        return OSCMessage(address, values: values)
    }

    private static func header(_ width: Int32, _ height: Int32, _ count: Int) -> OSCValues {
        [width, height, Int32(min(count, WireCounts.maxDetections))]
    }

    // MARK: - Decoding

    /// Decode any Poseiosc/VisionOSC message, dispatching on its OSC address.
    public static func decode(_ message: OSCMessage) throws -> DecodedFrame {
        let address = message.addressPattern.stringValue
        switch address {
        case OSCAddress.poses:
            return try .poses(decodeKeypoints(message, pointCount: WireCounts.bodyJoints, make: PoseDetection.init))
        case OSCAddress.hands:
            return try .hands(decodeKeypoints(message, pointCount: WireCounts.handJoints, make: HandDetection.init))
        case OSCAddress.faces:
            return try .faces(decodeKeypoints(message, pointCount: WireCounts.facePoints, make: FaceDetection.init))
        case OSCAddress.texts:
            return try .texts(decodeBoxes(message))
        case OSCAddress.animals:
            return try .animals(decodeBoxes(message))
        case OSCAddress.cameraInfo:
            return try .cameraInfo(decodeCameraInfo(message))
        case OSCAddress.faceBox:
            return try .faceBoxes(decodeFaceBoxes(message))
        case OSCAddress.faceContour:
            return try .faceContours(decodeFaceContours(message))
        default:
            throw WireCodecError.unknownAddress(address)
        }
    }

    private static func decodeFaceBoxes(_ message: OSCMessage) throws -> DetectionFrame<FaceBoxDetection> {
        let address = message.addressPattern.stringValue
        var reader = ValueReader(address: address, values: message.values)
        let width = try reader.int32()
        let height = try reader.int32()
        let count = try reader.int32()

        var detections: [FaceBoxDetection] = []
        detections.reserveCapacity(min(Int(count), WireCounts.maxDetections))
        for _ in 0..<count {
            let confidence = try reader.float()
            let left = try reader.float()
            let top = try reader.float()
            let boxWidth = try reader.float()
            let boxHeight = try reader.float()
            let roll = try reader.float()
            let yaw = try reader.float()
            let pitch = try reader.float()
            detections.append(FaceBoxDetection(
                confidence: confidence,
                box: WireRect(left: left, top: top, width: boxWidth, height: boxHeight),
                rollDegrees: roll,
                yawDegrees: yaw,
                pitchDegrees: pitch
            ))
        }
        return DetectionFrame(width: width, height: height, detections: detections)
    }

    private static func decodeFaceContours(_ message: OSCMessage) throws -> DetectionFrame<FaceContourDetection> {
        let address = message.addressPattern.stringValue
        var reader = ValueReader(address: address, values: message.values)
        let width = try reader.int32()
        let height = try reader.int32()
        let count = try reader.int32()

        var detections: [FaceContourDetection] = []
        detections.reserveCapacity(min(Int(count), WireCounts.maxDetections))
        for _ in 0..<count {
            let confidence = try reader.float()
            let pointCount = try reader.int32()
            var points: [WireXY] = []
            // The count is attacker-controlled until the reads below validate
            // it, so cap the up-front allocation; truncation throws in next().
            points.reserveCapacity(min(Int(pointCount), 512))
            for _ in 0..<pointCount {
                let x = try reader.float()
                let y = try reader.float()
                points.append(WireXY(x: x, y: y))
            }
            detections.append(FaceContourDetection(confidence: confidence, points: points))
        }
        return DetectionFrame(width: width, height: height, detections: detections)
    }

    private static func decodeCameraInfo(_ message: OSCMessage) throws -> CameraInfo {
        var reader = ValueReader(address: message.addressPattern.stringValue, values: message.values)
        return try CameraInfo(
            width: reader.int32(),
            height: reader.int32(),
            orientationDegrees: reader.int32(),
            facing: reader.int32()
        )
    }

    private static func decodeKeypoints<D: Sendable & Equatable>(
        _ message: OSCMessage,
        pointCount: Int,
        make: (Float, [WirePoint]) -> D
    ) throws -> DetectionFrame<D> {
        let address = message.addressPattern.stringValue
        var reader = ValueReader(address: address, values: message.values)
        let width = try reader.int32()
        let height = try reader.int32()
        let count = try reader.int32()

        var detections: [D] = []
        detections.reserveCapacity(Int(count))
        for _ in 0..<count {
            let confidence = try reader.float()
            var points: [WirePoint] = []
            points.reserveCapacity(pointCount)
            for _ in 0..<pointCount {
                let x = try reader.float()
                let y = try reader.float()
                let c = try reader.float()
                points.append(WirePoint(x: x, y: y, confidence: c))
            }
            detections.append(make(confidence, points))
        }
        return DetectionFrame(width: width, height: height, detections: detections)
    }

    private static func decodeBoxes(_ message: OSCMessage) throws -> DetectionFrame<BoxDetection> {
        let address = message.addressPattern.stringValue
        var reader = ValueReader(address: address, values: message.values)
        let width = try reader.int32()
        let height = try reader.int32()
        let count = try reader.int32()

        var detections: [BoxDetection] = []
        detections.reserveCapacity(Int(count))
        for _ in 0..<count {
            let confidence = try reader.float()
            let left = try reader.float()
            let top = try reader.float()
            let boxWidth = try reader.float()
            let boxHeight = try reader.float()
            let label = try reader.string()
            detections.append(BoxDetection(
                confidence: confidence,
                box: WireRect(left: left, top: top, width: boxWidth, height: boxHeight),
                label: label
            ))
        }
        return DetectionFrame(width: width, height: height, detections: detections)
    }
}

/// Sequential typed reader over an OSC values array. Strict about the expected
/// VisionOSC types but lenient where another sender might reasonably differ
/// (e.g. int where float is expected, or 64-bit variants).
private struct ValueReader {
    let address: String
    let values: OSCValues
    var index = 0

    init(address: String, values: OSCValues) {
        self.address = address
        self.values = values
    }

    private mutating func next() throws -> any OSCValue {
        guard index < values.count else {
            throw WireCodecError.truncatedMessage(address: address, expectedAtLeast: index + 1, got: values.count)
        }
        defer { index += 1 }
        return values[index]
    }

    mutating func int32() throws -> Int32 {
        let value = try next()
        switch value {
        case let v as Int32: return v
        case let v as Int64: return Int32(clamping: v)
        case let v as Int: return Int32(clamping: v)
        case let v as Float32: return Int32(v)
        case let v as Double: return Int32(v)
        default: throw WireCodecError.badValue(address: address, index: index - 1)
        }
    }

    mutating func float() throws -> Float {
        let value = try next()
        switch value {
        case let v as Float32: return v
        case let v as Double: return Float(v)
        case let v as Int32: return Float(v)
        case let v as Int64: return Float(v)
        case let v as Int: return Float(v)
        default: throw WireCodecError.badValue(address: address, index: index - 1)
        }
    }

    mutating func string() throws -> String {
        let value = try next()
        switch value {
        case let v as String: return v
        case let v as Character: return String(v)
        default: throw WireCodecError.badValue(address: address, index: index - 1)
        }
    }
}
