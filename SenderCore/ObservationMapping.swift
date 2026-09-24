//
//  ObservationMapping.swift
//  TrackOSC Sender (shared)
//
//  Vision observations → wire models. All VisionOSC fidelity decisions live
//  here: joint ordering, coordinate flips, missing-joint sentinels.
//

import Foundation
import Vision
import simd
import PoseioscShared

enum ObservationMapping {
    // MARK: - Keypoint helper

    /// Maps a Vision joint dictionary onto the wire's fixed joint order,
    /// substituting VisionOSC's missing-joint sentinel for absent or
    /// zero-confidence joints.
    private static func wirePoints<Name: Hashable>(
        _ joints: [Name: Joint],
        order: [Name],
        frameWidth w: Float,
        frameHeight h: Float
    ) -> [WirePoint] {
        order.map { name -> WirePoint in
            guard let joint = joints[name], joint.confidence > 0 else {
                return .missing(frameHeight: h)
            }
            return CoordinateMapper.point(
                normalizedX: joint.location.x,
                normalizedY: joint.location.y,
                confidence: joint.confidence,
                frameWidth: w,
                frameHeight: h
            )
        }
    }

    // MARK: - Body poses

    /// The 17 joints of the wire format, in PoseNet order (JointOrder.body17).
    private static let bodyJointNames: [HumanBodyPoseObservation.JointName] = [
        .nose, .leftEye, .rightEye, .leftEar, .rightEar,
        .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
        .leftWrist, .rightWrist, .leftHip, .rightHip,
        .leftKnee, .rightKnee, .leftAnkle, .rightAnkle
    ]

    static func mapBodyPoses(
        _ observations: [HumanBodyPoseObservation],
        width: Int32,
        height: Int32
    ) -> DetectionFrame<PoseDetection> {
        let w = Float(width), h = Float(height)
        let detections = observations.prefix(WireCounts.maxDetections).map { observation in
            PoseDetection(
                confidence: observation.confidence,
                joints: wirePoints(observation.allJoints(), order: bodyJointNames, frameWidth: w, frameHeight: h)
            )
        }
        return DetectionFrame(width: width, height: height, detections: Array(detections))
    }

    // MARK: - 3D body poses

    /// The 17 joints of /poses3d/arr, root first (JointOrder.body3D17).
    private static let body3DJointNames: [HumanBodyPose3DObservation.JointName] = [
        .root, .spine, .centerShoulder, .centerHead, .topHead,
        .leftShoulder, .leftElbow, .leftWrist,
        .rightShoulder, .rightElbow, .rightWrist,
        .leftHip, .leftKnee, .leftAnkle,
        .rightHip, .rightKnee, .rightAnkle
    ]

    #if DEBUG
    nonisolated(unsafe) private static var loggedHeightTechnique = false
    #endif

    static func mapBodyPoses3D(
        _ observations: [HumanBodyPose3DObservation],
        width: Int32,
        height: Int32
    ) -> DetectionFrame<Pose3DDetection> {
        let w = Float(width), h = Float(height)
        let detections = observations.prefix(WireCounts.maxDetections).map { observation in
            #if DEBUG
            if !loggedHeightTechnique {
                loggedHeightTechnique = true
                print("[TrackOSC] 3D body height estimation: \(observation.heightEstimationTechnique)")
            }
            #endif
            let joints = body3DJointNames.map { name -> WirePoint3D in
                // Translation column of the camera-relative transform: metres.
                let position = observation.cameraRelativePosition(for: name).columns.3
                // Vision's 2D projection of the joint, normalized, origin
                // bottom-left like every other Vision point.
                let image = observation.pointInImage(for: name)
                let projected = CoordinateMapper.point(
                    normalizedX: image.x,
                    normalizedY: image.y,
                    confidence: 1,
                    frameWidth: w,
                    frameHeight: h
                )
                return WirePoint3D(x: position.x, y: position.y, z: position.z, px: projected.x, py: projected.y)
            }
            return Pose3DDetection(
                confidence: observation.confidence,
                bodyHeight: Float(observation.bodyHeight.converted(to: .meters).value),
                joints: joints
            )
        }
        return DetectionFrame(width: width, height: height, detections: Array(detections))
    }

    // MARK: - Hands

    /// The 21 joints of the wire format (JointOrder.hand21). Apple names the
    /// fifth finger "little"; the wire format calls it "pinky" (VisionOSC).
    private static let handJointNames: [HumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]

