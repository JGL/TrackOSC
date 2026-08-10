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
