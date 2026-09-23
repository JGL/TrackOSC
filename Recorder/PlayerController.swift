//
//  PlayerController.swift
//  TrackOSC Recorder (macOS)
//
//  Plays a .trackosc recording to a host:port, re-sending each datagram at
//  its recorded time (scaled by speed), looping, seeking, and priming the
//  destination with the last /camerainfo after a seek.
//

import AppKit
import Foundation
import Observation
import PoseioscShared
import UniformTypeIdentifiers
import os.lock

@Observable @MainActor
final class PlayerController {
    private(set) var reader: RecordingReader?
    private(set) var fileURL: URL?
    private(set) var isPlaying = false
    /// Position in the recording, refreshed at display rate while playing.
    private(set) var position: Duration = .zero
    /// Datagrams sent since the file was opened, refreshed with `position`.
    private(set) var sentCount: UInt64 = 0
    var lastError: String?
    var recentURLs: [URL] = []

    var isLooping: Bool {
        didSet {
            UserDefaults.standard.set(isLooping, forKey: "playerLoop")
            engine.setLooping(isLooping)
        }
    }
    var speed: Double {
        didSet {
            UserDefaults.standard.set(speed, forKey: "playerSpeed")
            engine.setSpeed(speed)
        }
    }
    var destinationHost: String {
        didSet {
            UserDefaults.standard.set(destinationHost, forKey: "playerHost")
            engine.setDestination(host: destinationHost, port: destinationPort)
        }
    }
    var destinationPort: UInt16 {
        didSet {
            UserDefaults.standard.set(Int(destinationPort), forKey: "playerPort")
            engine.setDestination(host: destinationHost, port: destinationPort)
        }
    }

    static let speeds: [Double] = [0.25, 0.5, 1, 2, 4]
    private let engine = PlaybackEngine()
    private var task: Task<Void, Never>?
    private static let recentKey = "recentRecordings"

    init() {
        let defaults = UserDefaults.standard
        isLooping = defaults.object(forKey: "playerLoop") as? Bool ?? true
        let storedSpeed = defaults.double(forKey: "playerSpeed")
        speed = Self.speeds.contains(storedSpeed) ? storedSpeed : 1
        destinationHost = defaults.string(forKey: "playerHost") ?? "127.0.0.1"
        let storedPort = defaults.integer(forKey: "playerPort")
        destinationPort = (1...65535).contains(storedPort) ? UInt16(storedPort) : TrackOSCApp.defaultPort
        engine.setLooping(isLooping)
        engine.setSpeed(speed)
        engine.setDestination(host: destinationHost, port: destinationPort)
        loadRecents()
    }

    var duration: Duration { reader?.duration ?? .zero }

    // MARK: - Files

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(exportedAs: RecordingFormat.uniformTypeIdentifier)]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a TrackOSC recording to play."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    func open(url: URL) {
        stop()
        lastError = nil
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let reader = try RecordingReader(url: url)
            self.reader = reader
            fileURL = url
            position = .zero
            engine.load(reader)
            remember(url)
        } catch {
            reader = nil
            fileURL = nil
            lastError = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func remember(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        if recentURLs.count > 8 { recentURLs.removeLast(recentURLs.count - 8) }
        let bookmarks = recentURLs.compactMap { try? $0.bookmarkData(options: .withSecurityScope) }
        UserDefaults.standard.set(bookmarks, forKey: Self.recentKey)
    }

    private func loadRecents() {
        guard let bookmarks = UserDefaults.standard.array(forKey: Self.recentKey) as? [Data] else { return }
        recentURLs = bookmarks.compactMap { data in
            var stale = false
            return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
        }
    }

    // MARK: - Transport

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard reader != nil, !isPlaying else { return }
        isPlaying = true
        engine.resume(from: position)
        task = Task.detached(priority: .userInitiated) { [engine] in
            await engine.run()
        }
        Task { [weak self] in
            _ = await self?.task?.value
            await MainActor.run { [weak self] in
                guard let self, isPlaying, !engine.isRunning else { return }
                // Reached the end without looping.
                isPlaying = false
                position = duration
            }
        }
    }

    func pause() {
        guard isPlaying else { return }
        engine.pause()
        task?.cancel()
        task = nil
        isPlaying = false
        position = engine.position
    }

    func stop() {
        pause()
        position = .zero
        engine.seek(to: .zero)
    }

    func seek(to time: Duration) {
        let clamped = max(.zero, min(time, duration))
        position = clamped
        engine.seek(to: clamped)
    }

    func refreshPosition() {
        sentCount = engine.sentCount
        guard isPlaying else { return }
        position = engine.position
        if !engine.isRunning {
            isPlaying = false
            task = nil
        }
    }
}

