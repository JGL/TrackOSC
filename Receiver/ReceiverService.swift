//
//  ReceiverService.swift
//  Poseiosc Receiver (macOS)
//
//  Owns the OSC UDP server and the Bonjour advertisement. Decoded frames are
//  accumulated behind a lock; the UI pulls snapshots at display rate.
//

import Foundation
import PoseioscShared
import SwiftOSC
import os.lock

struct ReceiverSnapshot: Sendable {
    var latest: [FrameKind: TimestampedFrame]
    var rates: [FrameKind: Double]
    var newLogEntries: [LogEntry]
    var totalMessages: UInt64
    var cameraInfo: CameraInfo?
    var cameraInfoSeenAt: Date?
}

final class ReceiverService: Sendable {
    private struct State {
        var latest: [FrameKind: TimestampedFrame] = [:]
        var recentTimestamps: [FrameKind: [Date]] = [:]
        var pendingLog: [LogEntry] = []
        var lastLogTimes: [FrameKind: Date] = [:]
        var totalMessages: UInt64 = 0
        var nextLogID: UInt64 = 0
        var cameraInfo: CameraInfo?
        var cameraInfoSeenAt: Date?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let server = OSAllocatedUnfairLock<OSCUDPServer?>(initialState: nil)
    private let advertiser = BonjourAdvertiser()

    /// Only one log entry per kind per interval, so the log stays readable at 60 Hz.
    private static let logSampleInterval: TimeInterval = 0.25

    func start(port: UInt16) throws {
        let newServer = OSCUDPServer(port: port)
        newServer.setReceiveHandler(.messages { [weak self] message, _, host, _ in
            self?.handle(message: message, from: host)
        })
        try newServer.start()
        server.withLock { current in
            current?.stop()
            current = newServer
        }
    }

    func stop() {
        server.withLock { current in
            current?.stop()
            current = nil
        }
        advertiser.stop()
        state.withLock { $0 = State() }
    }

    /// Starts Bonjour advertising; returns the advertised service name.
    func advertise(port: UInt16) throws -> String {
        let name = "TrackOSC Receiver (\(Host.current().localizedName ?? "Mac"))"
        try advertiser.start(name: name, port: port)
        return name
    }

    func takeSnapshot() -> ReceiverSnapshot {
        let now = Date.now
        return state.withLock { s in
            var rates: [FrameKind: Double] = [:]
            for kind in FrameKind.allCases {
                var timestamps = s.recentTimestamps[kind] ?? []
                timestamps.removeAll { now.timeIntervalSince($0) > 1.0 }
                s.recentTimestamps[kind] = timestamps
                rates[kind] = Double(timestamps.count)
            }
            let entries = s.pendingLog
            s.pendingLog = []
            return ReceiverSnapshot(
                latest: s.latest,
                rates: rates,
                newLogEntries: entries,
                totalMessages: s.totalMessages,
                cameraInfo: s.cameraInfo,
                cameraInfoSeenAt: s.cameraInfoSeenAt
            )
        }
    }

    private func handle(message: OSCMessage, from host: String) {
        guard let decoded = try? WireCodec.decode(message) else { return }
        let now = Date.now

        guard let kind = FrameKind.from(decoded) else {
            if case .cameraInfo(let info) = decoded {
                state.withLock { s in
                    s.totalMessages += 1
                    s.cameraInfo = info
                    s.cameraInfoSeenAt = now
                }
            }
            return
        }
        let count = detectionCount(of: decoded)

        state.withLock { s in
            s.totalMessages += 1
            s.latest[kind] = TimestampedFrame(decoded: decoded, receivedAt: now, senderHost: host)
            s.recentTimestamps[kind, default: []].append(now)

            let lastLogged = s.lastLogTimes[kind]
            if lastLogged == nil || now.timeIntervalSince(lastLogged!) >= Self.logSampleInterval {
                s.pendingLog.append(LogEntry(
                    id: s.nextLogID,
                    time: now,
                    address: kind.address,
                    detectionCount: count,
                    senderHost: host
                ))
                s.nextLogID += 1
                s.lastLogTimes[kind] = now
            }
        }
    }

    private func detectionCount(of decoded: DecodedFrame) -> Int {
        switch decoded {
        case .poses(let f): f.detections.count
        case .hands(let f): f.detections.count
        case .faces(let f): f.detections.count
        case .faceBoxes(let f): f.detections.count
        case .faceContours(let f): f.detections.count
        case .texts(let f): f.detections.count
        case .animals(let f): f.detections.count
        case .cameraInfo: 0
        }
    }
}
