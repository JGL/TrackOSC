//
//  Models.swift
//  PoseioscShared
//
//  Plain value types describing one frame of detections, in wire coordinates:
//  pixels, origin top-left, unmirrored.
//

import Foundation

/// A single keypoint in pixel coordinates (origin top-left).
/// `confidence` carries Vision's per-point confidence – except for face points,
/// where it carries the per-point precision estimate, matching VisionOSC.
public struct WirePoint: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var confidence: Float

    public init(x: Float, y: Float, confidence: Float) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }

    /// VisionOSC's "missing joint" value: vision-space (0,0) run through the
    /// top-left flip, i.e. `(0, frameHeight, 0)`. Consumers filter on confidence == 0.
    public static func missing(frameHeight: Float) -> WirePoint {
        WirePoint(x: 0, y: frameHeight, confidence: 0)
    }
}

/// A bare coordinate pair in pixel coordinates (origin top-left), for points
/// that carry no per-point confidence (face contour vertices).
public struct WireXY: Sendable, Equatable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

/// An axis-aligned bounding box in pixel coordinates (origin top-left).
public struct WireRect: Sendable, Equatable {
    public var left: Float
    public var top: Float
    public var width: Float
    public var height: Float

    public init(left: Float, top: Float, width: Float, height: Float) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }
}

/// One detected body pose: overall confidence + exactly 17 joints in `JointOrder.body17` order.
public struct PoseDetection: Sendable, Equatable {
    public var confidence: Float
    public var joints: [WirePoint]

    public init(confidence: Float, joints: [WirePoint]) {
        precondition(joints.count == WireCounts.bodyJoints, "PoseDetection requires exactly \(WireCounts.bodyJoints) joints")
        self.confidence = confidence
        self.joints = joints
    }
}

/// One detected hand: overall confidence + exactly 21 joints in `JointOrder.hand21` order.
public struct HandDetection: Sendable, Equatable {
    public var confidence: Float
    public var joints: [WirePoint]

    public init(confidence: Float, joints: [WirePoint]) {
        precondition(joints.count == WireCounts.handJoints, "HandDetection requires exactly \(WireCounts.handJoints) joints")
        self.confidence = confidence
        self.joints = joints
    }
}

/// One detected face: overall confidence + exactly 76 landmark points in Vision's
/// constellation order. Each point's `confidence` is Vision's precision estimate.
public struct FaceDetection: Sendable, Equatable {
    public var confidence: Float
    public var points: [WirePoint]

    public init(confidence: Float, points: [WirePoint]) {
        precondition(points.count == WireCounts.facePoints, "FaceDetection requires exactly \(WireCounts.facePoints) points")
        self.confidence = confidence
        self.points = points
    }
}

/// One face's boundary and head pose, for the additive /faces/box message:
/// bounding box in pixels (origin top-left) plus roll/yaw/pitch in degrees.
/// An angle Vision didn't report is encoded as 0.
public struct FaceBoxDetection: Sendable, Equatable {
    public var confidence: Float
    public var box: WireRect
    public var rollDegrees: Float
    public var yawDegrees: Float
    public var pitchDegrees: Float

    public init(confidence: Float, box: WireRect, rollDegrees: Float, yawDegrees: Float, pitchDegrees: Float) {
        self.confidence = confidence
        self.box = box
        self.rollDegrees = rollDegrees
        self.yawDegrees = yawDegrees
        self.pitchDegrees = pitchDegrees
    }
}

/// One face's jawline contour, for the additive /faces/contour message: an
/// OPEN polyline (ear → chin → ear). The point count varies by OS revision
/// and is empty when Vision reports no contour for the face.
public struct FaceContourDetection: Sendable, Equatable {
    public var confidence: Float
    public var points: [WireXY]

    public init(confidence: Float, points: [WireXY]) {
        self.confidence = confidence
        self.points = points
    }
}

/// One detected text region or animal: confidence + bounding box + string payload
/// (recognized text, or animal label "Cat"/"Dog").
public struct BoxDetection: Sendable, Equatable {
    public var confidence: Float
    public var box: WireRect
    public var label: String

