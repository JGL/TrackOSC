//
//  FaceLandmarksTests.swift
//  PoseioscSharedTests
//

import Foundation
import Testing
@testable import PoseioscShared

@Suite("Face landmark layout")
struct FaceLandmarksTests {
    private func face(mouthGap: Float) -> [WirePoint] {
        var points = (0..<76).map { _ in WirePoint(x: 0, y: 0, confidence: 1) }
        points[FaceLandmarks.leftPupil] = WirePoint(x: 100, y: 100, confidence: 1)
        points[FaceLandmarks.rightPupil] = WirePoint(x: 160, y: 100, confidence: 1)
        points[FaceLandmarks.innerLipTop] = WirePoint(x: 130, y: 160, confidence: 1)
        points[FaceLandmarks.innerLipBottom] = WirePoint(x: 130, y: 160 + mouthGap, confidence: 1)
        return points
    }

    @Test func rangesCoverAllSeventySixPoints() {
        let ranges = [FaceLandmarks.leftEye, FaceLandmarks.rightEye, FaceLandmarks.leftEyebrow, FaceLandmarks.rightEyebrow,
                      FaceLandmarks.outerLips, FaceLandmarks.innerLips, FaceLandmarks.nose, FaceLandmarks.noseCrest, FaceLandmarks.faceContour]
        var covered = Set<Int>([FaceLandmarks.leftPupil, FaceLandmarks.rightPupil])
        for range in ranges {
            for index in range {
                #expect(!covered.contains(index), "index \(index) claimed twice")
                covered.insert(index)
            }
        }
        #expect(covered == Set(0..<76))
    }

    @Test func mouthOpennessIsRelativeToInterocular() {
        #expect(FaceLandmarks.interocular(face(mouthGap: 0)) == 60)
        #expect(FaceLandmarks.mouthOpenness(face(mouthGap: 0)) == 0)
        #expect(FaceLandmarks.mouthOpenness(face(mouthGap: 30)) == 0.5)
        #expect(FaceLandmarks.mouthOpenness(Array(face(mouthGap: 30).prefix(10))) == nil)
    }
}
