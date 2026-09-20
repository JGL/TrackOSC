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
//  TrackOSC additions (v1.3 / v1.4), same header:
//    faces/box:         float confidence, left, top, width, height, roll, yaw, pitch
//    faces/contour:     float confidence, int32 m, m × (float x, float y)
//    poses3d/arr:       float confidence, float bodyHeight, 17 × (x, y, z, px, py)
//    barcodes/arr:      float confidence, left, top, width, height,
//                       4 × (float x, float y), string symbology, string payload
//    animalposes/arr:   float confidence + 25 × (float x, float y, float confidence)
//    humans/arr:        float confidence, left, top, width, height
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

    public static func encodePoses3D(_ frame: DetectionFrame<Pose3DDetection>) -> OSCMessage {
        var values: OSCValues = header(frame.width, frame.height, frame.detections.count)
        for detection in frame.detections.prefix(WireCounts.maxDetections) {
            values.append(Float32(detection.confidence))
            values.append(Float32(detection.bodyHeight))
            for joint in detection.joints {
                values.append(Float32(joint.x))
                values.append(Float32(joint.y))
                values.append(Float32(joint.z))
                values.append(Float32(joint.px))
                values.append(Float32(joint.py))
            }
        }
        return OSCMessage(OSCAddress.poses3D, values: values)
    }

    public static func encodeAnimalPoses(_ frame: DetectionFrame<AnimalPoseDetection>) -> OSCMessage {
        encodeKeypoints(address: OSCAddress.animalPoses, frame: frame, joints: \.joints, confidence: \.confidence)
    }

    public static func encodeHumans(_ frame: DetectionFrame<HumanDetection>) -> OSCMessage {
        var values: OSCValues = header(frame.width, frame.height, frame.detections.count)
        for detection in frame.detections.prefix(WireCounts.maxDetections) {
            values.append(Float32(detection.confidence))
            values.append(Float32(detection.box.left))
            values.append(Float32(detection.box.top))
            values.append(Float32(detection.box.width))
            values.append(Float32(detection.box.height))
        }
        return OSCMessage(OSCAddress.humans, values: values)
    }

    public static func encodeBarcodes(_ frame: DetectionFrame<BarcodeDetection>) -> OSCMessage {
        var values: OSCValues = header(frame.width, frame.height, frame.detections.count)
        for detection in frame.detections.prefix(WireCounts.maxDetections) {
            values.append(Float32(detection.confidence))
            values.append(Float32(detection.box.left))
            values.append(Float32(detection.box.top))
            values.append(Float32(detection.box.width))
            values.append(Float32(detection.box.height))
            for corner in detection.corners {
                values.append(Float32(corner.x))
                values.append(Float32(corner.y))
            }
            values.append(detection.symbology)
            values.append(detection.payload)
        }
        return OSCMessage(OSCAddress.barcodes, values: values)
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
        case OSCAddress.poses3D:
            return try .poses3D(decodePoses3D(message))
        case OSCAddress.barcodes:
            return try .barcodes(decodeBarcodes(message))
        case OSCAddress.animalPoses:
            return try .animalPoses(decodeKeypoints(message, pointCount: WireCounts.animalJoints, make: AnimalPoseDetection.init))
        case OSCAddress.humans:
            return try .humans(decodeHumans(message))
        default:
            throw WireCodecError.unknownAddress(address)
        }
    }

    private static func decodePoses3D(_ message: OSCMessage) throws -> DetectionFrame<Pose3DDetection> {
        let address = message.addressPattern.stringValue
        var reader = ValueReader(address: address, values: message.values)
        let width = try reader.int32()
        let height = try reader.int32()
        let count = try reader.count()

        var detections: [Pose3DDetection] = []
        detections.reserveCapacity(min(Int(count), WireCounts.maxDetections))
        for _ in 0..<count {
            let confidence = try reader.float()
            let bodyHeight = try reader.float()
            var joints: [WirePoint3D] = []
            joints.reserveCapacity(WireCounts.body3DJoints)
            for _ in 0..<WireCounts.body3DJoints {
                let x = try reader.float()
                let y = try reader.float()
                let z = try reader.float()
                let px = try reader.float()
                let py = try reader.float()
                joints.append(WirePoint3D(x: x, y: y, z: z, px: px, py: py))
            }
            detections.append(Pose3DDetection(confidence: confidence, bodyHeight: bodyHeight, joints: joints))
        }
        return DetectionFrame(width: width, height: height, detections: detections)
    }

    private static func decodeHumans(_ message: OSCMessage) throws -> DetectionFrame<HumanDetection> {
        let address = message.addressPattern.stringValue
        var reader = ValueReader(address: address, values: message.values)
        let width = try reader.int32()
        let height = try reader.int32()
        let count = try reader.count()

        var detections: [HumanDetection] = []
        detections.reserveCapacity(min(Int(count), WireCounts.maxDetections))
        for _ in 0..<count {
            let confidence = try reader.float()
            let left = try reader.float()
            let top = try reader.float()
            let boxWidth = try reader.float()
            let boxHeight = try reader.float()
            detections.append(HumanDetection(
                confidence: confidence,
                box: WireRect(left: left, top: top, width: boxWidth, height: boxHeight)
            ))
        }
        return DetectionFrame(width: width, height: height, detections: detections)
    }

    private static func decodeBarcodes(_ message: OSCMessage) throws -> DetectionFrame<BarcodeDetection> {
        let address = message.addressPattern.stringValue
        var reader = ValueReader(address: address, values: message.values)
        let width = try reader.int32()
        let height = try reader.int32()
        let count = try reader.count()

        var detections: [BarcodeDetection] = []
        detections.reserveCapacity(min(Int(count), WireCounts.maxDetections))
        for _ in 0..<count {
            let confidence = try reader.float()
            let left = try reader.float()
            let top = try reader.float()
            let boxWidth = try reader.float()
            let boxHeight = try reader.float()
            var corners: [WireXY] = []
            corners.reserveCapacity(WireCounts.barcodeCorners)
            for _ in 0..<WireCounts.barcodeCorners {
                let x = try reader.float()
                let y = try reader.float()
                corners.append(WireXY(x: x, y: y))
            }
            let symbology = try reader.string()
            let payload = try reader.string()
            detections.append(BarcodeDetection(
                confidence: confidence,
                box: WireRect(left: left, top: top, width: boxWidth, height: boxHeight),
                corners: corners,
                symbology: symbology,
                payload: payload
            ))
        }
        return DetectionFrame(width: width, height: height, detections: detections)
    }

    private static func decodeFaceBoxes(_ message: OSCMessage) throws -> DetectionFrame<FaceBoxDetection> {
        let address = message.addressPattern.stringValue
        var reader = ValueReader(address: address, values: message.values)
        let width = try reader.int32()
        let height = try reader.int32()
        let count = try reader.count()

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
        let count = try reader.count()

        var detections: [FaceContourDetection] = []
        detections.reserveCapacity(min(Int(count), WireCounts.maxDetections))
        for _ in 0..<count {
            let confidence = try reader.float()
            let pointCount = try reader.count()
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
        let count = try reader.count()

        var detections: [D] = []
        detections.reserveCapacity(min(Int(count), WireCounts.maxDetections))
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
        let count = try reader.count()

        var detections: [BoxDetection] = []
        detections.reserveCapacity(min(Int(count), WireCounts.maxDetections))
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

    /// A count field: an int32 that must be non-negative. A negative count
    /// would trap in `0..<count`, so it is rejected as a bad value instead.
    mutating func count() throws -> Int32 {
        let value = try int32()
        guard value >= 0 else { throw WireCodecError.badValue(address: address, index: index - 1) }
        return value
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
