/**
 * Joint orders, edge lists and colours for TrackOSC messages.
 *
 * TRACKOSC SKELETON REFERENCE v1.4 – source: PoseioscShared/Sources/PoseioscShared/Skeleton.swift
 * (full table in Examples/SKELETONS.md – keep this file in sync with it)
 *
 * Loads as a plain <script> (global `TrackOSCSkeletons`) and as a CommonJS
 * module for the Node tests.
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.TrackOSCSkeletons = factory();
}(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  const BODY_JOINTS = ["nose", "leftEye", "rightEye", "leftEar", "rightEar",
    "leftShoulder", "rightShoulder", "leftElbow", "rightElbow", "leftWrist", "rightWrist",
    "leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"];
  const BODY_EDGES = [
    [0, 1], [0, 2], [1, 3], [2, 4],            // head
    [5, 6], [5, 11], [6, 12], [11, 12],        // torso
    [5, 7], [7, 9],                            // left arm
    [6, 8], [8, 10],                           // right arm
    [11, 13], [13, 15],                        // left leg
    [12, 14], [14, 16],                        // right leg
  ];

  const HAND_JOINTS = ["wrist",
    "thumbCMC", "thumbMP", "thumbIP", "thumbTip", "indexMCP", "indexPIP", "indexDIP", "indexTip",
    "middleMCP", "middlePIP", "middleDIP", "middleTip", "ringMCP", "ringPIP", "ringDIP", "ringTip",
    "pinkyMCP", "pinkyPIP", "pinkyDIP", "pinkyTip"];
  const HAND_EDGES = [
    [0, 1], [1, 2], [2, 3], [3, 4],            // thumb
    [0, 5], [5, 6], [6, 7], [7, 8],            // index
    [0, 9], [9, 10], [10, 11], [11, 12],       // middle
    [0, 13], [13, 14], [14, 15], [15, 16],     // ring
    [0, 17], [17, 18], [18, 19], [19, 20],     // pinky
  ];

  const POSE3D_JOINTS = ["root", "spine", "centerShoulder", "centerHead", "topHead",
    "leftShoulder", "leftElbow", "leftWrist", "rightShoulder", "rightElbow", "rightWrist",
    "leftHip", "leftKnee", "leftAnkle", "rightHip", "rightKnee", "rightAnkle"];
  const POSE3D_EDGES = [
    [0, 1], [1, 2], [2, 3], [3, 4],            // root → spine → centerShoulder → centerHead → topHead
    [2, 5], [5, 6], [6, 7],                    // left arm
    [2, 8], [8, 9], [9, 10],                   // right arm
    [0, 11], [11, 12], [12, 13],               // left leg
    [0, 14], [14, 15], [15, 16],               // right leg
  ];

  const ANIMAL_JOINTS = ["nose", "leftEye", "rightEye",
    "leftEarTop", "leftEarMiddle", "leftEarBottom", "rightEarTop", "rightEarMiddle", "rightEarBottom",
    "neck", "leftFrontElbow", "leftFrontKnee", "leftFrontPaw", "rightFrontElbow", "rightFrontKnee", "rightFrontPaw",
    "leftBackElbow", "leftBackKnee", "leftBackPaw", "rightBackElbow", "rightBackKnee", "rightBackPaw",
    "tailTop", "tailMiddle", "tailBottom"];
  const ANIMAL_EDGES = [
    [0, 1], [0, 2],                            // nose → eyes
    [1, 5], [5, 4], [4, 3],                    // left ear
    [2, 8], [8, 7], [7, 6],                    // right ear
    [0, 9],                                    // nose → neck
    [9, 10], [10, 11], [11, 12],               // left front leg
    [9, 13], [13, 14], [14, 15],               // right front leg
    [9, 22],                                   // spine: neck → tailTop
    [22, 16], [16, 17], [17, 18],              // left back leg
    [22, 19], [19, 20], [20, 21],              // right back leg
    [22, 23], [23, 24],                        // tail
  ];

  // Barcode corners: topLeft, topRight, bottomRight, bottomLeft (closed quad).
  const BARCODE_CORNERS = ["topLeft", "topRight", "bottomRight", "bottomLeft"];

  // sRGB, matching the native apps.
  const COLOURS = {
    "/poses/arr": [48, 209, 88],
    "/poses3d/arr": [99, 230, 226],
    "/hands/arr": [255, 159, 10],
    "/faces/arr": [100, 210, 255],
    "/faces/box": [100, 210, 255],
    "/faces/contour": [100, 210, 255],
    "/texts/arr": [255, 214, 10],
    "/animals/arr": [255, 55, 95],
    "/animalposes/arr": [172, 142, 104],
    "/humans/arr": [94, 92, 230],
    "/barcodes/arr": [191, 90, 242],
    "/contours/arr": [230, 230, 230],
    "/horizon": [255, 69, 58],
    "/rectangles/arr": [64, 200, 224],
    guides: [128, 128, 128],
  };

  return { BODY_JOINTS, BODY_EDGES, HAND_JOINTS, HAND_EDGES, POSE3D_JOINTS, POSE3D_EDGES,
    ANIMAL_JOINTS, ANIMAL_EDGES, BARCODE_CORNERS, COLOURS };
}));
