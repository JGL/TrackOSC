//
//  ReceiverStore.swift
//  TrackOSC Receiver (macOS)
//
//  Receiver-only state on top of the shared ReceiverModel: which visualiser
//  is showing and the 3D view reset.
//

import Foundation
import Observation
import PoseioscShared

@Observable @MainActor
final class ReceiverStore {
    let model = ReceiverModel(app: .receiver)

    /// 2D canvas or 3D scene in the left pane; remembered across launches.
    var visualizerMode: VisualizerMode {
        didSet { UserDefaults.standard.set(visualizerMode.rawValue, forKey: "visualizerMode") }
    }
    /// Bumped by "Reset view" to put the 3D camera back where it started.
    var resetViewToken = 0

    init() {
        visualizerMode = UserDefaults.standard.string(forKey: "visualizerMode")
            .flatMap(VisualizerMode.init(rawValue:)) ?? .twoD
    }

    /// The 3D poses to draw right now: the latest /poses3d/arr frame if it
    /// is fresh, otherwise nothing.
    func freshPoses3D(at now: Date = .now) -> [Pose3DDetection] {
        guard case .poses3D(let decoded)? = model.fresh(.poses3D, at: now) else { return [] }
        return decoded.detections
    }
}
