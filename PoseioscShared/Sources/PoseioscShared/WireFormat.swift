//
//  WireFormat.swift
//  PoseioscShared
//
//  OSC address patterns and joint orderings, byte-compatible with
//  LingDong-'s VisionOSC: https://github.com/LingDong-/VisionOSC
//

/// The five OSC address patterns emitted by VisionOSC (and by Poseiosc),
/// plus TrackOSC's additive messages (unknown to — and safely ignored by —
/// original VisionOSC receivers): /camerainfo (v1.1), /faces/box and
/// /faces/contour (v1.3).
public enum OSCAddress {
    public static let poses = "/poses/arr"
    public static let hands = "/hands/arr"
    public static let faces = "/faces/arr"
    public static let texts = "/texts/arr"
    public static let animals = "/animals/arr"
    public static let cameraInfo = "/camerainfo"
    public static let faceBox = "/faces/box"
    public static let faceContour = "/faces/contour"

    public static let all: [String] = [poses, hands, faces, texts, animals, cameraInfo, faceBox, faceContour]
}

/// Fixed keypoint counts per detection type (VisionOSC constants.h).
public enum WireCounts {
    public static let bodyJoints = 17
    public static let handJoints = 21
    public static let facePoints = 76
    /// VisionOSC caps detections at 32 per frame (MAX_DET).
    public static let maxDetections = 32
}

/// Joint name orderings. The wire format carries no names — order is the contract.
public enum JointOrder {
    /// PoseNet/PoseOSC body joint order used by VisionOSC.
    public static let body17: [String] = [
        "nose", "leftEye", "rightEye", "leftEar", "rightEar",
        "leftShoulder", "rightShoulder", "leftElbow", "rightElbow",
        "leftWrist", "rightWrist", "leftHip", "rightHip",
        "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"
    ]

    /// MediaPipe-style hand joint order used by VisionOSC.
    /// Apple's "little" finger joints are named "pinky" here, matching VisionOSC.
    public static let hand21: [String] = [
        "wrist",
        "thumbCMC", "thumbMP", "thumbIP", "thumbTip",
        "indexMCP", "indexPIP", "indexDIP", "indexTip",
        "middleMCP", "middlePIP", "middleDIP", "middleTip",
        "ringMCP", "ringPIP", "ringDIP", "ringTip",
        "pinkyMCP", "pinkyPIP", "pinkyDIP", "pinkyTip"
    ]
}
