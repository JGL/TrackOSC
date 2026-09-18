//
//  ReceiverModel.swift
//  TrackOSC Receiver (macOS)
//
//  UI-facing state. The OSC server can deliver hundreds of messages per second,
//  so ReceiverService accumulates off the main thread and this model is
//  refreshed at display rate (30 Hz) to keep SwiftUI invalidation cheap.
//

import Foundation
import PoseioscShared
import Observation

struct TimestampedFrame: Sendable {
    var decoded: DecodedFrame
    var receivedAt: Date
    var senderHost: String
}

struct LogEntry: Identifiable, Sendable {
    let id: UInt64
    var time: Date
    var address: String
    var detectionCount: Int
    var senderHost: String
    /// Set for messages the codec rejected (unknown address, truncated…).
    var note: String? = nil
}

@Observable @MainActor
final class ReceiverModel {
    /// Most recent frame per message kind; the visualiser draws these.
    var latest: [FrameKind: TimestampedFrame] = [:]
    /// Messages per second per kind, over a 1-second sliding window.
    var rates: [FrameKind: Double] = [:]
    /// Recent messages, newest first. Capped.
    var log: [LogEntry] = []
    var isLogPaused = false

    var listenPort: UInt16 = 9527
    var isListening = false
    var lastError: String?
    var advertisedName: String?

    /// Total messages received since launch.
    var totalMessages: UInt64 = 0
    /// Messages the codec rejected since launch (unknown address, malformed).
    var unknownMessages: UInt64 = 0

    /// Latest /camerainfo from the sender (nil until one arrives or when stale).
    var cameraInfo: CameraInfo?

    /// 2D canvas or 3D scene in the left pane; remembered across launches.
    var visualizerMode: VisualizerMode {
        didSet { UserDefaults.standard.set(visualizerMode.rawValue, forKey: "visualizerMode") }
    }
    /// Bumped by "Reset view" to put the 3D camera back where it started.
    var resetViewToken = 0

    private let service = ReceiverService()
    private var refreshTask: Task<Void, Never>?

    static let logCap = 300
    /// A frame older than this is considered stale and no longer drawn.
    static let staleInterval: TimeInterval = 0.5

    init() {
        listenPort = UInt16(UserDefaults.standard.integer(forKey: "listenPort").clamped(to: 1...65535, fallback: 9527))
        visualizerMode = UserDefaults.standard.string(forKey: "visualizerMode")
            .flatMap(VisualizerMode.init(rawValue:)) ?? .twoD
        start()
    }

    func start() {
        do {
            try service.start(port: listenPort)
            isListening = true
            lastError = nil
        } catch {
            isListening = false
            lastError = "Could not listen on port \(listenPort): \(error.localizedDescription)"
        }

        do {
            advertisedName = try service.advertise(port: listenPort)
        } catch {
            advertisedName = nil
            // Bonjour failure is non-fatal: manual host/port entry still works.
            if lastError == nil {
                lastError = "Bonjour advertising failed: \(error.localizedDescription)"
            }
        }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                self?.pullFromService()
            }
        }
    }

    func restart(port: UInt16) {
        UserDefaults.standard.set(Int(port), forKey: "listenPort")
        listenPort = port
        service.stop()
        latest = [:]
        rates = [:]
        start()
    }

    /// The 3D poses to draw right now: the latest /poses3d/arr frame if it
    /// is fresh, otherwise nothing.
    func freshPoses3D(at now: Date = .now) -> [Pose3DDetection] {
        guard
            let frame = latest[.poses3D],
            now.timeIntervalSince(frame.receivedAt) < Self.staleInterval,
            case .poses3D(let decoded) = frame.decoded
        else { return [] }
        return decoded.detections
    }

    private func pullFromService() {
        let snapshot = service.takeSnapshot()
        latest = snapshot.latest
        rates = snapshot.rates
        totalMessages = snapshot.totalMessages
        unknownMessages = snapshot.unknownMessages
        if let seenAt = snapshot.cameraInfoSeenAt, Date.now.timeIntervalSince(seenAt) < 2.0 {
            cameraInfo = snapshot.cameraInfo
        } else {
            cameraInfo = nil
        }
        if !isLogPaused && !snapshot.newLogEntries.isEmpty {
            log.insert(contentsOf: snapshot.newLogEntries.reversed(), at: 0)
            if log.count > Self.logCap {
                log.removeLast(log.count - Self.logCap)
            }
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>, fallback: Int) -> Int {
        self == 0 ? fallback : Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
