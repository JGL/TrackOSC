//
//  FrameStats.swift
//  TrackOSC (VisualCore)
//

import Foundation

struct FrameStats: Sendable {
    private(set) var fps: Double = 0
    private(set) var frameMilliseconds: Double = 0
    private var window: [(Double, Double)] = []   // (timestamp, cpu ms)

    mutating func record(cpuSeconds: Double, at now: Double) {
        window.append((now, cpuSeconds * 1000))
        window.removeAll { now - $0.0 > 1 }
        fps = Double(window.count)
        frameMilliseconds = window.isEmpty ? 0 : window.map(\.1).reduce(0, +) / Double(window.count)
    }
}
