//
//  Stage3D.swift
//  TrackOSC (ReceiverCore)
//
//  The RealityKit stage shared by the Receiver's 3D view and 3D Costumes:
//  a root, an orbiting perspective camera, a floor grid that settles under
//  the lowest ankle, and an axis gnomon with a camera marker at the
//  origin. Units are metres straight from /poses3d/arr; Vision's
//  camera-relative space and RealityKit's are both right-handed, y up.
//

import AppKit
import RealityKit
import simd
import SwiftUI

/// Spherical camera position around the stage's target.
struct OrbitState: Equatable {
    var azimuth: Float = 0.70      // radians around y, from the +z side
    var elevation: Float = 0.39    // radians above the target's horizon
    var distance: Float = 3.7      // metres from the target
}

@MainActor
final class Stage3D {
    /// Vision camera space → RealityKit space; flip a component after the on-device check.
    static let axisSign = SIMD3<Float>(1, 1, 1)
    /// Where the orbit camera looks: a couple of metres in front of the camera marker, at hip height.
    static let defaultTarget = SIMD3<Float>(0, -0.2, 2.0) * axisSign

    let root = Entity()
    let camera = PerspectiveCamera()
    private let floor = Entity()
    private var floorY: Float = -1.2

    init(showGnomon: Bool = true) {
        root.addChild(floor)
        buildFloor()
        if showGnomon { buildGnomonAndCameraMarker() }
        camera.camera.near = 0.05
        camera.camera.far = 60
        root.addChild(camera)
    }

    static func scenePosition(x: Float, y: Float, z: Float) -> SIMD3<Float> {
        SIMD3<Float>(x, y, z) * axisSign
    }

    /// Places the camera on a sphere around the target and points it there.
    func placeCamera(_ orbit: OrbitState) {
        let target = Self.defaultTarget
        let towardsMarker: Float = target.z >= 0 ? -1 : 1
        let offset = SIMD3<Float>(
            sin(orbit.azimuth) * cos(orbit.elevation),
            sin(orbit.elevation),
            cos(orbit.azimuth) * cos(orbit.elevation) * towardsMarker
        ) * orbit.distance
        camera.look(at: target, from: target + offset, relativeTo: nil)
    }

    /// Ease the floor to just under the lowest point seen this frame.
    func settleFloor(under lowestY: Float?) {
        guard let lowestY else { return }
        floorY += (lowestY - 0.02 - floorY) * 0.1
        floor.position.y = floorY
    }

    var floorHeight: Float { floorY }

    private func buildFloor() {
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
        let marker = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.08, 0.05, 0.03)),
            materials: [UnlitMaterial(color: NSColor(white: 0.75, alpha: 1))]
        )
        root.addChild(marker)
    }
}

/// Drag to orbit, pinch to zoom, for any view over a Stage3D.
struct OrbitGestures: ViewModifier {
    @Binding var orbit: OrbitState
    @State private var dragStart: OrbitState?
    @State private var zoomStart: Float?

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStart ?? orbit
                        dragStart = start
                        var next = start
                        next.azimuth = start.azimuth - Float(value.translation.width) * 0.01
                        next.elevation = min(max(start.elevation + Float(value.translation.height) * 0.01, -1.4), 1.4)
                        orbit = next
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = zoomStart ?? orbit.distance
                        zoomStart = start
                        orbit.distance = min(max(start / Float(value.magnification), 0.5), 12)
                    }
                    .onEnded { _ in zoomStart = nil }
            )
    }
}
