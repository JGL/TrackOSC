//
//  VisionProcessor.swift
//  TrackOSC Sender (shared)
//
//  Runs the enabled Vision requests on each frame, maps observations to the
//  wire format, sends OSC immediately per completed request (matching
//  VisionOSC's cadence), and publishes the mapped detections for the overlay.
//
//  The per-frame requests run concurrently: each child task's `perform`
//  suspends this actor, so all enabled detectors are in flight at once inside
//  Vision.
//
//  The 3D body request is the exception. It is stateful (a class held across
//  frames), markedly heavier than the 2D requests, and would drag every other
//  detector down to its rate if it sat in the same batch. It therefore runs in
//  its own latest-frame-wins lane: each frame is parked for it, and it
//  processes whatever is newest when it comes free, sending /poses3d/arr at
//  its own — typically lower — rate.
//

import Foundation
import Vision
import PoseioscShared

/// Which detectors are enabled.
struct DetectorConfig: Sendable, Equatable {
    var enabled: Set<Detector> = Detector.defaultSet
    var maxHands = 2

    func isEnabled(_ detector: Detector) -> Bool { enabled.contains(detector) }
}

/// Everything the overlay needs to draw one processed frame.
struct OverlaySnapshot: Sendable {
    var width: Int32 = 0
    var height: Int32 = 0
    var rotationDegrees: Int32 = 90
    var isFrontCamera = false
    var poses: [PoseDetection] = []
    var hands: [HandDetection] = []
    var faces: [FaceDetection] = []
    var faceBoxes: [FaceBoxDetection] = []
    var faceContours: [FaceContourDetection] = []
    var texts: [BoxDetection] = []
    var animals: [BoxDetection] = []
    /// The most recent 3D result (it lags the frame by the 3D lane's latency).
    var poses3D: [Pose3DDetection] = []
    /// Increments per completed 3D analysis, so the UI can show a 3D rate.
    var poses3DSequence: UInt64 = 0
    var animalPoses: [AnimalPoseDetection] = []
    var humans: [HumanDetection] = []
    var barcodes: [BarcodeDetection] = []
    var processingTime: TimeInterval = 0
}

