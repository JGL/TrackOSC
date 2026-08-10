//
//  FrameKind.swift
//  Poseiosc Receiver (macOS)
//

import PoseioscShared
import SwiftUI

/// The drawable message kinds (the five VisionOSC messages plus the additive
/// v1.3 face-boundary pair), with display metadata for the UI.
enum FrameKind: String, CaseIterable, Identifiable, Sendable {
    case poses, hands, faces, faceBoxes, faceContours, texts, animals

    var id: String { rawValue }

    var address: String {
        switch self {
        case .poses: OSCAddress.poses
        case .hands: OSCAddress.hands
        case .faces: OSCAddress.faces
        case .faceBoxes: OSCAddress.faceBox
        case .faceContours: OSCAddress.faceContour
        case .texts: OSCAddress.texts
        case .animals: OSCAddress.animals
        }
    }

    var color: Color {
        switch self {
        case .poses: .green
        case .hands: .orange
        case .faces, .faceBoxes, .faceContours: .cyan
        case .texts: .yellow
        case .animals: .pink
        }
    }

    /// nil for non-drawable messages (/camerainfo).
    static func from(_ decoded: DecodedFrame) -> FrameKind? {
        switch decoded {
        case .poses: .poses
        case .hands: .hands
        case .faces: .faces
        case .faceBoxes: .faceBoxes
        case .faceContours: .faceContours
        case .texts: .texts
        case .animals: .animals
        case .cameraInfo: nil
        }
    }
}
