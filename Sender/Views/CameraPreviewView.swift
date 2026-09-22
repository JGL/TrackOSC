//
//  CameraPreviewView.swift
//  Poseiosc Sender (iOS)
//
//  Hosts the CameraManager's AVCaptureVideoPreviewLayer. The layer (and its
//  unmirrored configuration) is owned by CameraManager – see the note there
//  about why mirroring cannot be configured from this view.
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    final class PreviewContainerView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                guard previewLayer !== oldValue else { return }
                oldValue?.removeFromSuperlayer()
                if let previewLayer {
                    layer.addSublayer(previewLayer)
                    setNeedsLayout()
                }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer?.frame = bounds
            CATransaction.commit()
        }
    }

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.previewLayer = previewLayer
    }
}
