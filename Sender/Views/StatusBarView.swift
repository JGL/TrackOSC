//
//  StatusBarView.swift
//  Poseiosc Sender (iOS)
//
//  Destination and processing-rate readout over the camera preview.
//

import SwiftUI

struct StatusBarView: View {
    var model: AppModel

    var body: some View {
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
    }

    private var destinationLabel: String {
        let host = model.settings.host.isEmpty ? "–" : model.settings.host
        return "→ \(host):\(String(model.settings.port))"
    }

    /// Shows the exact dimensions being transmitted, e.g. "720×1280 · 24 fps".
    private var dimensionsAndRateLabel: String {
        let fps = "\(Int(model.processedFPS)) fps"
        guard model.overlay.width > 0 else { return fps }
        return "\(model.overlay.width)×\(model.overlay.height) · \(fps)"
    }
}
