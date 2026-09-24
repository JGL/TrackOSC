//
//  FaceLandmarks.swift
//  PoseioscShared
//
//  Where each of the 76 /faces/arr points sits. The wire format carries no
//  names; this layout was probed empirically from Vision's constellation
//  (VNFaceLandmarks2D allPoints order) and is what every TrackOSC app and
//  example assumes. Left/right are the subject's own, as Vision reports them.
//

import Foundation
#if canImport(Vision)
import Vision
#endif

public enum FaceLandmarks {
    public static let leftEye = 0..<6
    public static let leftPupil = 6
    public static let rightEye = 7..<13
    public static let rightPupil = 13
    public static let leftEyebrow = 14..<20
    public static let rightEyebrow = 20..<26
    public static let outerLips = 26..<40
    public static let innerLips = 40..<46
    public static let nose = 46..<54
    public static let noseCrest = 54..<59
    public static let medianLine = 59..<59   // not present in the 76-point set
    public static let faceContour = 59..<76

    /// A drawable feature: consecutive points, closed (eyes, lips) or open
    /// (brows, nose, jaw). Drawing these as lines shows every landmark region.
    public struct Region: Sendable {
        public let name: String
        public let range: Range<Int>
        public let isClosed: Bool
    }

    public static let regions: [Region] = [
        Region(name: "leftEye", range: leftEye, isClosed: true),
        Region(name: "rightEye", range: rightEye, isClosed: true),
        Region(name: "leftEyebrow", range: leftEyebrow, isClosed: false),
        Region(name: "rightEyebrow", range: rightEyebrow, isClosed: false),
        Region(name: "outerLips", range: outerLips, isClosed: true),
        Region(name: "innerLips", range: innerLips, isClosed: true),
        Region(name: "nose", range: nose, isClosed: false),
        Region(name: "noseCrest", range: noseCrest, isClosed: false),
        Region(name: "faceContour", range: faceContour, isClosed: false),
    ]

#if canImport(Vision)
    /// The wire's point order as Vision regions with their expected point
    /// counts (sums to 76): left eye, left pupil, right eye, right pupil,
    /// left brow, right brow, outer lips, inner lips, nose, nose crest, jaw.
    @available(macOS 15, iOS 18, *)
    public static func assemblyOrder(_ landmarks: FaceObservation.Landmarks2D) -> [(region: FaceObservation.Landmarks2D.Region?, count: Int)] {
        [
            (landmarks.leftEye, leftEye.count),
            (landmarks.leftPupil, 1),
            (landmarks.rightEye, rightEye.count),
            (landmarks.rightPupil, 1),
            (landmarks.leftEyebrow, leftEyebrow.count),
            (landmarks.rightEyebrow, rightEyebrow.count),
            (landmarks.outerLips, outerLips.count),
            (landmarks.innerLips, innerLips.count),
            (landmarks.nose, nose.count),
            (landmarks.noseCrest, noseCrest.count),
            (landmarks.faceContour, faceContour.count),
        ]
    }
#endif

    /// Inner-lip points used for mouth openness: top centre and bottom centre.
    public static let innerLipTop = 41
    public static let innerLipBottom = 44

    /// Distance between the pupils, the natural unit for face measurements.
    public static func interocular(_ points: [WirePoint]) -> Float? {
        guard points.count >= 76 else { return nil }
        let l = points[leftPupil], r = points[rightPupil]
        return hypot(l.x - r.x, l.y - r.y)
    }

    /// Mouth openness as a fraction of the interocular distance: about 0
    /// closed, 0.3 slightly open, 0.6 and above wide open. nil when the face
    /// has fewer than 76 points or the eyes coincide.
    public static func mouthOpenness(_ points: [WirePoint]) -> Float? {
        guard points.count >= 76, let unit = interocular(points), unit > 0.5 else { return nil }
        let top = points[innerLipTop], bottom = points[innerLipBottom]
        return hypot(top.x - bottom.x, top.y - bottom.y) / unit
    }

    /// Centre of the pupils, the point to anchor face things on.
    public static func eyeCentre(_ points: [WirePoint]) -> WirePoint? {
        guard points.count >= 76 else { return nil }
        let l = points[leftPupil], r = points[rightPupil]
        return WirePoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2, confidence: min(l.confidence, r.confidence))
    }
}
