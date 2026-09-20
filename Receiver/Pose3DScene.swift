//
//  Pose3DScene.swift
//  TrackOSC Receiver (macOS)
//
//  The RealityKit scene graph behind the 3D visualiser: a floor grid, an
//  axis gnomon and camera marker at the origin, and a pool of skeleton
//  entities (joint spheres + bone cylinders) reused across frames so nothing
//  is allocated per tick.
//
//  Units are metres, straight from /poses3d/arr. Vision's camera-relative
//  space and RealityKit's are both right-handed with y up, so the only
//  question is the sign of z (which way is "in front of the camera"); that
//  is confirmed on device and set once in `axisSign`.
//

import AppKit
import PoseioscShared
import RealityKit
import simd

@MainActor
final class Pose3DScene {
    /// Vision camera space → RealityKit space. Flip a component here after
    /// the on-device check (a subject in front of the camera must appear in
    /// front of the camera marker, a raised hand must go up, and the
    /// subject's left must be on the camera's right).
    static let axisSign = SIMD3<Float>(1, 1, 1)

    /// Where the orbit camera looks: a couple of metres in front of the
    /// camera marker, at roughly hip height.
    static let defaultTarget = SIMD3<Float>(0, -0.2, 2.0) * axisSign

    /// Everything in the scene hangs off this.
    let root = Entity()
    /// The viewing camera, orbited around `defaultTarget` by the view.
    let camera = PerspectiveCamera()

    private let floor = Entity()
    private var floorY: Float = -1.2
    private var pool: [PoseEntitySet] = []

    private let jointMesh = MeshResource.generateSphere(radius: 0.03)
    private let boneMesh = MeshResource.generateCylinder(height: 1, radius: 0.012)
    private let poseMaterial = UnlitMaterial(color: NSColor.systemMint)

    private struct PoseEntitySet {
        let root: Entity
        let joints: [ModelEntity]
        let bones: [ModelEntity]
    }

    init() {
        root.addChild(floor)
        buildFloor()
        buildGnomonAndCameraMarker()
        camera.camera.near = 0.05
        camera.camera.far = 60
        root.addChild(camera)
    }

    /// Places the camera on a sphere around the target (azimuth around y,
    /// measured from the side of the target that faces the camera marker)
    /// and points it at the target.
    func placeCamera(_ orbit: Visualizer3DView.OrbitState) {
        let target = Self.defaultTarget
        let towardsMarker: Float = target.z >= 0 ? -1 : 1  // from the target back towards the origin
        let offset = SIMD3<Float>(
            sin(orbit.azimuth) * cos(orbit.elevation),
            sin(orbit.elevation),
            cos(orbit.azimuth) * cos(orbit.elevation) * towardsMarker
        ) * orbit.distance
        camera.look(at: target, from: target + offset, relativeTo: nil)
    }

    // MARK: - Static scene

    private func buildFloor() {
        // A 4 m square grid, 0.5 m pitch, centred under the orbit target.
        // RealityKit has no line primitives, so each line is a thin box.
        let extent: Float = 4
        let pitch: Float = 0.5
        let thickness: Float = 0.006
        let material = UnlitMaterial(color: NSColor(white: 0.35, alpha: 1))
        let alongX = MeshResource.generateBox(size: SIMD3<Float>(extent, thickness, thickness))
        let alongZ = MeshResource.generateBox(size: SIMD3<Float>(thickness, thickness, extent))
        let centreX = Self.defaultTarget.x
        let centreZ = Self.defaultTarget.z
        var offset = -extent / 2
        while offset <= extent / 2 + 0.001 {
            let lineX = ModelEntity(mesh: alongX, materials: [material])
            lineX.position = SIMD3<Float>(centreX, 0, centreZ + offset)
            floor.addChild(lineX)
            let lineZ = ModelEntity(mesh: alongZ, materials: [material])
            lineZ.position = SIMD3<Float>(centreX + offset, 0, centreZ)
            floor.addChild(lineZ)
            offset += pitch
        }
        floor.position.y = floorY
    }

    private func buildGnomonAndCameraMarker() {
        // Axis gnomon: 0.25 m of +x (red), +y (green), +z (blue) from the origin.
        let length: Float = 0.25
        let girth: Float = 0.01
        let axes: [(SIMD3<Float>, NSColor)] = [
            (SIMD3<Float>(1, 0, 0), .systemRed),
            (SIMD3<Float>(0, 1, 0), .systemGreen),
            (SIMD3<Float>(0, 0, 1), .systemBlue)
        ]
        for (direction, color) in axes {
            let size = SIMD3<Float>(girth, girth, girth) + direction * (length - girth)
            let axis = ModelEntity(mesh: .generateBox(size: size), materials: [UnlitMaterial(color: color)])
            axis.position = direction * (length / 2)
            root.addChild(axis)
        }

        // The camera itself: a small grey box at the origin.
        let marker = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.08, 0.05, 0.03)),
            materials: [UnlitMaterial(color: NSColor(white: 0.75, alpha: 1))]
        )
        root.addChild(marker)
    }

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

        if let minAnkleY {
            floorY += (minAnkleY - 0.02 - floorY) * 0.1
            floor.position.y = floorY
        }
    }

    static func scenePosition(_ joint: WirePoint3D) -> SIMD3<Float> {
        SIMD3<Float>(joint.x, joint.y, joint.z) * axisSign
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
    /// rotating and stretching it — no geometry rebuilds.
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
