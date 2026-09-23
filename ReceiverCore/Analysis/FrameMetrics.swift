//
//  FrameMetrics.swift
//  TrackOSC (ReceiverCore)
//
//  Small, pure readings of a decoded frame that apps narrate, route or map:
//  normalised positions, raised hands, face angles, 3D distance.
//  Coordinates on the wire are pixels with the origin top-left, so "higher
//  on screen" means a smaller y.
//

import Foundation
import PoseioscShared

enum FrameMetrics {
    /// Vision's yaw is positive when the face turns towards its own left,
    /// which appears as the viewer's right on an unmirrored image. Kept as
    /// one constant so the wording can be flipped once if a device says so.
    static let positiveYawIsSubjectLeft = true

    struct Normalised: Equatable, Sendable {
        var x: Double   // 0 = left edge, 1 = right edge
        var y: Double   // 0 = top, 1 = bottom
    }

    static func isVisible(_ point: WirePoint) -> Bool {
        point.confidence > 0
    }

    static func normalised(_ point: WirePoint, in frame: (width: Int32, height: Int32)) -> Normalised? {
        guard isVisible(point), frame.width > 0, frame.height > 0 else { return nil }
        return Normalised(x: Double(point.x) / Double(frame.width), y: Double(point.y) / Double(frame.height))
    }

    static func normalisedCentre(of box: WireRect, in frame: (width: Int32, height: Int32)) -> Normalised? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        return Normalised(x: Double(box.left + box.width / 2) / Double(frame.width),
                          y: Double(box.top + box.height / 2) / Double(frame.height))
    }

    // MARK: - Body (17 PoseNet joints)

    static let noseIndex = 0
    static let leftShoulderIndex = 5, rightShoulderIndex = 6
    static let leftWristIndex = 9, rightWristIndex = 10

    static func nose(of pose: PoseDetection, in frame: (width: Int32, height: Int32)) -> Normalised? {
        guard pose.joints.count > noseIndex else { return nil }
        return normalised(pose.joints[noseIndex], in: frame)
    }

    /// A hand counts as raised when its wrist is visible and above the
    /// matching shoulder. Left/right are the subject's own.
    static func raisedHands(of pose: PoseDetection) -> (left: Bool, right: Bool) {
        guard pose.joints.count >= 11 else { return (false, false) }
        func raised(wrist: Int, shoulder: Int) -> Bool {
            let w = pose.joints[wrist], s = pose.joints[shoulder]
            return isVisible(w) && isVisible(s) && w.y < s.y
        }
        return (raised(wrist: leftWristIndex, shoulder: leftShoulderIndex),
                raised(wrist: rightWristIndex, shoulder: rightShoulderIndex))
    }

    // MARK: - Face box angles

    enum Turn: String, Sendable { case straight, left, right }
    enum Tilt: String, Sendable { case level, up, down }

    static func turn(of face: FaceBoxDetection, threshold: Float = 15) -> Turn {
        guard abs(face.yawDegrees) > threshold else { return .straight }
        let subjectLeft = (face.yawDegrees > 0) == positiveYawIsSubjectLeft
        return subjectLeft ? .left : .right
    }

    static func tilt(of face: FaceBoxDetection, threshold: Float = 12) -> Tilt {
        guard abs(face.pitchDegrees) > threshold else { return .level }
        return face.pitchDegrees > 0 ? .up : .down
    }

    // MARK: - 3D body

    static let rootIndex3D = 0

    /// Distance from the camera to the body's root joint, in metres.
    static func distance(of pose: Pose3DDetection) -> Double? {
        guard pose.joints.count > rootIndex3D else { return nil }
        let root = pose.joints[rootIndex3D]
        let d = (Double(root.x) * Double(root.x) + Double(root.y) * Double(root.y) + Double(root.z) * Double(root.z)).squareRoot()
        return d.isFinite && d > 0.05 ? d : nil
    }

    // MARK: - Words

    static func percent(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }
}
