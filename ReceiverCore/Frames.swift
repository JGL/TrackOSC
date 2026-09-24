//
//  Frames.swift
//  TrackOSC (ReceiverCore)
//
//  Value types the receiver pipeline hands to models and views.
//

import Foundation
import PoseioscShared

/// The most recent decoded frame of one kind, with when and from where it arrived.
struct TimestampedFrame: Sendable {
    var decoded: DecodedFrame
    var receivedAt: Date
    var senderHost: String
}

/// A decoded frame as pushed to `ReceiverService.frames()` subscribers.
struct ReceivedFrame: Sendable {
    var decoded: DecodedFrame
    var kind: FrameKind?          // nil for /camerainfo
    var receivedAt: Date
    var instant: ContinuousClock.Instant
    var senderHost: String
}

/// One sampled line of the receiver log.
struct LogEntry: Identifiable, Sendable {
    let id: UInt64
    var time: Date
    var address: String
    var detectionCount: Int
    var senderHost: String
    /// Set for messages the codec rejected (unknown address, truncated…).
    var note: String? = nil
}

extension DecodedFrame {
    /// Number of detections carried, 0 for /camerainfo.
    var detectionCount: Int {
        switch self {
        case .poses(let f): f.detections.count
        case .poses3D(let f): f.detections.count
        case .hands(let f): f.detections.count
        case .faces(let f): f.detections.count
        case .faceBoxes(let f): f.detections.count
        case .faceContours(let f): f.detections.count
        case .texts(let f): f.detections.count
        case .animals(let f): f.detections.count
        case .animalPoses(let f): f.detections.count
        case .humans(let f): f.detections.count
        case .barcodes(let f): f.detections.count
        case .contours(let f): f.detections.count
        case .horizon(let f): f.detections.count
        case .rectangles(let f): f.detections.count
        case .cameraInfo: 0
        }
    }

    /// The oriented frame size the coordinates refer to.
    var frameSize: (width: Int32, height: Int32) {
        switch self {
        case .poses(let f): (f.width, f.height)
        case .poses3D(let f): (f.width, f.height)
        case .hands(let f): (f.width, f.height)
        case .faces(let f): (f.width, f.height)
        case .faceBoxes(let f): (f.width, f.height)
        case .faceContours(let f): (f.width, f.height)
        case .texts(let f): (f.width, f.height)
        case .animals(let f): (f.width, f.height)
        case .animalPoses(let f): (f.width, f.height)
        case .humans(let f): (f.width, f.height)
        case .barcodes(let f): (f.width, f.height)
        case .contours(let f): (f.width, f.height)
        case .horizon(let f): (f.width, f.height)
        case .rectangles(let f): (f.width, f.height)
        case .cameraInfo(let info): (info.width, info.height)
        }
    }
}
