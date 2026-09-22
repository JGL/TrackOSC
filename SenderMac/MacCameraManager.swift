//
//  MacCameraManager.swift
//  Poseiosc Sender (macOS)
//
//  Owns the AVCaptureSession for the Mac sender. Unlike the iPhone, Mac
//  cameras don't rotate with an interface – the rotation setting exists for
//  rotated external camera rigs, and there can be several cameras (built-in,
//  external webcams, iPhone Continuity Camera), so devices are discovered and
//  selectable by uniqueID.
//
//  Wire conventions match the iOS sender: unmirrored buffers and preview,
//  rotation read per frame, /camerainfo facing reported as front (a webcam
//  faces the user).
//

@preconcurrency import AVFoundation
import os.lock

struct CameraOption: Identifiable, Equatable {
    let id: String       // AVCaptureDevice.uniqueID
    let name: String
}

final class MacCameraManager: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer

    private let sessionQueue = DispatchQueue(label: "poseiosc.mac.camera.session")
    private let videoQueue = DispatchQueue(label: "poseiosc.mac.camera.video")
    private let output = AVCaptureVideoDataOutput()
    private var conveyor: FrameConveyor?

    /// Rotation of the physical camera rig (0/90/180/270), read per frame.
    private let rotation = OSAllocatedUnfairLock<Int32>(initialState: 0)

    private(set) var currentDeviceID: String?

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
    }

    func attach(conveyor: FrameConveyor) {
        self.conveyor = conveyor
    }

    static func availableCameras() -> [CameraOption] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map { CameraOption(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// Starts (or restarts) capture with the given camera, falling back to
    /// the first available one.
    func start(deviceID: String?) {
        sessionQueue.async { [self] in
            configure(deviceID: deviceID)
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

    func setRotation(_ degrees: Int32) {
        rotation.withLock { $0 = degrees }
    }

    private func configure(deviceID: String?) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for input in session.inputs {
            session.removeInput(input)
        }

        let device = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) }
            ?? AVCaptureDevice.default(for: .video)
        guard
            let device,
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }

        session.addInput(input)
        currentDeviceID = device.uniqueID

        if session.sessionPreset != .hd1280x720, session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }

        if !session.outputs.contains(output) {
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
        }

        // Unmirrored buffers and preview, matching the wire convention.
        for connection in [output.connection(with: .video), previewLayer.connection] {
            if let connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }
}

extension MacCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard
            let conveyor,
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let angle = rotation.withLock { $0 }
        let bufferWidth = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let bufferHeight = Int32(CVPixelBufferGetHeight(pixelBuffer))
        let swapped = VisionAngle.isQuarterTurn(angle)

        conveyor.submit(FrameBox(
            sampleBuffer: sampleBuffer,
            pixelBuffer: pixelBuffer,
            orientation: VisionAngle.orientation(forDegrees: angle),
            orientedWidth: swapped ? bufferHeight : bufferWidth,
            orientedHeight: swapped ? bufferWidth : bufferHeight,
            rotationDegrees: angle,
            isFrontCamera: true
        ))
    }
}
