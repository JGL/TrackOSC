//
//  ObservationMapping.swift
//  Poseiosc Sender (iOS)
//
//  Vision observations → wire models. All VisionOSC fidelity decisions live
//  here: joint ordering, coordinate flips, missing-joint sentinels.
//

import Foundation
import Vision
import PoseioscShared

enum ObservationMapping {
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
            let joints = observation.allJoints()
            let points = bodyJointNames.map { name -> WirePoint in
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
            return PoseDetection(confidence: observation.confidence, joints: points)
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
            let joints = observation.allJoints()
            let points = handJointNames.map { name -> WirePoint in
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
            return HandDetection(confidence: observation.confidence, joints: points)
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
            guard let allPoints = observation.landmarks?.allPoints else { return nil }

            // Don't assume anything about the landmarks' normalization basis
            // (it is NOT documented in the public interface): let Vision
            // itself convert to image pixels, requesting the wire format's
            // upper-left origin directly.
            let imagePoints = allPoints.pointsInImageCoordinates(frameSize, origin: .upperLeft)
            guard imagePoints.count == WireCounts.facePoints else { return nil }

            let precisions = allPoints.precisionEstimatesPerPoint
            let points = imagePoints.enumerated().map { index, point in
                WirePoint(
                    x: Float(point.x),
                    y: Float(point.y),
                    confidence: precisions.flatMap { index < $0.count ? Float($0[index]) : nil } ?? observation.confidence
                )
            }
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
}
