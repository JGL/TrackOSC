//
//  FrameConveyor.swift
//  Poseiosc Sender (iOS)
//
//  Latest-frame-wins hand-off between the camera delegate (60 fps) and the
//  Vision processor (slower when several detectors are enabled). At most one
//  processing batch is in flight; frames arriving while busy overwrite the
//  single pending slot, so latency stays bounded and stale frames are dropped.
//

import CoreMedia
import CoreVideo
import ImageIO
import os.lock

/// One camera frame plus the orientation Vision needs to interpret it, and the
/// oriented (display-space) pixel dimensions all wire coordinates refer to.
struct FrameBox: @unchecked Sendable {
    /// The whole sample buffer: carries the camera-intrinsics attachment (when
    /// the capture connection delivers it) and the timestamp Vision's
    /// stateful 3D request keys on. Same backing store as `pixelBuffer`.
    let sampleBuffer: CMSampleBuffer
    let pixelBuffer: CVPixelBuffer
    let orientation: CGImagePropertyOrientation
    let orientedWidth: Int32
    let orientedHeight: Int32
    /// Rotation from sensor-native landscape (0/90/180/270), for /camerainfo.
    let rotationDegrees: Int32
    let isFrontCamera: Bool
}

final class FrameConveyor: Sendable {
    private struct State {
        var pending: FrameBox?
        var isProcessing = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let process: @Sendable (FrameBox) async -> Void

    init(process: @escaping @Sendable (FrameBox) async -> Void) {
        self.process = process
    }

    /// Called from the camera queue for every frame.
    func submit(_ frame: FrameBox) {
        let shouldStart = state.withLock { s -> Bool in
            if s.isProcessing {
                s.pending = frame  // overwrite: latest frame wins
                return false
            }
            s.isProcessing = true
            return true
        }
        guard shouldStart else { return }

        // Detached deliberately: processing must not inherit any actor context
        // or task-locals from the camera delegate's calling context.
        Task.detached(priority: .userInitiated) { [self] in
            var current: FrameBox? = frame
            while let frameToProcess = current {
                await process(frameToProcess)
                current = state.withLock { s in
                    let next = s.pending
                    s.pending = nil
                    if next == nil { s.isProcessing = false }
                    return next
                }
            }
        }
    }
}