actor VisionProcessor {
    private var config = DetectorConfig()
    private let sender: OSCSenderService
    private let publish: @Sendable (OverlaySnapshot) -> Void

    // 3D lane state (see the file comment).
    private var pose3DRequest: DetectHumanBodyPose3DRequest?
    private var pose3DPending: FrameBox?
    private var pose3DLaneRunning = false
    private var latestPoses3D: [Pose3DDetection] = []
    private var poses3DSequence: UInt64 = 0

    init(sender: OSCSenderService, publish: @escaping @Sendable (OverlaySnapshot) -> Void) {
        self.sender = sender
        self.publish = publish
    }

    func setConfig(_ newConfig: DetectorConfig) {
        config = newConfig
    }

    func process(_ frame: FrameBox) async {
        let cfg = config
        let started = ContinuousClock.now
        var snapshot = OverlaySnapshot(
            width: frame.orientedWidth,
            height: frame.orientedHeight,
            rotationDegrees: frame.rotationDegrees,
            isFrontCamera: frame.isFrontCamera
        )

        // Camera geometry first, so receivers can interpret what follows.
        sender.send(WireCodec.encodeCameraInfo(CameraInfo(
            width: frame.orientedWidth,
            height: frame.orientedHeight,
            orientationDegrees: frame.rotationDegrees,
            facing: frame.isFrontCamera ? 1 : 0
        )))

        // Hand the frame to the 3D lane (or tear the lane down when toggled off).
        if cfg.isEnabled(.poses3D) {
            pose3DPending = frame
            if !pose3DLaneRunning {
                pose3DLaneRunning = true
                Task { await self.runPose3DLane() }
            }
        } else if pose3DRequest != nil || !latestPoses3D.isEmpty {
            pose3DPending = nil
            pose3DRequest = nil
            latestPoses3D = []
        }
        snapshot.poses3D = latestPoses3D
        snapshot.poses3DSequence = poses3DSequence

        // Each run* method awaits Vision off-actor; the actor is free to
        // interleave, so enabled requests execute concurrently.
        async let poses = cfg.isEnabled(.poses) ? runBody(frame) : nil
        async let hands = cfg.isEnabled(.hands) ? runHands(frame, maxHands: cfg.maxHands) : nil
        async let faces = cfg.isEnabled(.faces) ? runFaces(frame) : nil
        async let texts = cfg.isEnabled(.texts) ? runTexts(frame) : nil
        async let animals = cfg.isEnabled(.animals) ? runAnimals(frame) : nil
        async let animalPoses = cfg.isEnabled(.animalPoses) ? runAnimalPoses(frame) : nil
        async let humans = cfg.isEnabled(.humans) ? runHumans(frame) : nil
        async let barcodes = cfg.isEnabled(.barcodes) ? runBarcodes(frame) : nil

        if let result = await poses {
            snapshot.poses = result.detections
            sender.send(WireCodec.encodePoses(result))
        }
        if let result = await hands {
            snapshot.hands = result.detections
            sender.send(WireCodec.encodeHands(result))
        }
        if let result = await faces {
            snapshot.faces = result.landmarks.detections
            snapshot.faceBoxes = result.boxes.detections
            snapshot.faceContours = result.contours.detections
            sender.send(WireCodec.encodeFaces(result.landmarks))
            sender.send(WireCodec.encodeFaceBoxes(result.boxes))
            sender.send(WireCodec.encodeFaceContours(result.contours))
        }
        if let result = await texts {
            snapshot.texts = result.detections
            sender.send(WireCodec.encodeTexts(result))
        }
        if let result = await animals {
            snapshot.animals = result.detections
            sender.send(WireCodec.encodeAnimals(result))
        }
        if let result = await animalPoses {
            snapshot.animalPoses = result.detections
            sender.send(WireCodec.encodeAnimalPoses(result))
        }
        if let result = await humans {
            snapshot.humans = result.detections
            sender.send(WireCodec.encodeHumans(result))
        }
        if let result = await barcodes {
            snapshot.barcodes = result.detections
            sender.send(WireCodec.encodeBarcodes(result))
        }

        let elapsed = started.duration(to: .now).components
        snapshot.processingTime = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        publish(snapshot)
    }

    // MARK: - 3D lane

    private func takePendingPose3D() -> FrameBox? {
        defer { pose3DPending = nil }
        return pose3DPending
    }

    private func runPose3DLane() async {
        while let frame = takePendingPose3D() {
            let request = pose3DRequest ?? DetectHumanBodyPose3DRequest()
            pose3DRequest = request

            // The sample buffer (rather than the bare pixel buffer) lets Vision
            // pick up camera intrinsics when the capture connection delivers
            // them (iOS), which turns reference-height estimates into
            // measured ones.
            guard let observations = try? await request.perform(
                on: frame.sampleBuffer, orientation: frame.orientation
            ) else { continue }

            // Toggled off while we were inside Vision: drop the result.
            guard config.isEnabled(.poses3D) else { break }

            let result = ObservationMapping.mapBodyPoses3D(
                observations,
                width: frame.orientedWidth,
                height: frame.orientedHeight
            )
            latestPoses3D = result.detections
            poses3DSequence &+= 1
            sender.send(WireCodec.encodePoses3D(result))
        }
        pose3DLaneRunning = false
    }

    // MARK: - Individual requests

    private func runBody(_ frame: FrameBox) async -> DetectionFrame<PoseDetection>? {
        let request = DetectHumanBodyPoseRequest()
        guard let observations = try? await request.perform(
            on: frame.pixelBuffer, orientation: frame.orientation
        ) else { return nil }
        return ObservationMapping.mapBodyPoses(
            observations,
            width: frame.orientedWidth,
            height: frame.orientedHeight
        )
    }

    private func runHands(_ frame: FrameBox, maxHands: Int) async -> DetectionFrame<HandDetection>? {
        var request = DetectHumanHandPoseRequest()
        request.maximumHandCount = maxHands
        guard let observations = try? await request.perform(
            on: frame.pixelBuffer, orientation: frame.orientation
        ) else { return nil }
        return ObservationMapping.mapHands(
            observations,
            width: frame.orientedWidth,
            height: frame.orientedHeight
        )
    }

    private func runFaces(_ frame: FrameBox) async -> ObservationMapping.FaceFrames? {
        // Revision 3 (the only revision of the modern API) produces the
        // 76-point constellation VisionOSC expects.
        let request = DetectFaceLandmarksRequest()
        guard let observations = try? await request.perform(
            on: frame.pixelBuffer, orientation: frame.orientation
        ) else { return nil }
        return ObservationMapping.mapFaces(
            observations,
            width: frame.orientedWidth,
            height: frame.orientedHeight
        )
    }

    private func runTexts(_ frame: FrameBox) async -> DetectionFrame<BoxDetection>? {
        var request = RecognizeTextRequest()
        // Fast level keeps frame rate usable; VisionOSC also prioritized rate.
        request.recognitionLevel = .fast
        guard let observations = try? await request.perform(
            on: frame.pixelBuffer, orientation: frame.orientation
        ) else { return nil }
        return ObservationMapping.mapTexts(
            observations,
            width: frame.orientedWidth,
            height: frame.orientedHeight
        )
    }

    private func runAnimals(_ frame: FrameBox) async -> DetectionFrame<BoxDetection>? {
        let request = RecognizeAnimalsRequest()
        guard let observations = try? await request.perform(
            on: frame.pixelBuffer, orientation: frame.orientation
        ) else { return nil }
        return ObservationMapping.mapAnimals(
            observations,
            width: frame.orientedWidth,
            height: frame.orientedHeight
        )
    }

    private func runAnimalPoses(_ frame: FrameBox) async -> DetectionFrame<AnimalPoseDetection>? {
        let request = DetectAnimalBodyPoseRequest()
        guard let observations = try? await request.perform(
            on: frame.pixelBuffer, orientation: frame.orientation
        ) else { return nil }
        return ObservationMapping.mapAnimalPoses(
            observations,
            width: frame.orientedWidth,
            height: frame.orientedHeight
        )
    }

    private func runHumans(_ frame: FrameBox) async -> DetectionFrame<HumanDetection>? {
        var request = DetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        guard let observations = try? await request.perform(
            on: frame.pixelBuffer, orientation: frame.orientation
        ) else { return nil }
        return ObservationMapping.mapHumans(
            observations,
            width: frame.orientedWidth,
            height: frame.orientedHeight
        )
    }

    private func runBarcodes(_ frame: FrameBox) async -> DetectionFrame<BarcodeDetection>? {
        // Default symbologies: everything Vision supports.
        let request = DetectBarcodesRequest()
        guard let observations = try? await request.perform(
            on: frame.pixelBuffer, orientation: frame.orientation
        ) else { return nil }
        return ObservationMapping.mapBarcodes(
            observations,
            width: frame.orientedWidth,
            height: frame.orientedHeight
        )
    }
}