    static func mapHands(
        _ observations: [HumanHandPoseObservation],
        width: Int32,
        height: Int32
    ) -> DetectionFrame<HandDetection> {
        let w = Float(width), h = Float(height)
        let detections = observations.prefix(WireCounts.maxDetections).map { observation in
            HandDetection(
                confidence: observation.confidence,
                joints: wirePoints(observation.allJoints(), order: handJointNames, frameWidth: w, frameHeight: h)
            )
        }
        return DetectionFrame(width: width, height: height, detections: Array(detections))
    }

    // MARK: - Animal poses

    /// The 25 joints of /animalposes/arr (JointOrder.animal25).
    private static let animalJointNames: [AnimalBodyPoseObservation.JointName] = [
        .nose, .leftEye, .rightEye,
        .leftEarTop, .leftEarMiddle, .leftEarBottom,
        .rightEarTop, .rightEarMiddle, .rightEarBottom,
        .neck,
        .leftFrontElbow, .leftFrontKnee, .leftFrontPaw,
        .rightFrontElbow, .rightFrontKnee, .rightFrontPaw,
        .leftBackElbow, .leftBackKnee, .leftBackPaw,
        .rightBackElbow, .rightBackKnee, .rightBackPaw,
        .tailTop, .tailMiddle, .tailBottom
    ]

    static func mapAnimalPoses(
        _ observations: [AnimalBodyPoseObservation],
        width: Int32,
        height: Int32
    ) -> DetectionFrame<AnimalPoseDetection> {
        let w = Float(width), h = Float(height)
        let detections = observations.prefix(WireCounts.maxDetections).map { observation in
            AnimalPoseDetection(
                confidence: observation.confidence,
                joints: wirePoints(observation.allJoints(), order: animalJointNames, frameWidth: w, frameHeight: h)
            )
        }
        return DetectionFrame(width: width, height: height, detections: Array(detections))
    }

    // MARK: - Faces

    /// One frame's face output: the VisionOSC-compatible landmark
    /// constellations plus the additive v1.3 boundary messages. `boxes` and
    /// `contours` come ungated from the same observation list, so face i in
    /// /faces/box is face i in /faces/contour. `landmarks` keeps the
    /// defensive 76-point gate (the /faces/arr wire contract) and can
    /// therefore contain fewer faces.
    struct FaceFrames {
        var landmarks: DetectionFrame<FaceDetection>
        var boxes: DetectionFrame<FaceBoxDetection>
        var contours: DetectionFrame<FaceContourDetection>
    }

    static func mapFaces(
        _ observations: [FaceObservation],
        width: Int32,
        height: Int32
    ) -> FaceFrames {
        let w = Float(width), h = Float(height)
        let capped = observations.prefix(WireCounts.maxDetections)
        let frameSize = CGSize(width: CGFloat(width), height: CGFloat(height))

        let landmarkDetections = capped.compactMap { observation -> FaceDetection? in
            guard let landmarks = observation.landmarks else { return nil }
            // Assemble the wire's 76 points from the named regions in the
            // documented order (FaceLandmarks.swift), converting each with
            // Vision's own image-coordinate mapping. This no longer depends
            // on allPoints' order or count, and a region that comes back with
            // a different number of points is resampled to the expected one.
            var points: [WirePoint] = []
            points.reserveCapacity(WireCounts.facePoints)
            for (region, expected) in FaceLandmarks.assemblyOrder(landmarks) {
                let imagePoints = region?.pointsInImageCoordinates(frameSize, origin: .upperLeft) ?? []
                let resampled = resample(imagePoints, to: expected)
                // Every point carries the face's confidence: a detected face
                // has all 76 landmarks, so none is "missing".
                points += resampled.map { WirePoint(x: Float($0.x), y: Float($0.y), confidence: observation.confidence) }
            }
            guard points.count == WireCounts.facePoints else { return nil }
            return FaceDetection(confidence: observation.confidence, points: points)
        }

        let boxDetections = capped.map { observation in
            FaceBoxDetection(
                confidence: observation.confidence,
                box: CoordinateMapper.rect(
                    normalized: observation.boundingBox.cgRect,
                    frameWidth: w,
                    frameHeight: h
                ),
                rollDegrees: Float(observation.roll.converted(to: .degrees).value),
                yawDegrees: Float(observation.yaw.converted(to: .degrees).value),
                pitchDegrees: Float(observation.pitch.converted(to: .degrees).value)
            )
        }

        let contourDetections = capped.map { observation -> FaceContourDetection in
            let contourPoints = observation.landmarks?.faceContour
                .pointsInImageCoordinates(frameSize, origin: .upperLeft) ?? []
            return FaceContourDetection(
                confidence: observation.confidence,
                points: contourPoints.map { WireXY(x: Float($0.x), y: Float($0.y)) }
            )
        }

        return FaceFrames(
            landmarks: DetectionFrame(width: width, height: height, detections: Array(landmarkDetections)),
            boxes: DetectionFrame(width: width, height: height, detections: Array(boxDetections)),
            contours: DetectionFrame(width: width, height: height, detections: Array(contourDetections))
        )
    }

