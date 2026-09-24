//
//  Costume3DCoreTests.swift
//

import Foundation
import simd
import Testing
@testable import Costume3DCore

/// The T-pose as a live body (so the solver should reproduce the rest).
func tPoseLive() -> Live3D {
    let p = RestPose.tPosePositions
    let joints: [SIMD3<Float>] = [
        p["hips_joint"]!, p["spine_4_joint"]!, SIMD3<Float>(0, 1.40, 0), p["head_joint"]!, p["head_joint"]! + SIMD3<Float>(0, 0.12, 0),
        p["left_arm_joint"]!, p["left_forearm_joint"]!, p["left_hand_joint"]!,
        p["right_arm_joint"]!, p["right_forearm_joint"]!, p["right_hand_joint"]!,
        p["left_upLeg_joint"]!, p["left_leg_joint"]!, p["left_foot_joint"]!,
        p["right_upLeg_joint"]!, p["right_leg_joint"]!, p["right_foot_joint"]!,
    ]
    return Live3D(joints: joints, bodyHeight: 1.75)
}

func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ tol: Float = 0.01) -> Bool { simd_length(a - b) < tol }

@Suite("Rig table")
struct RigTests {
    @Test func appleRigIsCompleteAndOrdered() {
        #expect(AppleRig.joints.count == 91)
        #expect(AppleRig.joints[0].name == "root")
        var seen: Set<String> = []
        for j in AppleRig.joints {
            if let p = j.parent { #expect(seen.contains(p), "\(j.name) before its parent \(p)") }
            seen.insert(j.name)
        }
        #expect(Set(AppleRig.names).count == 91)
        #expect(AppleRig.path(of: "left_forearm_joint") == "root/hips_joint/spine_1_joint/spine_2_joint/spine_3_joint/spine_4_joint/spine_5_joint/spine_6_joint/spine_7_joint/left_shoulder_1_joint/left_arm_joint/left_forearm_joint")
        #expect(AppleRig.driven.allSatisfy { AppleRig.parentByName[$0] != nil })
    }

    @Test func validationListsMissingJoints() {
        let paths = AppleRig.names.filter { $0 != "left_forearm_joint" && $0 != "jaw_joint" }.map(AppleRig.path(of:))
        let (driven, other) = AppleRig.validate(jointPaths: paths)
        #expect(driven == ["left_forearm_joint"])
        #expect(other == ["jaw_joint"])
    }

    @Test func tPoseRestHasBonesAlongX() {
        let rest = RestPose.tPose()
        #expect(rest.count == 91)
        let world = rest.worldTransforms()
        // World positions round-trip.
        for (i, path) in rest.paths.enumerated() {
            let name = AppleRig.name(fromPath: path)
            #expect(near(world.positions[i], RestPose.tPosePositions[name]!, 0.001), Comment(rawValue: name))
        }
        // The left arm's +X points along +X (towards the forearm), the spine's along +Y.
        let arm = rest.index(of: "left_arm_joint")!
        #expect(near(world.rotations[arm].act(SIMD3<Float>(1, 0, 0)), SIMD3<Float>(1, 0, 0), 0.001))
        let spine = rest.index(of: "spine_3_joint")!
        #expect(near(world.rotations[spine].act(SIMD3<Float>(1, 0, 0)), SIMD3<Float>(0, 1, 0), 0.001))
        #expect(abs(Retarget17.restHeight(rest) - 1.67) < 0.05)
    }
}

@Suite("FK solver")
struct FKTests {
    @Test func tPoseLiveReproducesTheRest() {
        let rest = RestPose.tPose()
        var solver = FKSolver()
        solver.smoothing = 0
        let result = solver.solve(rest: rest, live: tPoseLive(), deltaTime: 1)!
        // Feet are aimed flat and forward by design, so they differ from the rest's toe-ward axis.
        for i in 0..<rest.count where AppleRig.driven.contains(AppleRig.name(fromPath: rest.paths[i])) && !rest.paths[i].contains("foot") {
            let d = simd_dot(result.localRotations[i].vector, rest.localRotations[i].vector)
            #expect(abs(d) > 0.999, Comment(rawValue: rest.paths[i]))
        }
        #expect(near(result.hipsPosition, RestPose.tPosePositions["hips_joint"]!))
        #expect(abs(result.scale - 1.75 / Retarget17.restHeight(rest)) < 0.001)
    }

    @Test func bentElbowRotatesTheForearmAndLandsTheWrist() {
        let rest = RestPose.tPose()
        var solver = FKSolver()
        solver.smoothing = 0
        var live = tPoseLive()
        // Bend the left elbow 90° forward: the wrist moves to +Z of the elbow.
        let elbow = live.joints[Body3D.leftElbow]
        live.joints[Body3D.leftWrist] = elbow + SIMD3<Float>(0, 0, 0.26)
        let result = solver.solve(rest: rest, live: live, deltaTime: 1)!
        let forearm = rest.index(of: "left_forearm_joint")!
        let angle = result.localRotations[forearm].angle
        #expect(abs(angle - .pi / 2) < 0.02)
        // Forward kinematics with the rest lengths puts the hand joint at the live wrist.
        var world = [SIMD3<Float>](repeating: .zero, count: rest.count)
        for i in 0..<rest.count {
            let p = rest.parents[i]
            world[i] = p < 0 ? rest.localTranslations[i] : world[p] + result.worldRotations[p].act(rest.localTranslations[i])
        }
        let hand = rest.index(of: "left_hand_joint")!
        #expect(near(world[hand], live.joints[Body3D.leftWrist], 0.02))
        // The upper arm is unchanged.
        let arm = rest.index(of: "left_arm_joint")!
        #expect(abs(simd_dot(result.localRotations[arm].vector, rest.localRotations[arm].vector)) > 0.999)
    }

