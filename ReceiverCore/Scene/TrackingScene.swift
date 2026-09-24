//
//  TrackingScene.swift
//  TrackOSC (ReceiverCore)
//
//  The frame every visual app draws from: people with stable identities
//  and smoothed joints in normalised 0–1 coordinates (x across, y down,
//  mirrored when the display setting says so), their hands and faces,
//  recognised text and codes, and two scalar moods – presence and
//  activity. Built at display rate from the receiver's latest frames.
//

import Foundation
import simd
import PoseioscShared

/// A 2D point in the scene's normalised space.
typealias ScenePoint = SIMD2<Float>

struct SceneHand: Sendable, Equatable {
    /// 21 joints in JointOrder.hand21, normalised; `visible` mirrors confidence > 0.
    var joints: [ScenePoint]
    var visible: [Bool]
    var centre: ScenePoint
    /// 0 = fist, 1 = fully spread: mean fingertip distance from the wrist over hand size.
    var openness: Float
    /// A guess from which wrist of the owning person is nearest; nil when unknown.
    var isLeft: Bool?
    var personID: Int?
}

struct SceneFace: Sendable, Equatable {
    var centre: ScenePoint
    var size: ScenePoint
    var yawDegrees: Float
    var pitchDegrees: Float
    var rollDegrees: Float
    /// 0 closed … about 1 wide open (from the landmarks when present).
    var mouthOpenness: Float
    /// 76 landmarks, normalised, when /faces/arr is arriving.
    var landmarks: [ScenePoint]
    var personID: Int?
}

struct ScenePerson: Sendable, Equatable, Identifiable {
    let id: Int
    /// 17 joints in JointOrder.body17, normalised and smoothed.
    var joints: [ScenePoint]
    var visible: [Bool]
    /// Per-joint velocity in scene units per second.
    var velocities: [ScenePoint]
    var centroid: ScenePoint
    var boundingBox: (min: ScenePoint, max: ScenePoint)
    var hands: [SceneHand]
    var face: SceneFace?
    /// Seconds since this identity first appeared.
    var age: Float
    /// 0 when the person has just gone missing (grace period), else 1.
    var confidence: Float
    /// Mean joint speed, scene units per second, smoothed.
    var speed: Float

    static func == (lhs: ScenePerson, rhs: ScenePerson) -> Bool {
        lhs.id == rhs.id && lhs.joints == rhs.joints && lhs.confidence == rhs.confidence
    }
}

/// A cat or dog from /animalposes/arr: 25 joints in JointOrder.animal25.
struct SceneAnimal: Sendable, Equatable, Identifiable {
    let id: Int
    var joints: [ScenePoint]
    var visible: [Bool]
    var velocities: [ScenePoint]
    var centroid: ScenePoint
    var age: Float
    var confidence: Float
    var speed: Float

    static func == (lhs: SceneAnimal, rhs: SceneAnimal) -> Bool {
        lhs.id == rhs.id && lhs.joints == rhs.joints && lhs.confidence == rhs.confidence
    }
}

struct SceneText: Sendable, Equatable {
    var text: String
    var centre: ScenePoint
    var size: ScenePoint
    var isCode: Bool
}

struct TrackingScene: Sendable {
    var time: Float = 0
    var deltaTime: Float = 1 / 60
    /// Width / height of the sender's frame (1 when unknown).
    var frameAspect: Float = 1
    var persons: [ScenePerson] = []
    /// Hands not attached to anyone, plus copies of every attached one.
    var hands: [SceneHand] = []
    var faces: [SceneFace] = []
    var animals: [SceneAnimal] = []
    var texts: [SceneText] = []
    /// 0 … 1, how much someone has been here recently (smoothed).
    var presence: Float = 0
    /// 0 … 1, how much movement there is (smoothed, saturating).
    var activity: Float = 0
    /// True while the attract scene is standing in for real tracking.
    var isAttract = false
    var isLive: Bool { !persons.isEmpty || !hands.isEmpty || !faces.isEmpty || !animals.isEmpty }

    static let empty = TrackingScene()
}
