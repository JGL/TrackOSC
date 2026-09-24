//
//  Pose3DScene.swift
//  TrackOSC Receiver (macOS)
//
//  The RealityKit scene graph behind the 3D visualiser: a floor grid, an
//  axis gnomon and camera marker at the origin, and a pool of skeleton
//  entities (joint spheres + bone cylinders) reused across frames so nothing
//  is allocated per tick.
//
//  The floor, gnomon and camera are the shared Stage3D (ReceiverCore/Scene3D);
//  units are metres straight from /poses3d/arr, with the sign of z set once
//  in Stage3D.axisSign after the on-device check.
//

import AppKit
import PoseioscShared
import RealityKit
import simd

@MainActor
final class Pose3DScene {
    /// The shared stage (floor, gnomon, camera); the skeleton pool hangs off its root.
    let stage = Stage3D()
    var root: Entity { stage.root }
    var camera: PerspectiveCamera { stage.camera }
    static var defaultTarget: SIMD3<Float> { Stage3D.defaultTarget }

    private var pool: [PoseEntitySet] = []

    private let jointMesh = MeshResource.generateSphere(radius: 0.03)
    private let boneMesh = MeshResource.generateCylinder(height: 1, radius: 0.012)
    private let poseMaterial = UnlitMaterial(color: NSColor.systemMint)

    private struct PoseEntitySet {
        let root: Entity
        let joints: [ModelEntity]
        let bones: [ModelEntity]
    }

    init() {}

    func placeCamera(_ orbit: OrbitState) { stage.placeCamera(orbit) }

    // MARK: - Per-frame update

    func update(poses: [Pose3DDetection]) {
        while pool.count < poses.count {
            pool.append(makePoseEntities())
        }

        var minAnkleY: Float?
        for (index, set) in pool.enumerated() {
            guard index < poses.count else {
                set.root.isEnabled = false
                continue
            }
            set.root.isEnabled = true
            let joints = poses[index].joints.map { Self.scenePosition($0) }
            for (jointIndex, joint) in set.joints.enumerated() {
                joint.position = joints[jointIndex]
            }
            for (edgeIndex, (a, b)) in Skeleton.body3D17Edges.enumerated() {
                Self.place(bone: set.bones[edgeIndex], from: joints[a], to: joints[b])
            }
            // Ankles are indices 13 and 16 in JointOrder.body3D17.
            let ankleY = min(joints[13].y, joints[16].y)
            minAnkleY = min(minAnkleY ?? ankleY, ankleY)
        }

        stage.settleFloor(under: minAnkleY)
    }

    static func scenePosition(_ joint: WirePoint3D) -> SIMD3<Float> {
        Stage3D.scenePosition(x: joint.x, y: joint.y, z: joint.z)
    }

    private func makePoseEntities() -> PoseEntitySet {
        let poseRoot = Entity()
        root.addChild(poseRoot)
        let joints = (0..<WireCounts.body3DJoints).map { _ in
            let entity = ModelEntity(mesh: jointMesh, materials: [poseMaterial])
            poseRoot.addChild(entity)
            return entity
        }
        let bones = Skeleton.body3D17Edges.map { _ in
            let entity = ModelEntity(mesh: boneMesh, materials: [poseMaterial])
            poseRoot.addChild(entity)
            return entity
        }
        return PoseEntitySet(root: poseRoot, joints: joints, bones: bones)
    }

    /// Positions a unit cylinder (along +y) between two points by moving,
    /// rotating and stretching it – no geometry rebuilds.
    private static func place(bone: ModelEntity, from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let delta = b - a
        let length = simd_length(delta)
        guard length > 1e-4 else {
            bone.isEnabled = false
            return
        }
        bone.isEnabled = true
        bone.position = (a + b) / 2
        bone.scale = SIMD3<Float>(1, length, 1)
        let up = SIMD3<Float>(0, 1, 0)
        let direction = delta / length
        if simd_dot(up, direction) < -0.9999 {
            bone.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        } else {
            bone.orientation = simd_quatf(from: up, to: direction)
        }
    }
}