    @Test func turningTheHipsYawsTheWholeBody() {
        let rest = RestPose.tPose()
        var solver = FKSolver()
        solver.smoothing = 0
        var live = tPoseLive()
        // Rotate every live joint 90° about +Y.
        let q = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
        live.joints = live.joints.map { q.act($0) }
        let result = solver.solve(rest: rest, live: live, deltaTime: 1)!
        let hips = rest.index(of: "hips_joint")!
        // The hips' +Y (the character's right) now points where the rotated −X went.
        let right = result.worldRotations[hips].act(SIMD3<Float>(0, 1, 0))
        #expect(near(right, q.act(SIMD3<Float>(-1, 0, 0)), 0.02))
        // And the left arm's +X follows.
        let arm = rest.index(of: "left_arm_joint")!
        #expect(near(result.worldRotations[arm].act(SIMD3<Float>(1, 0, 0)), q.act(SIMD3<Float>(1, 0, 0)), 0.02))
    }

    @Test func missingBodyHoldsAndSmoothingApproaches() {
        let rest = RestPose.tPose()
        var solver = FKSolver()
        solver.smoothing = 0.5
        var live = tPoseLive()
        _ = solver.solve(rest: rest, live: live, deltaTime: 1)
        live.joints[Body3D.root].x += 1
        let half = solver.solve(rest: rest, live: live, deltaTime: 0.25)!
        #expect(abs(half.hipsPosition.x - 0.5) < 0.01)
        let held = solver.solve(rest: rest, live: nil, deltaTime: 0.25)!
        #expect(abs(held.hipsPosition.x - 0.75) < 0.01)   // still approaching the last live body
        #expect(solver.solve(rest: rest, live: nil, deltaTime: 10)!.hipsPosition.x > 0.99)
    }
}

@Suite("Parts")
struct PartsTests {
    @Test func fileNamesMatchBones() {
        #expect(PartBone.match(fileName: "forearm-left") == .forearmLeft)
        #expect(PartBone.match(fileName: "Left_Forearm") == .forearmLeft)
        #expect(PartBone.match(fileName: "upperArmRight") == .upperArmRight)
        #expect(PartBone.match(fileName: "torso") == .torso)
        #expect(PartBone.match(fileName: "hat") == nil)
    }

    @Test func placementMapsArtAxisOntoSegment() {
        // A part 0.5 tall from y 0…0.5 (vertical: axis top→bottom), hung on a bone from (1,2,0) to (1,1,0).
        let axis = PartsMath.axis(ofBounds: SIMD3<Float>(-0.05, 0, -0.05), SIMD3<Float>(0.05, 0.5, 0.05))
        #expect(axis.start == SIMD3<Float>(0, 0.5, 0) && axis.end == SIMD3<Float>(0, 0, 0))
        let p = PartsMath.place(artAxis: axis, on: (SIMD3<Float>(1, 2, 0), SIMD3<Float>(1, 1, 0)))
        #expect(abs(p.scale - 2) < 0.001)
        let start = p.position + p.rotation.act(axis.start * p.scale)
        let end = p.position + p.rotation.act(axis.end * p.scale)
        #expect(near(start, SIMD3<Float>(1, 2, 0)))
        #expect(near(end, SIMD3<Float>(1, 1, 0)))
        // A horizontal part onto a diagonal bone.
        let axis2 = PartsMath.axis(ofBounds: SIMD3<Float>(0, -0.1, -0.1), SIMD3<Float>(1, 0.1, 0.1))
        let p2 = PartsMath.place(artAxis: axis2, on: (SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 0)))
        #expect(near(p2.position + p2.rotation.act(axis2.end * p2.scale), SIMD3<Float>(1, 1, 0)))
        let segment = PartBone.forearmLeft.segment(in: tPoseLive())!
        #expect(near(segment.0, RestPose.tPosePositions["left_forearm_joint"]!))
    }

    @Test func blockyUSDAHasTheSkeletonAndSkinning() {
        let usda = USDAWriter.blocky()
        #expect(usda.hasPrefix("#usda 1.0"))
        #expect(usda.contains("def Skeleton \"Skeleton\""))
        #expect(usda.contains("\"root/hips_joint/spine_1_joint\""))
        #expect(usda.contains("primvars:skel:jointIndices"))
        let blocks = USDAWriter.blockyBlocks.count
        #expect(usda.components(separatedBy: "4, 4, 4, 4, 4, 4").count - 1 >= 1)
        // 8 points per block.
        let pointsLine = usda.components(separatedBy: "point3f[] points = [")[1].components(separatedBy: "]")[0]
        #expect(pointsLine.components(separatedBy: "), (").count == blocks * 8)
    }
}
