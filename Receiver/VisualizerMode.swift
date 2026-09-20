//
//  VisualizerMode.swift
//  TrackOSC Receiver (macOS)
//

/// Which visualiser fills the left pane: the 2D canvas (every message kind,
/// in wire pixels) or the 3D scene (/poses3d/arr in metres).
enum VisualizerMode: String, CaseIterable, Identifiable, Sendable {
    case twoD = "2D"
    case threeD = "3D"

    var id: String { rawValue }
}
