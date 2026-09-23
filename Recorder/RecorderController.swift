//
//  RecorderController.swift
//  TrackOSC Recorder (macOS)
//
//  A datagram tap that appends every incoming datagram to a RecordingWriter.
//  Runs on the receive queue, so it only ever buffers and counts.
//

import Foundation
import PoseioscShared
import os.lock

final class RecorderController: DatagramTap, Sendable {
    struct Status: Sendable {
        var isRecording = false
        var url: URL?
        var recordCount = 0
        var byteCount = 0
        var elapsed: Duration = .zero
        var countsByAddress: [String: Int] = [:]
    }

    private struct State {
        var writer: RecordingWriter?
        var countsByAddress: [String: Int] = [:]
        var lastError: String?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var isRecording: Bool { state.withLock { $0.writer != nil } }

    func start(url: URL) throws {
        let writer = try RecordingWriter(url: url)
        state.withLock { s in
            s.writer = writer
            s.countsByAddress = [:]
            s.lastError = nil
        }
    }

    /// Closes the file and returns its URL (nil when nothing was recording).
    @discardableResult
    func stop() throws -> URL? {
        let writer = state.withLock { s -> RecordingWriter? in
            let w = s.writer
            s.writer = nil
            return w
        }
        try writer?.close()
        return writer?.url
    }

    func status() -> Status {
        state.withLock { s in
            guard let writer = s.writer else {
                return Status(countsByAddress: s.countsByAddress)
            }
            return Status(
                isRecording: true,
                url: writer.url,
                recordCount: writer.recordCount,
                byteCount: writer.byteCount,
                elapsed: .now - writer.startInstant,
                countsByAddress: s.countsByAddress
            )
        }
    }

    func receive(_ datagram: Data, from host: String, at instant: ContinuousClock.Instant) {
        state.withLock { s in
            guard let writer = s.writer else { return }
            do {
                try writer.append(datagram, at: instant)
                s.countsByAddress[Self.address(of: datagram), default: 0] += 1
            } catch {
                s.lastError = error.localizedDescription
            }
        }
    }

    /// The OSC address of a message datagram, "#bundle" for bundles, "?" otherwise.
    static func address(of datagram: Data) -> String {
        guard let first = datagram.first else { return "?" }
        if first == UInt8(ascii: "#") { return "#bundle" }
        guard first == UInt8(ascii: "/") else { return "?" }
        let end = datagram.firstIndex(of: 0) ?? datagram.endIndex
        return String(decoding: datagram[datagram.startIndex..<end], as: UTF8.self)
    }
}
