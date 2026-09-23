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