    public init(confidence: Float, box: WireRect, label: String) {
        self.confidence = confidence
        self.box = box
        self.label = label
    }
}

/// One joint of a 3D body pose (additive /poses3d/arr message, v1.4): its
/// position in metres in Vision's camera-relative space, plus its 2D
/// projection in wire pixels (origin top-left) so 2D-only receivers can draw
/// it without projecting. Vision's camera space is right-handed with y up;
/// x, y, z are the translation of the joint relative to the camera.
public struct WirePoint3D: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var z: Float
    /// Projected pixel x (origin top-left).
    public var px: Float
    /// Projected pixel y (origin top-left).
    public var py: Float

    public init(x: Float, y: Float, z: Float, px: Float, py: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.px = px
        self.py = py
    }
}

/// One detected 3D body pose: overall confidence, estimated body height in
/// metres, and exactly 17 joints in `JointOrder.body3D17` order. Vision always
/// reports all 17 joints, so there is no missing-joint sentinel.
public struct Pose3DDetection: Sendable, Equatable {
    public var confidence: Float
    /// Estimated body height in metres (measured from camera intrinsics when
    /// available, otherwise a reference estimate).
    public var bodyHeight: Float
    public var joints: [WirePoint3D]

    public init(confidence: Float, bodyHeight: Float, joints: [WirePoint3D]) {
        precondition(joints.count == WireCounts.body3DJoints, "Pose3DDetection requires exactly \(WireCounts.body3DJoints) joints")
        self.confidence = confidence
        self.bodyHeight = bodyHeight
        self.joints = joints
    }
}

/// One detected animal (cat/dog) pose: overall confidence + exactly 25 joints
/// in `JointOrder.animal25` order. Missing joints use `WirePoint.missing`.
public struct AnimalPoseDetection: Sendable, Equatable {
    public var confidence: Float
    public var joints: [WirePoint]

    public init(confidence: Float, joints: [WirePoint]) {
        precondition(joints.count == WireCounts.animalJoints, "AnimalPoseDetection requires exactly \(WireCounts.animalJoints) joints")
        self.confidence = confidence
        self.joints = joints
    }
}

/// One detected human (whole-body rectangle, no skeleton), for the additive
/// /humans/arr message.
public struct HumanDetection: Sendable, Equatable {
    public var confidence: Float
    public var box: WireRect

    public init(confidence: Float, box: WireRect) {
        self.confidence = confidence
        self.box = box
    }
}

/// One detected barcode or QR code, for the additive /barcodes/arr message:
/// axis-aligned bounding box, the four quadrilateral corners (top-left,
/// top-right, bottom-right, bottom-left, in the code's own orientation), the
/// symbology name (e.g. "QR", "EAN13", "Code128") and the decoded payload
/// ("" when Vision reports none).
public struct BarcodeDetection: Sendable, Equatable {
    public var confidence: Float
    public var box: WireRect
    public var corners: [WireXY]
    public var symbology: String
    public var payload: String

    public init(confidence: Float, box: WireRect, corners: [WireXY], symbology: String, payload: String) {
        precondition(corners.count == WireCounts.barcodeCorners, "BarcodeDetection requires exactly \(WireCounts.barcodeCorners) corners")
        self.confidence = confidence
        self.box = box
        self.corners = corners
        self.symbology = symbology
        self.payload = payload
    }
}

/// One detected edge contour (/contours/arr): a closed polyline in pixels.
public struct ContourDetection: Sendable, Equatable {
    public var confidence: Float
    public var points: [WireXY]

    public init(confidence: Float, points: [WireXY]) {
        self.confidence = confidence
        self.points = points
    }
}

/// The horizon (/horizon): its angle in degrees and the line through the
/// frame's centre at that angle, as two endpoints in pixels.
public struct HorizonDetection: Sendable, Equatable {
    public var confidence: Float
    public var angleDegrees: Float
    public var start: WireXY
    public var end: WireXY

