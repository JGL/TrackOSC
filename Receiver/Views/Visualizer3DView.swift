//
//  Visualizer3DView.swift
//  TrackOSC Receiver (macOS)
//
//  The 3D pane: a RealityKit scene of the latest /poses3d/arr frame with a
//  drag-to-orbit, pinch-to-zoom camera, a placeholder while nothing 3D is
//  arriving, and a caption explaining the units and controls.
//
//  The camera is driven here rather than by RealityKit's built-in
//  `realityViewCameraControls`, which repositions any explicit camera entity
//  to the origin (verified: everything clips to black).
//

import PoseioscShared
import RealityKit
import SwiftUI

struct Visualizer3DView: View {
    var model: ReceiverModel
    @State private var scene = Pose3DScene()
    @State private var orbit = OrbitState()
    @State private var dragStart: OrbitState?
    @State private var zoomStart: Float?

    /// Spherical camera position around the scene's target.
    struct OrbitState: Equatable {
        var azimuth: Float = 0.70      // radians around y, from the +z side
        var elevation: Float = 0.39    // radians above the target's horizon
        var distance: Float = 3.7      // metres from the target
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let poses = model.freshPoses3D(at: timeline.date)
            ZStack {
                RealityView { content in
                    content.add(scene.root)
                    content.camera = .virtual
                    scene.placeCamera(orbit)
                } update: { _ in
                    scene.update(poses: poses)
                    scene.placeCamera(orbit)
                }
                .gesture(orbitDrag)
                .gesture(zoomPinch)

                if poses.isEmpty {
                    Text("Waiting for /poses3d/arr… (turn on 3D Body on the sender)")
                        .font(.title3)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                        .allowsHitTesting(false)
                }

                VStack {
                    Spacer()
                    Text(caption(for: poses))
                        .font(.caption.monospaced())
                        .foregroundStyle(.gray)
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(.black)
        .onChange(of: model.resetViewToken) {
            orbit = OrbitState()
        }
        .accessibilityLabel("3D pose visualiser")
    }

    private var orbitDrag: some Gesture {
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
    }

    private var zoomPinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? orbit.distance
                zoomStart = start
                orbit.distance = min(max(start / Float(value.magnification), 0.5), 12)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func caption(for poses: [Pose3DDetection]) -> String {
        var parts: [String] = []
        if poses.isEmpty {
            parts.append("no 3D poses")
        } else {
            let heights = poses.map { String(format: "%.2f m", $0.bodyHeight) }.joined(separator: ", ")
            parts.append("\(poses.count) pose\(poses.count == 1 ? "" : "s") · height \(heights)")
        }
        parts.append("metres · x right · y up · z: Vision camera space")
        parts.append("drag to orbit · pinch to zoom")
        return parts.joined(separator: " · ")
    }
}
