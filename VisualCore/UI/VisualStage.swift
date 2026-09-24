//
//  VisualStage.swift
//  TrackOSC (VisualCore)
//
//  The canvas plus a mode name that fades in on change, and the renderer
//  error if there is one.
//

import SwiftUI

struct VisualStage: View {
    let store: VisualStore

    var body: some View {
        ZStack(alignment: .topLeading) {
            if store.renderer != nil {
                MetalCanvasView(store: store)
            } else {
                store.model.settings.stageBackground
                Text("Metal is not available on this Mac.")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            TimelineView(.animation(minimumInterval: 0.1)) { timeline in
                let age = timeline.date.timeIntervalSince(store.modeChangedAt)
                if store.display.showModeName, age < 2.5 {
                    Text(store.mode.name)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: .rect(cornerRadius: 10))
                        .padding(16)
                        .opacity(age < 2 ? 1 : (2.5 - age) * 2)
                        .allowsHitTesting(false)
                }
            }
            if let error = store.rendererError {
                Text(error)
                    .font(.callout.monospaced())
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.red.opacity(0.8))
                    .padding(16)
            }
        }
    }
}
