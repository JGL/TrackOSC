//
//  AttractScene.swift
//  TrackOSC (ReceiverCore)
//
//  A synthetic person who wanders and waves when no one is being tracked,
//  so an installation never shows a dead screen. Same joint order as the
//  real thing, so every mode draws it without knowing.
//

import Foundation
import simd

struct AttractScene: Sendable {
    func scene(at time: Float, dt: Float, aspect: Float) -> TrackingScene {
        let t = time
        let cx: Float = 0.5 + sinf(t * 0.35) * 0.22
        let bob: Float = sinf(t * 2.4) * 0.008
        let sway: Float = sinf(t * 1.2) * 0.03
        let step: Float = sinf(t * 2.4) * 0.05
        let wave: Float = sinf(t * 3.0) * 0.08

        let headY: Float = 0.22 + bob
        let shoulderY: Float = 0.33 + bob
        let hipY: Float = 0.55 + bob
        let kneeY: Float = 0.72 + bob
        let ankleY: Float = 0.88 + bob
        let halfShoulder: Float = 0.075 / max(aspect, 0.5)
        let halfHip: Float = 0.055 / max(aspect, 0.5)

        let joints: [SIMD2<Float>] = [
            SIMD2(cx, headY),                                         // nose
            SIMD2(cx - 0.02, headY - 0.015), SIMD2(cx + 0.02, headY - 0.015),  // eyes
            SIMD2(cx - 0.04, headY - 0.005), SIMD2(cx + 0.04, headY - 0.005),  // ears
            SIMD2(cx - halfShoulder, shoulderY), SIMD2(cx + halfShoulder, shoulderY),
            SIMD2(cx - halfShoulder - 0.05 + sway, shoulderY + 0.12),       // left elbow
            SIMD2(cx + halfShoulder + 0.06, shoulderY - 0.02 + wave * 0.5), // right elbow (waving)
            SIMD2(cx - halfShoulder - 0.06 + sway, shoulderY + 0.25),       // left wrist
            SIMD2(cx + halfShoulder + 0.09, shoulderY - 0.16 + wave),       // right wrist
            SIMD2(cx - halfHip, hipY), SIMD2(cx + halfHip, hipY),
            SIMD2(cx - halfHip - step * 0.3, kneeY), SIMD2(cx + halfHip + step * 0.3, kneeY),
            SIMD2(cx - halfHip - step, ankleY), SIMD2(cx + halfHip + step, ankleY),
        ]
        let person = ScenePerson(
            id: 0, joints: joints, visible: Array(repeating: true, count: 17),
            velocities: Array(repeating: .zero, count: 17),
            centroid: SIMD2(cx, 0.5 + bob), boundingBox: (SIMD2(cx - 0.15, headY - 0.05), SIMD2(cx + 0.15, ankleY)),
            hands: [], face: nil, age: t, confidence: 1, speed: 0.15
        )
        return TrackingScene(time: t, deltaTime: dt, frameAspect: aspect, persons: [person], hands: [], faces: [],
                             texts: [], presence: 0.6, activity: 0.3, isAttract: true)
    }
}