    public init(confidence: Float, angleDegrees: Float, start: WireXY, end: WireXY) {
        self.confidence = confidence
        self.angleDegrees = angleDegrees
        self.start = start
        self.end = end
    }
}

/// A detected rectangle (/rectangles/arr): axis-aligned box plus the four
/// corners of the quadrilateral in its own orientation (TL, TR, BR, BL).
public struct RectangleDetection: Sendable, Equatable {
    public var confidence: Float
    public var box: WireRect
    public var corners: [WireXY]

    public init(confidence: Float, box: WireRect, corners: [WireXY]) {
        self.confidence = confidence
        self.box = box
        self.corners = corners
    }
}

/// A full frame of detections of one kind, with the camera frame dimensions
/// (oriented pixels) that all coordinates are expressed in.
public struct DetectionFrame<Detection: Sendable & Equatable>: Sendable, Equatable {
    public var width: Int32
    public var height: Int32
    public var detections: [Detection]

    public init(width: Int32, height: Int32, detections: [Detection]) {
        self.width = width
        self.height = height
        self.detections = detections
    }
}

/// Camera geometry broadcast alongside detection frames so receivers don't
/// have to infer orientation. `orientationDegrees` is the rotation of the
/// phone relative to its sensor-native landscape position: 0 = landscape,
/// 90 = portrait, 180 = opposite landscape, 270 = portrait upside down –
/// the same values as AVFoundation's video rotation angles.
public struct CameraInfo: Sendable, Equatable {
    public var width: Int32
    public var height: Int32
    public var orientationDegrees: Int32
    /// 0 = back camera, 1 = front camera.
    public var facing: Int32

    public init(width: Int32, height: Int32, orientationDegrees: Int32, facing: Int32) {
        self.width = width
        self.height = height
        self.orientationDegrees = orientationDegrees
        self.facing = facing
    }

    public var isFrontCamera: Bool { facing == 1 }

    public var orientationName: String {
        switch orientationDegrees {
        case 0: "landscape"
        case 90: "portrait"
        case 180: "landscape (flipped)"
        case 270: "portrait (upside down)"
        default: "\(orientationDegrees)°"
        }
    }
}

/// A decoded incoming message, dispatched by OSC address.
public enum DecodedFrame: Sendable {
    case poses(DetectionFrame<PoseDetection>)
    case hands(DetectionFrame<HandDetection>)
    case faces(DetectionFrame<FaceDetection>)
    case texts(DetectionFrame<BoxDetection>)
    case animals(DetectionFrame<BoxDetection>)
    case cameraInfo(CameraInfo)
    case faceBoxes(DetectionFrame<FaceBoxDetection>)
    case faceContours(DetectionFrame<FaceContourDetection>)
    case poses3D(DetectionFrame<Pose3DDetection>)
    case barcodes(DetectionFrame<BarcodeDetection>)
    case animalPoses(DetectionFrame<AnimalPoseDetection>)
    case humans(DetectionFrame<HumanDetection>)
    case contours(DetectionFrame<ContourDetection>)
    case horizon(DetectionFrame<HorizonDetection>)
    case rectangles(DetectionFrame<RectangleDetection>)

    /// The OSC address this frame kind corresponds to.
    public var address: String {
        switch self {
        case .poses: OSCAddress.poses
        case .hands: OSCAddress.hands
        case .faces: OSCAddress.faces
        case .texts: OSCAddress.texts
        case .animals: OSCAddress.animals
        case .cameraInfo: OSCAddress.cameraInfo
        case .faceBoxes: OSCAddress.faceBox
        case .faceContours: OSCAddress.faceContour
        case .poses3D: OSCAddress.poses3D
        case .barcodes: OSCAddress.barcodes
        case .animalPoses: OSCAddress.animalPoses
        case .humans: OSCAddress.humans
        case .contours: OSCAddress.contours
        case .horizon: OSCAddress.horizon
        case .rectangles: OSCAddress.rectangles
        }
    }
}
