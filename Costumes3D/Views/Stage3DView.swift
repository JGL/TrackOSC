//
//  Stage3DView.swift
//  TrackOSC 3D Costumes (macOS)
//

import RealityKit
import SwiftUI

struct Stage3DView: View {
    @Bindable var store: Costumes3DStore

    var body: some View {
        ZStack {
            RealityView { content in
                content.add(store.stage.root)
                content.camera = .virtual
                store.stage.placeCamera(store.orbit)
            } update: { _ in
                store.stage.placeCamera(store.orbit)
            }
            .modifier(OrbitGestures(orbit: $store.orbit))

            if !store.isReceiving3D {
                Text("Waiting for /poses3d/arr\u{2026} turn on 3D Body on the sender")
                    .font(.title3)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
                    .allowsHitTesting(false)
            }
            if !store.model.fullScreen.isGUIHidden {
                VStack {
                    Spacer()
                    Text(caption)
                        .font(.caption.monospaced())
                        .foregroundStyle(.gray)
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(store.model.settings.stageBackground)
    }

    private var caption: String {
        var parts: [String] = []
        if store.poseCount == 0 {
            parts.append("no 3D poses")
        } else {
            let heights = store.lastHeights.map { String(format: "%.2f m", $0) }.joined(separator: ", ")
            parts.append("\(store.poseCount) pose\(store.poseCount == 1 ? "" : "s") \u{00B7} height \(heights)")
        }
        parts.append("drag to orbit \u{00B7} pinch to zoom \u{00B7} 0 resets the view")
        return parts.joined(separator: " \u{00B7} ")
    }
}
