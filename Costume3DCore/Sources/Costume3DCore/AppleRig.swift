//
//  AppleRig.swift
//  Costume3DCore
//
//  Apple's motion-capture skeleton (the rig ARKit's body tracking drives
//  and the Biped Robot sample uses): 91 joints, their hierarchy, and the
//  handful TrackOSC drives from the 17-joint /poses3d/arr stream. A model
//  must use exactly these names in this hierarchy; +Y up, facing +Z, the
//  character's left hand along +X, and each joint's +X pointing down its
//  bone. Source: "Validating a Model for Motion Capture" (Apple).
//

import Foundation
import simd

public enum AppleRig {
    /// Every joint with its parent, root first, parents before children.
    public static let joints: [(name: String, parent: String?)] = {
        var list: [(String, String?)] = [
            ("root", nil), ("hips_joint", "root"),
            ("spine_1_joint", "hips_joint"), ("spine_2_joint", "spine_1_joint"), ("spine_3_joint", "spine_2_joint"), ("spine_4_joint", "spine_3_joint"),
            ("spine_5_joint", "spine_4_joint"), ("spine_6_joint", "spine_5_joint"), ("spine_7_joint", "spine_6_joint"),
            ("neck_1_joint", "spine_7_joint"), ("neck_2_joint", "neck_1_joint"), ("neck_3_joint", "neck_2_joint"), ("neck_4_joint", "neck_3_joint"),
            ("head_joint", "neck_4_joint"), ("jaw_joint", "head_joint"), ("chin_joint", "jaw_joint"), ("nose_joint", "head_joint"),
            ("right_eye_joint", "head_joint"), ("right_eyeUpperLid_joint", "right_eye_joint"), ("right_eyeLowerLid_joint", "right_eye_joint"), ("right_eyeball_joint", "right_eye_joint"),
            ("left_eye_joint", "head_joint"), ("left_eyeUpperLid_joint", "left_eye_joint"), ("left_eyeLowerLid_joint", "left_eye_joint"), ("left_eyeball_joint", "left_eye_joint"),
        ]
        for side in ["right", "left"] {
            list += [
                ("\(side)_shoulder_1_joint", "spine_7_joint"), ("\(side)_arm_joint", "\(side)_shoulder_1_joint"),
                ("\(side)_forearm_joint", "\(side)_arm_joint"), ("\(side)_hand_joint", "\(side)_forearm_joint"),
            ]
            for finger in ["Pinky", "Ring", "Mid", "Index"] {
                list += [
                    ("\(side)_hand\(finger)Start_joint", "\(side)_hand_joint"), ("\(side)_hand\(finger)_1_joint", "\(side)_hand\(finger)Start_joint"),
                    ("\(side)_hand\(finger)_2_joint", "\(side)_hand\(finger)_1_joint"), ("\(side)_hand\(finger)_3_joint", "\(side)_hand\(finger)_2_joint"),
                    ("\(side)_hand\(finger)End_joint", "\(side)_hand\(finger)_3_joint"),
                ]
            }
            list += [
                ("\(side)_handThumbStart_joint", "\(side)_hand_joint"), ("\(side)_handThumb_1_joint", "\(side)_handThumbStart_joint"),
                ("\(side)_handThumb_2_joint", "\(side)_handThumb_1_joint"), ("\(side)_handThumbEnd_joint", "\(side)_handThumb_2_joint"),
            ]
        }
        for side in ["left", "right"] {
            list += [
                ("\(side)_upLeg_joint", "hips_joint"), ("\(side)_leg_joint", "\(side)_upLeg_joint"), ("\(side)_foot_joint", "\(side)_leg_joint"),
                ("\(side)_toes_joint", "\(side)_foot_joint"), ("\(side)_toesEnd_joint", "\(side)_toes_joint"),
            ]
        }
        return list.map { (name: $0.0, parent: $0.1) }
    }()

    public static let names: [String] = joints.map(\.name)
    public static let parentByName: [String: String?] = Dictionary(uniqueKeysWithValues: joints.map { ($0.name, $0.parent) })

    /// "root/hips_joint/spine_1_joint": the path RealityKit reports in `jointNames`.
    public static func path(of name: String) -> String {
        var parts = [name]
        var current = name
        while let parent = parentByName[current] ?? nil { parts.insert(parent, at: 0); current = parent }
        return parts.joined(separator: "/")
    }

    /// The last path component of a RealityKit joint path.
    public static func name(fromPath path: String) -> String { path.split(separator: "/").last.map(String.init) ?? path }

    /// Joints the rig needs for the 17-joint stream to drive it; the rest may be unskinned.
    public static let driven: [String] = [
        "hips_joint", "spine_1_joint", "spine_2_joint", "spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint", "spine_7_joint",
        "neck_1_joint", "neck_2_joint", "neck_3_joint", "neck_4_joint", "head_joint",
        "left_shoulder_1_joint", "left_arm_joint", "left_forearm_joint", "left_hand_joint",
        "right_shoulder_1_joint", "right_arm_joint", "right_forearm_joint", "right_hand_joint",
        "left_upLeg_joint", "left_leg_joint", "left_foot_joint", "right_upLeg_joint", "right_leg_joint", "right_foot_joint",
    ]

    /// Missing joints (by name) in a loaded model's joint list, driven ones first.
    public static func validate(jointPaths: [String]) -> (missingDriven: [String], missingOther: [String]) {
        let present = Set(jointPaths.map(name(fromPath:)))
        let drivenSet = Set(driven)
        var missingDriven: [String] = [], missingOther: [String] = []
        for name in names where !present.contains(name) {
            if drivenSet.contains(name) { missingDriven.append(name) } else { missingOther.append(name) }
        }
        return (missingDriven, missingOther)
    }
}

/// The 17 joints of /poses3d/arr (JointOrder.body3D17), metres, camera space.
public enum Body3D {
    public static let root = 0, spine = 1, centerShoulder = 2, centerHead = 3, topHead = 4
    public static let leftShoulder = 5, leftElbow = 6, leftWrist = 7
    public static let rightShoulder = 8, rightElbow = 9, rightWrist = 10
    public static let leftHip = 11, leftKnee = 12, leftAnkle = 13
    public static let rightHip = 14, rightKnee = 15, rightAnkle = 16
    public static let edges: [(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 4), (2, 5), (5, 6), (6, 7), (2, 8), (8, 9), (9, 10), (0, 11), (11, 12), (12, 13), (0, 14), (14, 15), (15, 16)]
}

/// One tracked 3D body: 17 joints in Body3D order.
public struct Live3D: Sendable {
    public var joints: [SIMD3<Float>]
    public var bodyHeight: Float
    public init(joints: [SIMD3<Float>], bodyHeight: Float) {
        self.joints = joints
        self.bodyHeight = bodyHeight
    }
}
