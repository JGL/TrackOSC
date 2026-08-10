//
//  VisionProcessor.swift
//  Poseiosc Sender (iOS)
//
//  Runs the enabled Vision requests on each frame, maps observations to the
//  wire format, sends OSC immediately per completed request (matching
//  VisionOSC's cadence), and publishes the mapped detections for the overlay.
//
//  The requests run concurrently: each child task's `perform` suspends this
//  actor, so all enabled detectors are in flight at once inside Vision.
//

import Foundation
import Vision
import PoseioscShared

/// Which detectors are enabled. Mirrors VisionOSC's five toggles.
struct DetectorConfig: Sendable, Equatable {
    var poses = true
    var hands = true
    var faces = true
    var texts = false
    var animals = false
    var maxHands = 2
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
    var processingTime: TimeInterval = 0
}

actor VisionProcessor {
    private var config = DetectorConfig()
    private let sender: OSCSenderService
    private let publish: @Sendable (OverlaySnapshot) -> Void

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

        // Each run* method awaits Vision off-actor; the actor is free to
        // interleave, so enabled requests execute concurrently.
        async let poses = cfg.poses ? runBody(frame) : nil
        async let hands = cfg.hands ? runHands(frame, maxHands: cfg.maxHands) : nil
        async let faces = cfg.faces ? runFaces(frame) : nil
        async let texts = cfg.texts ? runTexts(frame) : nil
        async let animals = cfg.animals ? runAnimals(frame) : nil

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

        snapshot.processingTime = Double(started.duration(to: .now).components.attoseconds) / 1e18
        publish(snapshot)
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
}