/// The off-main-actor timing loop. All state is lock-protected so the main
/// actor can seek, change speed or pause while the loop sleeps.
final class PlaybackEngine: Sendable {
    private struct State {
        var records: [RecordingRecord] = []
        var reader: RecordingReader?
        var cursor = 0
        var anchorInstant: ContinuousClock.Instant = .now
        var anchorTime: Duration = .zero
        var speed: Double = 1
        var looping = true
        var running = false
        var primeIndex: Int?
        var position: Duration = .zero
        var sentCount: UInt64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let sender = UDPDatagramSender()

    var position: Duration { state.withLock { $0.position } }
    var isRunning: Bool { state.withLock { $0.running } }
    var sentCount: UInt64 { state.withLock { $0.sentCount } }

    func load(_ reader: RecordingReader) {
        state.withLock { s in
            s.reader = reader
            s.records = reader.records
            s.cursor = 0
            s.position = .zero
            s.sentCount = 0
            s.primeIndex = nil
        }
    }

    func setDestination(host: String, port: UInt16) {
        sender.setDestination(host: host, port: port)
    }

    func setSpeed(_ speed: Double) {
        state.withLock { s in
            s.anchorTime = s.position
            s.anchorInstant = .now
            s.speed = max(0.01, speed)
        }
    }

    func setLooping(_ looping: Bool) {
        state.withLock { $0.looping = looping }
    }

    func resume(from time: Duration) {
        state.withLock { s in
            s.cursor = s.reader?.index(atOrAfter: time) ?? 0
            s.position = time
            s.anchorTime = time
            s.anchorInstant = .now
            s.running = true
        }
    }

    func pause() {
        state.withLock { $0.running = false }
    }

    func seek(to time: Duration) {
        state.withLock { s in
            s.cursor = s.reader?.index(atOrAfter: time) ?? 0
            s.position = time
            s.anchorTime = time
            s.anchorInstant = .now
            // Re-send the most recent camera info so the receiver knows the frame size.
            s.primeIndex = s.reader?.lastIndex(of: "/camerainfo", before: s.cursor)
        }
    }

    /// Runs until paused or, when not looping, past the last record.
    func run() async {
        let clock = ContinuousClock()
        while true {
            let step: (datagram: Data?, sleepUntil: ContinuousClock.Instant?, finished: Bool) = state.withLock { s in
                guard s.running else { return (nil, nil, true) }
                if let prime = s.primeIndex {
                    s.primeIndex = nil
                    return (s.records[prime].datagram, nil, false)
                }
                if s.cursor >= s.records.count {
                    guard s.looping, !s.records.isEmpty else {
                        s.running = false
                        return (nil, nil, true)
                    }
                    s.cursor = 0
                    s.anchorTime = .zero
                    s.anchorInstant = .now
                    s.position = .zero
                }
                let record = s.records[s.cursor]
                let elapsed = record.time - s.anchorTime
                let due = s.anchorInstant + elapsed / s.speed
                let now = clock.now
                if due > now {
                    s.position = s.anchorTime + (now - s.anchorInstant) * s.speed
                    return (nil, min(due, now + .milliseconds(50)), false)
                }
                s.cursor += 1
                s.position = record.time
                s.sentCount += 1
                return (record.datagram, nil, false)
            }
            if step.finished { return }
            if let datagram = step.datagram {
                sender.send(datagram)
            } else if let until = step.sleepUntil {
                try? await clock.sleep(until: until)
                if Task.isCancelled { pause(); return }
            }
        }
    }
}
