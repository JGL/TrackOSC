//
//  ReceiverService.swift
//  TrackOSC (ReceiverCore)
//
//  Owns the UDP listener and the Bonjour advertisement. Every datagram goes
//  through the same pipeline on the receive queue:
//
//      taps (forwarding, recording) → decode → state → frame subscribers
//
//  Decoded frames accumulate behind a lock; UIs pull snapshots at display
//  rate, and apps that react to events (Speaker, Router) read the
//  `frames()` stream instead.
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
    var unknownMessages: UInt64
    var cameraInfo: CameraInfo?
    var cameraInfoSeenAt: Date?
}

final class ReceiverService: Sendable {
    private struct State {
        var latest: [FrameKind: TimestampedFrame] = [:]
        var recentTimestamps: [FrameKind: [Date]] = [:]
        var pendingLog: [LogEntry] = []
        var lastLogTimes: [FrameKind: Date] = [:]
        var lastUnknownLogTimes: [String: Date] = [:]
        var totalMessages: UInt64 = 0
        var unknownMessages: UInt64 = 0
        var nextLogID: UInt64 = 0
        var cameraInfo: CameraInfo?
        var cameraInfoSeenAt: Date?
    }

    private struct Subscribers {
        var next: UInt64 = 0
        var continuations: [UInt64: AsyncStream<ReceivedFrame>.Continuation] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let server = OSAllocatedUnfairLock<UDPDatagramServer?>(initialState: nil)
    private let taps = OSAllocatedUnfairLock<[ObjectIdentifier: any DatagramTap]>(initialState: [:])
    private let subscribers = OSAllocatedUnfairLock(initialState: Subscribers())
    private let advertiser = BonjourAdvertiser()

    /// Only one log entry per kind per interval, so the log stays readable at 60 Hz.
    private static let logSampleInterval: TimeInterval = 0.25
    /// Unknown or undecodable addresses are logged at most this often each,
    /// so a foreign 60 Hz stream is visible without flooding the log.
    private static let unknownLogInterval: TimeInterval = 5.0

    /// Binds the port; throws `UDPDatagramServer.ServerError.portInUse` when taken.
    func start(port: UInt16) throws {
        let newServer = try UDPDatagramServer(port: port) { [weak self] datagram, host, instant in
            self?.handle(datagram: datagram, from: host, at: instant)
        }
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
    func advertise(name: String, port: UInt16) throws -> String {
        try advertiser.start(name: name, port: port)
        return name
    }

    // MARK: - Taps and subscribers

    func addTap(_ tap: any DatagramTap) {
        taps.withLock { $0[ObjectIdentifier(tap)] = tap }
    }

    func removeTap(_ tap: any DatagramTap) {
        _ = taps.withLock { $0.removeValue(forKey: ObjectIdentifier(tap)) }
    }

    /// Every decoded frame, in arrival order, for apps that react to events.
    /// A slow consumer drops the oldest frames rather than stalling receive.
    func frames() -> AsyncStream<ReceivedFrame> {
        let (stream, continuation) = AsyncStream.makeStream(of: ReceivedFrame.self, bufferingPolicy: .bufferingNewest(256))
        let id = subscribers.withLock { s in
            let id = s.next
            s.next += 1
            s.continuations[id] = continuation
            return id
        }
        continuation.onTermination = { [subscribers] _ in
            _ = subscribers.withLock { $0.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    // MARK: - Reading state

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
                unknownMessages: s.unknownMessages,
                cameraInfo: s.cameraInfo,
                cameraInfoSeenAt: s.cameraInfoSeenAt
            )
        }
    }

    /// The latest frame of every kind, for render loops that run off the main actor.
    func currentFrames() -> [FrameKind: TimestampedFrame] {
        state.withLock { $0.latest }
    }

    // MARK: - Pipeline

    private func handle(datagram: Data, from host: String, at instant: ContinuousClock.Instant) {
        let taps = taps.withLock { Array($0.values) }
        for tap in taps {
            tap.receive(datagram, from: host, at: instant)
        }

        let now = Date.now
        let packet: OSCPacket?
        do {
            packet = try OSCPacket(from: datagram)
        } catch {
            recordUndecodable(address: "(\(datagram.count) bytes)", note: "not OSC: \(error)", host: host, now: now)
            return
        }
        guard let packet else {
            recordUndecodable(address: "(\(datagram.count) bytes)", note: "not OSC", host: host, now: now)
            return
        }
        handle(packet: packet, from: host, now: now, instant: instant)
    }

    private func handle(packet: OSCPacket, from host: String, now: Date, instant: ContinuousClock.Instant) {
        switch packet {
        case .message(let message):
            handle(message: message, from: host, now: now, instant: instant)
        case .bundle(let bundle):
            for element in bundle.elements {
                handle(packet: element, from: host, now: now, instant: instant)
            }
        }
    }

    private func handle(message: OSCMessage, from host: String, now: Date, instant: ContinuousClock.Instant) {
        let decoded: DecodedFrame
        do {
            decoded = try WireCodec.decode(message)
        } catch {
            let note: String = switch error as? WireCodecError {
            case .unknownAddress: "unknown address"
            case .truncatedMessage(_, let expected, let got): "truncated: expected ≥ \(expected) values, got \(got)"
            case .badValue(_, let index): "bad value at argument \(index)"
            case nil: "undecodable"
            }
            recordUndecodable(address: message.addressPattern.stringValue, note: note, host: host, now: now)
            return
        }

        let kind = FrameKind.from(decoded)
        let count = decoded.detectionCount

        state.withLock { s in
            s.totalMessages += 1
            guard let kind else {
                if case .cameraInfo(let info) = decoded {
                    s.cameraInfo = info
                    s.cameraInfoSeenAt = now
                }
                return
            }
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

        let frame = ReceivedFrame(decoded: decoded, kind: kind, receivedAt: now, instant: instant, senderHost: host)
        let continuations = subscribers.withLock { Array($0.continuations.values) }
        for continuation in continuations {
            continuation.yield(frame)
        }
    }

    /// Counts and (sparsely) logs messages the codec rejected, so anyone
    /// bringing up a new sender or a foreign OSC source can see what arrived.
    private func recordUndecodable(address: String, note: String, host: String, now: Date) {
        state.withLock { s in
            s.totalMessages += 1
            s.unknownMessages += 1
            if let last = s.lastUnknownLogTimes[address], now.timeIntervalSince(last) < Self.unknownLogInterval {
                return
            }
            s.lastUnknownLogTimes[address] = now
            s.pendingLog.append(LogEntry(
                id: s.nextLogID,
                time: now,
                address: address,
                detectionCount: 0,
                senderHost: host,
                note: note
            ))
            s.nextLogID += 1
        }
    }
}
