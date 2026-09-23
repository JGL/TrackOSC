//
//  FrameKind.swift
//  TrackOSC Receiver (macOS)
//

import PoseioscShared
import SwiftUI

/// The drawable message kinds (the five VisionOSC messages, the additive
/// v1.3 face-boundary pair, and the v1.4 quartet), with display metadata for
/// the UI. `allCases` order is the sidebar's row order.
enum FrameKind: String, CaseIterable, Identifiable, Sendable {
    case poses, poses3D, hands, faces, faceBoxes, faceContours, texts, animals, animalPoses, humans, barcodes

    var id: String { rawValue }

    var address: String {
        switch self {
        case .poses: OSCAddress.poses
        case .poses3D: OSCAddress.poses3D
        case .hands: OSCAddress.hands
        case .faces: OSCAddress.faces
        case .faceBoxes: OSCAddress.faceBox
        case .faceContours: OSCAddress.faceContour
        case .texts: OSCAddress.texts
        case .animals: OSCAddress.animals
        case .animalPoses: OSCAddress.animalPoses
        case .humans: OSCAddress.humans
        case .barcodes: OSCAddress.barcodes
        }
    }

    /// Matches the senders' chip and overlay colours (SenderCore/Detector.swift).
    var color: Color {
        switch self {
        case .poses: .green
        case .poses3D: .mint
        case .hands: .orange
        case .faces, .faceBoxes, .faceContours: .cyan
        case .texts: .yellow
        case .animals: .pink
        case .animalPoses: .brown
        case .humans: .indigo
        case .barcodes: .purple
        }
    }

    /// nil for non-drawable messages (/camerainfo).
    static func from(_ decoded: DecodedFrame) -> FrameKind? {
        switch decoded {
        case .poses: .poses
        case .poses3D: .poses3D
        case .hands: .hands
        case .faces: .faces
        case .faceBoxes: .faceBoxes
        case .faceContours: .faceContours
        case .texts: .texts
        case .animals: .animals
        case .animalPoses: .animalPoses
        case .humans: .humans
        case .barcodes: .barcodes
        case .cameraInfo: nil
        }
    }
}
