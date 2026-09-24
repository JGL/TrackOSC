//
//  MetalCanvasView.swift
//  TrackOSC (VisualCore)
//
//  An MTKView driven at the display's rate; every frame asks the store
//  for the scene and inputs and hands them to the renderer.
//

import MetalKit
import SwiftUI

struct MetalCanvasView: NSViewRepresentable {
    let store: VisualStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: store.renderer?.device)
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = true
        view.layer?.isOpaque = true
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.store = store
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        var store: VisualStore
        init(store: VisualStore) { self.store = store }

        nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        nonisolated func draw(in view: MTKView) {
            MainActor.assumeIsolated {
                store.renderFrame(in: view)
            }
        }
    }
}
