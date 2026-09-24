//
//  WireFormat.swift
//  PoseioscShared
//
//  OSC address patterns and joint orderings, byte-compatible with
//  LingDong-'s VisionOSC: https://github.com/LingDong-/VisionOSC
//

/// The five OSC address patterns emitted by VisionOSC (and by Poseiosc),
/// plus TrackOSC's additive messages (unknown to – and safely ignored by –
/// original VisionOSC receivers): /camerainfo (v1.1), /faces/box and
/// /faces/contour (v1.3), /poses3d/arr, /barcodes/arr, /animalposes/arr and
/// /humans/arr (v1.4).
public enum OSCAddress {
    public static let poses = "/poses/arr"
    public static let hands = "/hands/arr"
    public static let faces = "/faces/arr"
    public static let texts = "/texts/arr"
    public static let animals = "/animals/arr"
    public static let cameraInfo = "/camerainfo"
    public static let faceBox = "/faces/box"
    public static let faceContour = "/faces/contour"
    public static let poses3D = "/poses3d/arr"
    public static let barcodes = "/barcodes/arr"
    public static let animalPoses = "/animalposes/arr"
    public static let humans = "/humans/arr"
    // TrackOSC v1.6 additions.
    public static let contours = "/contours/arr"
    public static let horizon = "/horizon"
    public static let rectangles = "/rectangles/arr"

    public static let all: [String] = [
        poses, hands, faces, texts, animals, cameraInfo, faceBox, faceContour,
        poses3D, barcodes, animalPoses, humans,
        contours, horizon, rectangles
    ]
}

/// Fixed keypoint counts per detection type (VisionOSC constants.h, plus
/// TrackOSC's additions).
public enum WireCounts {
    public static let bodyJoints = 17
    public static let handJoints = 21
    public static let facePoints = 76
    /// Vision's 3D body skeleton (a different 17-joint set from PoseNet's).
    public static let body3DJoints = 17
    /// Vision's cat/dog skeleton.
    public static let animalJoints = 25
    /// Barcode quadrilateral corners: top-left, top-right, bottom-right, bottom-left.
    public static let barcodeCorners = 4
    /// VisionOSC caps detections at 32 per frame (MAX_DET).
    public static let maxDetections = 32
    /// Rectangle quadrilateral corners: top-left, top-right, bottom-right, bottom-left.
    public static let rectangleCorners = 4
    /// /contours/arr caps: contours per message and points across the whole
    /// message, so one datagram stays well under the 64 KB UDP limit.
    public static let maxContours = 64
    public static let maxContourPoints = 4000
}

/// Joint name orderings. The wire format carries no names – order is the contract.
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

    /// Vision's 3D body joints (VNHumanBodyPose3DObservation), root first so
    /// every parent precedes its children. Note this is NOT the PoseNet set:
    /// there are no eyes/ears, but there are spine, centre-shoulder and head joints.
    public static let body3D17: [String] = [
        "root", "spine", "centerShoulder", "centerHead", "topHead",
        "leftShoulder", "leftElbow", "leftWrist",
        "rightShoulder", "rightElbow", "rightWrist",
        "leftHip", "leftKnee", "leftAnkle",
        "rightHip", "rightKnee", "rightAnkle"
    ]

    /// Vision's 25 animal (cat/dog) joints (VNAnimalBodyPoseObservation),
    /// grouped head → neck → forelegs → hindlegs → tail.
    public static let animal25: [String] = [
        "nose", "leftEye", "rightEye",
        "leftEarTop", "leftEarMiddle", "leftEarBottom",
        "rightEarTop", "rightEarMiddle", "rightEarBottom",
        "neck",
        "leftFrontElbow", "leftFrontKnee", "leftFrontPaw",
        "rightFrontElbow", "rightFrontKnee", "rightFrontPaw",
        "leftBackElbow", "leftBackKnee", "leftBackPaw",
        "rightBackElbow", "rightBackKnee", "rightBackPaw",
        "tailTop", "tailMiddle", "tailBottom"
    ]
}
