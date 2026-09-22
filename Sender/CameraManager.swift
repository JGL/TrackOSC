//
//  CameraManager.swift
//  Poseiosc Sender (iOS)
//
//  Owns the AVCaptureSession. Frames go to the FrameConveyor; the preview
//  layer is exposed for the SwiftUI preview view.
//
//  Orientation: buffers are delivered sensor-native (landscape) and
//  unmirrored (mirroring is disabled on the connection). Instead of rotating
//  pixels, we tell Vision how the buffer is oriented, derived from an
//  AVCaptureDevice.RotationCoordinator in Auto mode or from the user's
//  orientation lock (for mounted rigs, where gravity-based detection is
//  unreliable – e.g. a phone lying flat). Angle → Vision mapping: 90° =
//  .right (the empirically verified portrait case for both cameras), 0° =
//  .up, 180° = .down, 270° = .left.
//
//  Coordinates stay unmirrored, matching VisionOSC's convention; the preview
//  is forced unmirrored too so overlay, preview, and OSC data all agree.
//

@preconcurrency import AVFoundation
import ImageIO
import os.lock

final class CameraManager: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    /// Owned here (not by the SwiftUI view) so mirroring can be re-disabled
    /// inside every session reconfiguration – the layer's connection does not
    /// exist until the session has inputs, and it is recreated (with
    /// mirroring re-enabled by default) on every camera switch.
    let previewLayer: AVCaptureVideoPreviewLayer

    private let sessionQueue = DispatchQueue(label: "poseiosc.camera.session")
    private let videoQueue = DispatchQueue(label: "poseiosc.camera.video")
    private let output = AVCaptureVideoDataOutput()
    private var conveyor: FrameConveyor?
    private(set) var position: AVCaptureDevice.Position = .back

    /// The interface-orientation-derived angle, pushed from the UI layer
    /// whenever the interface rotates. Used only in Auto mode; a locked
    /// orientation bypasses it entirely. Defaults to portrait.
    ///
    /// Deliberately NOT AVCaptureDevice.RotationCoordinator: its gravity-fed
    /// angles proved unreliable on device (stuck at 0° with the system
    /// rotation lock engaged). Driving everything from the interface
    /// orientation makes preview, overlay, and OSC data agree by
    /// construction – what you see is what is sent.
    private let autoAngle = OSAllocatedUnfairLock<Int32>(initialState: 90)

    /// The user's orientation setting (.auto follows the interface).
    private let orientationLock = OSAllocatedUnfairLock<CameraOrientationSetting>(initialState: .auto)

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
    }

    func attach(conveyor: FrameConveyor) {
        self.conveyor = conveyor
    }

    func start(position: AVCaptureDevice.Position) {
        sessionQueue.async { [self] in
            configure(position: position)
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back
        sessionQueue.async { [self] in
            configure(position: newPosition)
        }
    }

    func setOrientationLock(_ setting: CameraOrientationSetting) {
        orientationLock.withLock { $0 = setting }
    }

    /// Called from the UI layer whenever the interface orientation changes.
    func setAutoInterfaceAngle(_ angle: Int32) {
        autoAngle.withLock { $0 = angle }
    }

    /// The angle frames are currently interpreted with (also what /camerainfo
    /// reports). The view layer uses this to counter-rotate the preview for
    /// non-portrait orientations.
    var effectiveAngle: Int32 {
        currentCaptureAngle()
    }

    private func configure(position newPosition: AVCaptureDevice.Position) {
        session.beginConfiguration()

        for input in session.inputs {
            session.removeInput(input)
        }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        position = newPosition

        if session.sessionPreset != .hd1280x720, session.canSetSessionPreset(.hd1280x720) {
            // 720p is plenty for Vision and keeps all-detectors latency down.
            session.sessionPreset = .hd1280x720
        }

        if !session.outputs.contains(output) {
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                return
            }
            session.addOutput(output)
        }

        // Deliver sensor-native buffers; no rotation, no mirroring.
        if let connection = output.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            // Camera intrinsics ride along on each sample buffer so the 3D
            // body request can measure heights instead of estimating them.
            // Delivery is only supported with stabilisation off.
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .off
            }
            if connection.isCameraIntrinsicMatrixDeliverySupported {
                connection.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
        }

        // The preview connection now exists (session has an input) and was
        // recreated with automatic mirroring; force it unmirrored so the
        // preview matches the coordinates sent over OSC.
        if let preview = previewLayer.connection, preview.isVideoMirroringSupported {
            preview.automaticallyAdjustsVideoMirroring = false
            preview.isVideoMirrored = false
        }

        session.commitConfiguration()
    }

    /// The angle frames are interpreted with right now: the user's lock wins;
    /// Auto uses the interface-orientation angle. Read per frame, so no
    /// callback ordering can ever leave a stale value in the pipeline.
    ///
    /// NOTE: the preview connection's rotation is deliberately never touched.
    /// Its default renders upright portrait (verified across every build);
    /// explicit `videoRotationAngle` writes proved unreliable on device. For
    /// non-portrait orientations the view layer counter-rotates the preview
    /// in SwiftUI instead (see ContentView).
    private func currentCaptureAngle() -> Int32 {
        let lock = orientationLock.withLock { $0 }
        if lock == .auto {
            return autoAngle.withLock { $0 }
        }
        return Int32(lock.rawValue)
    }

}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard
            let conveyor,
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let angle = currentCaptureAngle()
        let orientation = VisionAngle.orientation(forDegrees: angle)
        let bufferWidth = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let bufferHeight = Int32(CVPixelBufferGetHeight(pixelBuffer))

        let swapped = VisionAngle.isQuarterTurn(angle)
        conveyor.submit(FrameBox(
            sampleBuffer: sampleBuffer,
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            orientedWidth: swapped ? bufferHeight : bufferWidth,
            orientedHeight: swapped ? bufferWidth : bufferHeight,
            rotationDegrees: angle,
            isFrontCamera: position == .front
        ))
    }
}
