//
//  MacContentView.swift
//  Poseiosc Sender (macOS)
//
//  Preview + overlay + detector chips, mirroring the iOS layout. The preview
//  displays buffers as captured (rotation 0); for a rotated camera rig the
//  preview is counter-rotated in view space, same pattern as iOS.
//

import SwiftUI

struct MacContentView: View {
    @Bindable var model: MacAppModel
    @State private var showSettings = false

    private var isMirrored: Bool { model.settings.mirrorPreview }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                ZStack {
                    if !model.settings.hideVideoPreview {
                        cameraPreview(in: proxy.size)
                    }
                    OverlayView(snapshot: model.overlay, mirrored: isMirrored)
                }
            }

            VStack {
                statusBar
                Spacer()
                controlBar
            }
        }
        .background(.black)
        .task {
            model.start()
        }
        .sheet(isPresented: $showSettings) {
            MacSettingsView(model: model)
        }
    }

    /// The preview shows the buffer as captured; a rotated rig setting
    /// counter-rotates the view (with swapped framing for quarter turns).
    @ViewBuilder
    private func cameraPreview(in size: CGSize) -> some View {
        let delta = Double(model.overlay.rotationDegrees)
        let quarterTurn = abs(delta.truncatingRemainder(dividingBy: 180)) == 90

        MacCameraPreviewView(previewLayer: model.camera.previewLayer)
            .frame(
                width: quarterTurn ? size.height : size.width,
                height: quarterTurn ? size.width : size.height
            )
            .rotationEffect(.degrees(delta))
            .position(x: size.width / 2, y: size.height / 2)
            .scaleEffect(x: isMirrored ? -1 : 1, y: 1)
    }

    private var statusBar: some View {
        HStack {
            Text(destinationLabel)
                .font(.system(.footnote, design: .monospaced))
            Spacer()
            Text(dimensionsAndRateLabel)
                .font(.system(.footnote, design: .monospaced))
        }
        .padding(8)
        .background(.black.opacity(0.5), in: .capsule)
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var destinationLabel: String {
        let host = model.settings.host.isEmpty ? "—" : model.settings.host
        return "→ \(host):\(String(model.settings.port))"
    }

    private var dimensionsAndRateLabel: String {
        let fps = "\(Int(model.processedFPS)) fps"
        guard model.overlay.width > 0 else { return fps }
        return "\(model.overlay.width)×\(model.overlay.height) · \(fps)"
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            DetectorChip(label: "Body", color: .green, isOn: model.settings.detectPoses) {
                model.settings.detectPoses.toggle()
                model.applySettings()
            }
            DetectorChip(label: "Hand", color: .orange, isOn: model.settings.detectHands) {
                model.settings.detectHands.toggle()
                model.applySettings()
            }
            DetectorChip(label: "Face", color: .cyan, isOn: model.settings.detectFaces) {
                model.settings.detectFaces.toggle()
                model.applySettings()
            }
            DetectorChip(label: "Text", color: .yellow, isOn: model.settings.detectTexts) {
                model.settings.detectTexts.toggle()
                model.applySettings()
            }
            DetectorChip(label: "Animal", color: .pink, isOn: model.settings.detectAnimals) {
                model.settings.detectAnimals.toggle()
                model.applySettings()
            }

            Spacer()

            Button(
                model.settings.hideVideoPreview ? "Show Video" : "Hide Video",
                systemImage: model.settings.hideVideoPreview ? "eye.slash" : "eye",
                action: toggleVideoPreview
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.title2)
            .foregroundStyle(.white)
            .padding(10)
            .background(.black.opacity(0.5), in: .circle)

            Button("Settings", systemImage: "gearshape", action: openSettings)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.title2)
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.5), in: .circle)
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private func openSettings() {
        model.refreshCameras()
        showSettings = true
    }

    private func toggleVideoPreview() {
        model.settings.hideVideoPreview.toggle()
    }
}
