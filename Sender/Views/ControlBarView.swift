//
//  ControlBarView.swift
//  Poseiosc Sender (iOS)
//
//  Detector toggle chips plus camera-switch and settings buttons.
//

import SwiftUI

struct ControlBarView: View {
    @Bindable var model: AppModel
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 12) {
            DetectorChipRow(isOn: model.settings.isEnabled) { detector in
                model.settings.toggle(detector)
                model.applySettings()
            }

            HStack {
                Button("Switch Camera", systemImage: "arrow.triangle.2.circlepath.camera", action: switchCamera)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .padding(12)
                    .background(.black.opacity(0.5), in: .circle)

                Button(
                    model.settings.hideVideoPreview ? "Show Video" : "Hide Video",
                    systemImage: model.settings.hideVideoPreview ? "eye.slash" : "eye",
                    action: toggleVideoPreview
                )
                .labelStyle(.iconOnly)
                .font(.title2)
                .padding(12)
                .background(.black.opacity(0.5), in: .circle)

                Spacer()

                Button("Settings", systemImage: "gearshape", action: openSettings)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .padding(12)
                    .background(.black.opacity(0.5), in: .circle)
            }
            .foregroundStyle(.white)
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    private func switchCamera() {
        model.switchCamera()
    }

    private func toggleVideoPreview() {
        model.settings.hideVideoPreview.toggle()
    }

    private func openSettings() {
        showSettings = true
    }
}