    // MARK: - Text

    static func mapTexts(
        _ observations: [RecognizedTextObservation],
        width: Int32,
        height: Int32
    ) -> DetectionFrame<BoxDetection> {
        let w = Float(width), h = Float(height)
        let detections = observations.prefix(WireCounts.maxDetections).compactMap { observation -> BoxDetection? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return BoxDetection(
                confidence: candidate.confidence,
                box: CoordinateMapper.rect(
                    normalized: observation.boundingBox.cgRect,
                    frameWidth: w,
                    frameHeight: h
                ),
                label: candidate.string
            )
        }
        return DetectionFrame(width: width, height: height, detections: Array(detections))
    }

    // MARK: - Animals

    static func mapAnimals(
        _ observations: [RecognizedObjectObservation],
        width: Int32,
        height: Int32
    ) -> DetectionFrame<BoxDetection> {
        let w = Float(width), h = Float(height)
        let detections = observations.prefix(WireCounts.maxDetections).compactMap { observation -> BoxDetection? in
            guard let label = observation.labels.first else { return nil }
            return BoxDetection(
                confidence: observation.confidence,
                box: CoordinateMapper.rect(
                    normalized: observation.boundingBox.cgRect,
                    frameWidth: w,
                    frameHeight: h
                ),
                label: label.identifier
            )
        }
        return DetectionFrame(width: width, height: height, detections: Array(detections))
    }

    // MARK: - Humans

    static func mapHumans(
        _ observations: [HumanObservation],
        width: Int32,
        height: Int32
    ) -> DetectionFrame<HumanDetection> {
        let w = Float(width), h = Float(height)
        let detections = observations.prefix(WireCounts.maxDetections).map { observation in
            HumanDetection(
                confidence: observation.confidence,
                box: CoordinateMapper.rect(
                    normalized: observation.boundingBox.cgRect,
                    frameWidth: w,
                    frameHeight: h
                )
            )
        }
        return DetectionFrame(width: width, height: height, detections: Array(detections))
    }

    // MARK: - Barcodes

    static func mapBarcodes(
        _ observations: [BarcodeObservation],
        width: Int32,
        height: Int32
    ) -> DetectionFrame<BarcodeDetection> {
        let w = Float(width), h = Float(height)
        let detections = observations.prefix(WireCounts.maxDetections).map { observation in
            let corners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
                .map { CoordinateMapper.xy(normalizedX: $0.x, normalizedY: $0.y, frameWidth: w, frameHeight: h) }
            return BarcodeDetection(
                confidence: observation.confidence,
                box: CoordinateMapper.rect(
                    normalized: observation.boundingBox.cgRect,
                    frameWidth: w,
                    frameHeight: h
                ),
                corners: corners,
                symbology: symbologyName(observation.symbology),
                payload: observation.payloadString ?? ""
            )
        }
        return DetectionFrame(width: width, height: height, detections: Array(detections))
    }

