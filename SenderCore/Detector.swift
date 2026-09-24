//
//  Detector.swift
//  TrackOSC Sender (shared)
//
//  The single source of truth for the detectors both senders can run: chip
//  order and labels, colours (shared with the overlay), defaults, and the
//  UserDefaults keys the toggles persist under.
//

import SwiftUI

/// Every detector the senders can run. `allCases` order is the chip order.
enum Detector: String, CaseIterable, Identifiable, Sendable {
    case poses
    case poses3D
    case hands
    case faces
    case texts
    case animals
    case animalPoses
    case humans
    case barcodes
    case contours
    case horizon
    case rectangles

    var id: String { rawValue }

    /// Chip label.
    var label: String {
        switch self {
        case .poses: "2D Body"
        case .poses3D: "3D Body"
        case .hands: "Hand"
        case .faces: "Face"
        case .texts: "Text"
        case .animals: "Animal"
        case .animalPoses: "Animal Pose"
        case .humans: "Human"
        case .barcodes: "Barcode"
        case .contours: "Contours"
        case .horizon: "Horizon"
        case .rectangles: "Rectangle"
        }
    }

    /// Chip and overlay colour. The receiver's FrameKind uses the same set.
    var color: Color {
        switch self {
        case .poses: .green
        case .poses3D: .mint
        case .hands: .orange
        case .faces: .cyan
        case .texts: .yellow
        case .animals: .pink
        case .animalPoses: .brown
        case .humans: .indigo
        case .barcodes: .purple
        case .contours: .white
        case .horizon: .red
        case .rectangles: .teal
        }
    }

    /// Text colour on a lit chip: black reads best on the bright legacy
    /// colours, white on the darker new ones.
    var chipTextColor: Color {
        switch self {
        case .animalPoses, .humans, .barcodes, .horizon: .white
        default: .black
        }
    }

    /// VisionOSC's defaults: body, hand and face on; everything else off.
    var isOnByDefault: Bool {
        switch self {
        case .poses, .hands, .faces: true
        default: false
        }
    }

    /// UserDefaults key. The five legacy keys keep their v1.0 names so an
    /// upgrade preserves users' choices.
    var defaultsKey: String {
        switch self {
        case .poses: "detectPoses"
        case .hands: "detectHands"
        case .faces: "detectFaces"
        case .texts: "detectTexts"
        case .animals: "detectAnimals"
        case .poses3D: "detectPoses3D"
        case .animalPoses: "detectAnimalPoses"
        case .humans: "detectHumans"
        case .barcodes: "detectBarcodes"
        case .contours: "detectContours"
        case .horizon: "detectHorizon"
        case .rectangles: "detectRectangles"
        }
    }

    static let defaultSet: Set<Detector> = Set(allCases.filter(\.isOnByDefault))

    /// Reads the persisted toggle set, applying defaults for absent keys.
    static func loadEnabled(from defaults: UserDefaults) -> Set<Detector> {
        Set(allCases.filter { detector in
            defaults.object(forKey: detector.defaultsKey) == nil
                ? detector.isOnByDefault
                : defaults.bool(forKey: detector.defaultsKey)
        })
    }

    /// Persists the toggle set, one key per detector.
    static func store(_ enabled: Set<Detector>, in defaults: UserDefaults) {
        for detector in allCases {
            defaults.set(enabled.contains(detector), forKey: detector.defaultsKey)
        }
    }
}
