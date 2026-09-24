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
    var store: ReceiverStore
    @State private var scene = Pose3DScene()
    @State private var orbit = OrbitState()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let poses = store.freshPoses3D(at: timeline.date)
            ZStack {
                RealityView { content in
                    content.add(scene.root)
                    content.camera = .virtual
                    scene.placeCamera(orbit)
                } update: { _ in
                    scene.update(poses: poses)
                    scene.placeCamera(orbit)
                }
                .modifier(OrbitGestures(orbit: $orbit))

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
        .onChange(of: store.resetViewToken) {
            orbit = OrbitState()
        }
        .accessibilityLabel("3D pose visualiser")
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
