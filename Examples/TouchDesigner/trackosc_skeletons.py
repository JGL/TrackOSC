"""Joint orders and edge lists for TrackOSC messages – paste into a Text DAT
named ``trackosc_skeletons`` and import it with ``mod.trackosc_skeletons``.

TRACKOSC SKELETON REFERENCE v1.4 – source: PoseioscShared/Sources/PoseioscShared/Skeleton.swift
(full table in Examples/SKELETONS.md – keep this file in sync with it)
"""

BODY_JOINTS = [
    "nose", "leftEye", "rightEye", "leftEar", "rightEar",
    "leftShoulder", "rightShoulder", "leftElbow", "rightElbow",
    "leftWrist", "rightWrist", "leftHip", "rightHip",
    "leftKnee", "rightKnee", "leftAnkle", "rightAnkle",
]
BODY_EDGES = [
    (0, 1), (0, 2), (1, 3), (2, 4), (5, 6), (5, 11), (6, 12), (11, 12),
    (5, 7), (7, 9), (6, 8), (8, 10), (11, 13), (13, 15), (12, 14), (14, 16),
]

HAND_JOINTS = [
    "wrist",
    "thumbCMC", "thumbMP", "thumbIP", "thumbTip",
    "indexMCP", "indexPIP", "indexDIP", "indexTip",
    "middleMCP", "middlePIP", "middleDIP", "middleTip",
    "ringMCP", "ringPIP", "ringDIP", "ringTip",
    "pinkyMCP", "pinkyPIP", "pinkyDIP", "pinkyTip",
]
HAND_EDGES = [
    (0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8),
    (0, 9), (9, 10), (10, 11), (11, 12), (0, 13), (13, 14), (14, 15), (15, 16),
    (0, 17), (17, 18), (18, 19), (19, 20),
]

POSE3D_JOINTS = [
    "root", "spine", "centerShoulder", "centerHead", "topHead",
    "leftShoulder", "leftElbow", "leftWrist",
    "rightShoulder", "rightElbow", "rightWrist",
    "leftHip", "leftKnee", "leftAnkle",
    "rightHip", "rightKnee", "rightAnkle",
]
POSE3D_EDGES = [
    (0, 1), (1, 2), (2, 3), (3, 4), (2, 5), (5, 6), (6, 7), (2, 8), (8, 9), (9, 10),
    (0, 11), (11, 12), (12, 13), (0, 14), (14, 15), (15, 16),
]

ANIMAL_JOINTS = [
    "nose", "leftEye", "rightEye",
    "leftEarTop", "leftEarMiddle", "leftEarBottom",
    "rightEarTop", "rightEarMiddle", "rightEarBottom",
    "neck",
    "leftFrontElbow", "leftFrontKnee", "leftFrontPaw",
    "rightFrontElbow", "rightFrontKnee", "rightFrontPaw",
    "leftBackElbow", "leftBackKnee", "leftBackPaw",
    "rightBackElbow", "rightBackKnee", "rightBackPaw",
    "tailTop", "tailMiddle", "tailBottom",
]
ANIMAL_EDGES = [
    (0, 1), (0, 2), (1, 5), (5, 4), (4, 3), (2, 8), (8, 7), (7, 6), (0, 9),
    (9, 10), (10, 11), (11, 12), (9, 13), (13, 14), (14, 15), (9, 22),
    (22, 16), (16, 17), (17, 18), (22, 19), (19, 20), (20, 21), (22, 23), (23, 24),
]

# Barcode corners: topLeft, topRight, bottomRight, bottomLeft (closed quad).
BARCODE_CORNERS = ["topLeft", "topRight", "bottomRight", "bottomLeft"]

KEYPOINT_KINDS = {
    "/poses/arr": ("poses", BODY_JOINTS, BODY_EDGES),
    "/hands/arr": ("hands", HAND_JOINTS, HAND_EDGES),
    "/faces/arr": ("faces", None, None),          # 76 landmarks, no names or edges
    "/animalposes/arr": ("animalposes", ANIMAL_JOINTS, ANIMAL_EDGES),
}