    /// Linear resampling of a polyline to a fixed point count; an empty
    /// region becomes that many points at the origin with the face's
    /// confidence (a receiver can still draw the rest of the face).
    private static func resample(_ points: [CGPoint], to count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        guard !points.isEmpty else { return Array(repeating: .zero, count: count) }
        guard points.count != count else { return points }
        guard points.count > 1 else { return Array(repeating: points[0], count: count) }
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1) * Double(points.count - 1)
            let a = Int(t.rounded(.down)), b = min(a + 1, points.count - 1)
            let f = t - Double(a)
            return CGPoint(x: points[a].x + (points[b].x - points[a].x) * f,
                           y: points[a].y + (points[b].y - points[a].y) * f)
        }
    }

    // MARK: - Contours, horizon, rectangles (v1.6)

    /// Every contour Vision found, walked depth-first from the top-level
    /// ones (so an outline precedes the holes inside it), simplified and
    /// capped so one message fits a datagram.
    static func mapContours(
        _ observation: ContoursObservation,
        width: Int32,
        height: Int32
    ) -> DetectionFrame<ContourDetection> {
        let w = Float(width), h = Float(height)
        var detections: [ContourDetection] = []
        var pointBudget = WireCounts.maxContourPoints
        var stack = Array(observation.topLevelContours.reversed())
        while let contour = stack.popLast() {
            guard detections.count < WireCounts.maxContours, pointBudget > 0 else { break }
            stack.append(contentsOf: contour.childContours.reversed())
            // Simplify: a small epsilon keeps the shape but drops most of
            // the pixel-level vertices.
            let simplified = (try? contour.polygonApproximation(epsilon: 0.004)) ?? contour
            var points = simplified.normalizedPoints
            guard points.count >= 3 else { continue }
            if points.count > 256 {
                let stride = Float(points.count) / 256
                points = (0..<256).map { points[Int(Float($0) * stride)] }
            }
            if points.count > pointBudget { continue }
            pointBudget -= points.count
            detections.append(ContourDetection(
                confidence: observation.confidence,
                points: points.map { CoordinateMapper.xy(normalizedX: CGFloat($0.x), normalizedY: CGFloat($0.y), frameWidth: w, frameHeight: h) }
            ))
        }
        return DetectionFrame(width: width, height: height, detections: detections)
    }

    /// The horizon as an angle plus the line through the frame's centre at
    /// that angle. Vision's angle is counter-clockwise positive in its own
    /// (y-up) space; on the wire's y-down frame the right-hand end of a
    /// positive angle is therefore higher. One constant to flip if a device
    /// reports it the other way.
    static let horizonPositiveRaisesRight = true

    static func mapHorizon(
        _ observation: HorizonObservation?,
        width: Int32,
        height: Int32
    ) -> DetectionFrame<HorizonDetection> {
        guard let observation else {
            return DetectionFrame(width: width, height: height, detections: [])
        }
        let w = Float(width), h = Float(height)
        let degrees = Float(observation.angle.converted(to: .degrees).value)
        let radians = degrees * .pi / 180
        let dy = tanf(radians) * (w / 2) * (horizonPositiveRaisesRight ? -1 : 1)
        let detection = HorizonDetection(
            confidence: observation.confidence,
            angleDegrees: degrees,
            start: WireXY(x: 0, y: h / 2 - dy),
            end: WireXY(x: w, y: h / 2 + dy)
        )
        return DetectionFrame(width: width, height: height, detections: [detection])
    }

    static func mapRectangles(
        _ observations: [RectangleObservation],
        width: Int32,
        height: Int32
    ) -> DetectionFrame<RectangleDetection> {
        let w = Float(width), h = Float(height)
        let detections = observations.prefix(WireCounts.maxDetections).map { observation in
            let corners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
                .map { CoordinateMapper.xy(normalizedX: $0.x, normalizedY: $0.y, frameWidth: w, frameHeight: h) }
            return RectangleDetection(
                confidence: observation.confidence,
                box: CoordinateMapper.rect(
                    normalized: observation.boundingBox.cgRect,
                    frameWidth: w,
                    frameHeight: h
                ),
                corners: corners
            )
        }
        return DetectionFrame(width: width, height: height, detections: Array(detections))
    }

    /// The wire's symbology string: VNBarcodeSymbology's names without the prefix.
    static func symbologyName(_ symbology: BarcodeSymbology) -> String {
        switch symbology {
        case .aztec: "Aztec"
        case .code39: "Code39"
        case .code39Checksum: "Code39Checksum"
        case .code39FullASCII: "Code39FullASCII"
        case .code39FullASCIIChecksum: "Code39FullASCIIChecksum"
        case .code93: "Code93"
        case .code93i: "Code93i"
        case .code128: "Code128"
        case .dataMatrix: "DataMatrix"
        case .ean8: "EAN8"
        case .ean13: "EAN13"
        case .i2of5: "I2of5"
        case .i2of5Checksum: "I2of5Checksum"
        case .itf14: "ITF14"
        case .pdf417: "PDF417"
        case .qr: "QR"
        case .upce: "UPCE"
        case .codabar: "Codabar"
        case .gs1DataBar: "GS1DataBar"
        case .gs1DataBarExpanded: "GS1DataBarExpanded"
        case .gs1DataBarLimited: "GS1DataBarLimited"
        case .microPDF417: "MicroPDF417"
        case .microQR: "MicroQR"
        case .msiPlessey: "MSIPlessey"
        @unknown default: String(describing: symbology)
        }
    }
}
