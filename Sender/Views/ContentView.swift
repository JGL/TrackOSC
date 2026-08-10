//
//  ContentView.swift
//  Poseiosc Sender (iOS)
//

import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()
    @State private var showSettings = false

    /// Selfie-mirror is display-only: the preview is flipped with a scale
    /// transform and the overlay flips its own coordinates (keeping label
    /// text readable). OSC output is unaffected.
    private var isMirrored: Bool {
        model.settings.useFrontCamera && model.settings.mirrorFrontPreview
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                ZStack {
                    if !model.settings.hideVideoPreview {
                        cameraPreview(in: proxy.size)
                    }
                    OverlayView(snapshot: model.overlay, mirrored: isMirrored)
                }
                // Size changes are the reliable signal that the interface
                // rotated; the model re-reads the scene orientation from it.
                .onChange(of: proxy.size) {
                    model.refreshInterfaceOrientation()
                }
            }
            .background(.black)
            .ignoresSafeArea()

            VStack {
                StatusBarView(model: model)
                Spacer()
                ControlBarView(model: model, showSettings: $showSettings)
            }
        }
        .statusBarHidden()
        .task {
            model.start()
            model.refreshInterfaceOrientation()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
    }

    /// The preview connection renders upright-portrait video (its untouched
    /// default). For non-portrait orientations the view is counter-rotated
    /// here, with swapped framing so aspect-fill still covers the screen.
    /// In portrait this applies no transform at all.
    @ViewBuilder
    private func cameraPreview(in size: CGSize) -> some View {
        let delta = Double(model.overlay.rotationDegrees - 90)
        let quarterTurn = abs(delta.truncatingRemainder(dividingBy: 180)) == 90

        CameraPreviewView(previewLayer: model.camera.previewLayer)
            .frame(
                width: quarterTurn ? size.height : size.width,
                height: quarterTurn ? size.width : size.height
            )
            .rotationEffect(.degrees(delta))
            .position(x: size.width / 2, y: size.height / 2)
            .scaleEffect(x: isMirrored ? -1 : 1, y: 1)
    }
}
