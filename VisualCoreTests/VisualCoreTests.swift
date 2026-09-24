//
//  VisualCoreTests.swift
//  TrackOSC Colours tests
//
//  Hosted by the Colours app so VisualCore and ReceiverCore compile once.
//

import Foundation
import Testing
@testable import TrackOSCColours

@Suite("Person tracker")
struct PersonTrackerTests {
    private func skeleton(at centre: SIMD2<Float>) -> (joints: [SIMD2<Float>], visible: [Bool]) {
        let joints = (0..<17).map { i in centre + SIMD2<Float>(Float(i % 3) * 0.01, Float(i / 3) * 0.02) }
        return (joints, Array(repeating: true, count: 17))
    }

    @Test func identitiesSurviveMovementAndBriefGaps() {
        var tracker = PersonTracker()
        tracker.smoothing = 0
        tracker.update(detections: [skeleton(at: SIMD2(0.3, 0.5)), skeleton(at: SIMD2(0.7, 0.5))], time: 0, dt: 1 / 30)
        let ids = tracker.tracked.map(\.id)
        #expect(ids.count == 2)
        // Both drift a little; the same ids follow them.
        tracker.update(detections: [skeleton(at: SIMD2(0.72, 0.5)), skeleton(at: SIMD2(0.32, 0.5))], time: 1 / 30, dt: 1 / 30)
        let byX = tracker.tracked.sorted { $0.joints[0].x < $1.joints[0].x }.map(\.id)
        #expect(byX == ids)
        // A dropped frame keeps them (missing), then they come back.
        tracker.update(detections: [], time: 2 / 30, dt: 1 / 30)
        #expect(tracker.tracked.count == 2)
        let allMissing = tracker.tracked.allSatisfy(\.missing)
        #expect(allMissing)
        tracker.update(detections: [skeleton(at: SIMD2(0.32, 0.5))], time: 3 / 30, dt: 1 / 30)
        let present = tracker.tracked.first { !$0.missing }?.id
        #expect(present == ids[0])
        // After the grace period the absent one goes.
        tracker.update(detections: [skeleton(at: SIMD2(0.32, 0.5))], time: 1.0, dt: 1 / 30)
        #expect(tracker.tracked.count == 1)
    }

    @Test func smoothingProducesVelocity() {
        var tracker = PersonTracker()
        tracker.smoothing = 0
        tracker.update(detections: [skeleton(at: SIMD2(0.3, 0.5))], time: 0, dt: 1 / 30)
        tracker.update(detections: [skeleton(at: SIMD2(0.4, 0.5))], time: 1 / 30, dt: 1 / 30)
        let v = tracker.tracked[0].velocities[0]
        #expect(abs(v.x - 3.0) < 0.01)   // 0.1 scene units in 1/30 s
        #expect(abs(v.y) < 0.001)
    }
}

@Suite("Palettes and parameters")
struct PaletteTests {
    @Test func paletteLoopsAndInterpolates() {
        let palette = Palette(name: "test", stops: [RGB(0, 0, 0), RGB(1, 1, 1)])
        #expect(palette.color(at: 0) == RGB(0, 0, 0))
        #expect(palette.color(at: 0.25).r == 0.5)
        #expect(palette.color(at: 0.5) == RGB(1, 1, 1))
        #expect(palette.color(at: 1.0) == RGB(0, 0, 0))   // loops
        #expect(Palette.curated.count == 12)
        let sane = Palette.curated.allSatisfy { $0.stops.count >= 2 && $0.stops.count <= Palette.maxStops }
        #expect(sane)
    }

    @Test func parametersPackClampAndRandomiseWithinRange() {
        let specs = [ParameterSpec("a", "A", 0...1, default: 0.5), ParameterSpec("b", "B", 10...20, default: 15)]
        let packed = specs.packed(["a": 5, "b": 0], count: 4)
        #expect(packed == [1, 10, 0, 0])
        let random = specs.randomised()
        #expect((0...1).contains(random["a"]!) && (10...20).contains(random["b"]!))
        #expect(specs.defaults == ["a": 0.5, "b": 15])
    }

    @Test func everyModeHasDistinctIdsAndFewParameters() {
        let ids = ColoursModes.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        let few = ColoursModes.all.allSatisfy { $0.parameters.count <= Int(VC_MAX_PARAMS) }
        #expect(few)
    }
}
