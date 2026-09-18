// Joint orders, edge lists and colours for TrackOSC messages.
//
// TRACKOSC SKELETON REFERENCE v1.4 — source: PoseioscShared/Sources/PoseioscShared/Skeleton.swift
// (full table in Examples/SKELETONS.md — keep this file in sync with it)
#pragma once

#include "ofColor.h"
#include <array>
#include <string>
#include <utility>
#include <vector>

namespace trackosc {

using Edge = std::pair<int, int>;

inline const std::vector<std::string> BODY_JOINTS = {
    "nose", "leftEye", "rightEye", "leftEar", "rightEar",
    "leftShoulder", "rightShoulder", "leftElbow", "rightElbow",
    "leftWrist", "rightWrist", "leftHip", "rightHip",
    "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"};
inline const std::vector<Edge> BODY_EDGES = {
    {0, 1}, {0, 2}, {1, 3}, {2, 4},            // head
    {5, 6}, {5, 11}, {6, 12}, {11, 12},        // torso
    {5, 7}, {7, 9},                            // left arm
    {6, 8}, {8, 10},                           // right arm
    {11, 13}, {13, 15},                        // left leg
    {12, 14}, {14, 16}};                       // right leg

inline const std::vector<std::string> HAND_JOINTS = {
    "wrist",
    "thumbCMC", "thumbMP", "thumbIP", "thumbTip",
    "indexMCP", "indexPIP", "indexDIP", "indexTip",
    "middleMCP", "middlePIP", "middleDIP", "middleTip",
    "ringMCP", "ringPIP", "ringDIP", "ringTip",
    "pinkyMCP", "pinkyPIP", "pinkyDIP", "pinkyTip"};
inline const std::vector<Edge> HAND_EDGES = {
    {0, 1}, {1, 2}, {2, 3}, {3, 4},            // thumb
    {0, 5}, {5, 6}, {6, 7}, {7, 8},            // index
    {0, 9}, {9, 10}, {10, 11}, {11, 12},       // middle
    {0, 13}, {13, 14}, {14, 15}, {15, 16},     // ring
    {0, 17}, {17, 18}, {18, 19}, {19, 20}};    // pinky

inline const std::vector<std::string> POSE3D_JOINTS = {
    "root", "spine", "centerShoulder", "centerHead", "topHead",
    "leftShoulder", "leftElbow", "leftWrist",
    "rightShoulder", "rightElbow", "rightWrist",
    "leftHip", "leftKnee", "leftAnkle",
    "rightHip", "rightKnee", "rightAnkle"};
inline const std::vector<Edge> POSE3D_EDGES = {
    {0, 1}, {1, 2}, {2, 3}, {3, 4},            // root → spine → centerShoulder → centerHead → topHead
    {2, 5}, {5, 6}, {6, 7},                    // left arm
    {2, 8}, {8, 9}, {9, 10},                   // right arm
    {0, 11}, {11, 12}, {12, 13},               // left leg
    {0, 14}, {14, 15}, {15, 16}};              // right leg

inline const std::vector<std::string> ANIMAL_JOINTS = {
    "nose", "leftEye", "rightEye",
    "leftEarTop", "leftEarMiddle", "leftEarBottom",
    "rightEarTop", "rightEarMiddle", "rightEarBottom",
    "neck",
    "leftFrontElbow", "leftFrontKnee", "leftFrontPaw",
    "rightFrontElbow", "rightFrontKnee", "rightFrontPaw",
    "leftBackElbow", "leftBackKnee", "leftBackPaw",
    "rightBackElbow", "rightBackKnee", "rightBackPaw",
    "tailTop", "tailMiddle", "tailBottom"};
inline const std::vector<Edge> ANIMAL_EDGES = {
    {0, 1}, {0, 2},                            // nose → eyes
    {1, 5}, {5, 4}, {4, 3},                    // left ear
    {2, 8}, {8, 7}, {7, 6},                    // right ear
    {0, 9},                                    // nose → neck
    {9, 10}, {10, 11}, {11, 12},               // left front leg
    {9, 13}, {13, 14}, {14, 15},               // right front leg
    {9, 22},                                   // spine: neck → tailTop
    {22, 16}, {16, 17}, {17, 18},              // left back leg
    {22, 19}, {19, 20}, {20, 21},              // right back leg
    {22, 23}, {23, 24}};                       // tail

// Barcode corners: topLeft, topRight, bottomRight, bottomLeft (closed quad).

// sRGB, matching the native apps.
inline const ofColor POSE_COLOUR(48, 209, 88);
inline const ofColor POSE3D_COLOUR(99, 230, 226);
inline const ofColor HAND_COLOUR(255, 159, 10);
inline const ofColor FACE_COLOUR(100, 210, 255);
inline const ofColor TEXT_COLOUR(255, 214, 10);
inline const ofColor ANIMAL_COLOUR(255, 55, 95);
inline const ofColor ANIMALPOSE_COLOUR(172, 142, 104);
inline const ofColor HUMAN_COLOUR(94, 92, 230);
inline const ofColor BARCODE_COLOUR(191, 90, 242);
inline const ofColor GUIDE_COLOUR(128, 128, 128);

}  // namespace trackosc
