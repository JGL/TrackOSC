//
//  CostumeStage.swift
//  TrackOSC Costumes (macOS)
//
//  The stage: a Canvas at the display rate drawing the store's current
//  frame through CoreGraphics, reporting its size back for the rig.
//

import SwiftUI

struct CostumeStage: View {
    @Bindable var store: CostumesStore

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas(rendersAsynchronously: false) { context, size in
                let frame = store.frame
                context.withCGContext { cg in
                    CostumesStore.draw(frame, in: cg)
                }
                if frame.isAttract && !store.model.fullScreen.isGUIHidden {
                    let text = Text("Attract figure \u{2013} nobody is being tracked").font(.caption).foregroundStyle(.white.opacity(0.6))
                    context.draw(text, at: CGPoint(x: size.width / 2, y: size.height - 18))
                }
                if store.costume == nil {
                    let text = Text(store.loadError ?? "No costume").font(.title3).foregroundStyle(.white.opacity(0.6))
                    context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in proxy.size } action: { size in
            if size.width > 0, size.height > 0 { store.viewSize = size }
        }
        .background(WindowScaleReader { scale in store.backingScale = scale })
    }
}

/// Reads the window's backing scale so recordings are made at full resolution.
private struct WindowScaleReader: NSViewRepresentable {
    let onScale: (CGFloat) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onScale(view.window?.backingScaleFactor ?? 2) }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        onScale(view.window?.backingScaleFactor ?? 2)
    }
}
