//
//  ReceiverWindow.swift
//  TrackOSC (ReceiverCore)
//
//  The window shell every receiver-type app uses: a stage (what an audience
//  sees) beside hideable controls, the shared connection toolbar, a port
//  banner when the default port was taken, and the presentation overlay.
//

import SwiftUI

struct ReceiverWindow<Stage: View, Controls: View, Extras: ToolbarContent>: View {
    @Bindable var model: ReceiverModel
    @ViewBuilder let stage: () -> Stage
    @ViewBuilder let controls: () -> Controls
    @ToolbarContentBuilder let toolbarExtras: () -> Extras

    init(
        model: ReceiverModel,
        @ViewBuilder stage: @escaping () -> Stage,
        @ViewBuilder controls: @escaping () -> Controls,
        @ToolbarContentBuilder toolbar: @escaping () -> Extras
    ) {
        self.model = model
        self.stage = stage
        self.controls = controls
        self.toolbarExtras = toolbar
    }

    /// Without app-specific toolbar items.
    init(
        model: ReceiverModel,
        @ViewBuilder stage: @escaping () -> Stage,
        @ViewBuilder controls: @escaping () -> Controls
    ) where Extras == EmptyToolbar {
        self.model = model
        self.stage = stage
        self.controls = controls
        self.toolbarExtras = { EmptyToolbar() }
    }

    var body: some View {
        let hidden = model.presentation.isGUIHidden
        VStack(spacing: 0) {
            if !hidden, let note = model.portNote {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12))
                Divider()
            }
            HSplitView {
                stage()
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                if !hidden {
                    controls()
                        .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
                }
            }
        }
        .toolbar(hidden ? .hidden : .visible, for: .windowToolbar)
        .toolbar {
            toolbarExtras()
            ConnectionToolbar(model: model)
        }
        .overlay(alignment: .bottomTrailing) {
            if hidden, model.presentation.isHintVisible {
                PresentationHint()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !hidden, let error = model.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.8))
            }
        }
        .background(WindowAccessor { window in model.presentation.attach(window: window) })
        .onAppear {
            if model.settings.startInPresentation {
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    model.presentation.enterPresentation()
                }
            }
        }
    }
}

/// A toolbar contribution with nothing in it.
struct EmptyToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) { EmptyView() }
    }
}

/// The fading corner hint shown while the controls are hidden.
struct PresentationHint: View {
    var body: some View {
        Text("Esc shows the controls")
            .font(.caption.monospaced())
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.5), in: .capsule)
            .padding(12)
            .transition(.opacity)
            .allowsHitTesting(false)
    }
}
