//
//  ReceiverModel.swift
//  TrackOSC (ReceiverCore)
//
//  UI-facing state shared by every receiver-type app. The listener can
//  deliver hundreds of messages per second, so ReceiverService accumulates
//  off the main thread and this model is refreshed at display rate (30 Hz)
//  to keep SwiftUI invalidation cheap. Each app wraps one of these in its
//  own store for app-specific state.
//

import Foundation
import Observation
import PoseioscShared

@Observable @MainActor
final class ReceiverModel {
    let app: TrackOSCApp
    let settings = ReceiverSettings()
    let presentation = PresentationController()
    let bonjour = BonjourBrowser()
    let forwarder = DatagramForwarder()

    /// Most recent frame per message kind; the visualiser draws these.
    var latest: [FrameKind: TimestampedFrame] = [:]
    /// Messages per second per kind, over a 1-second sliding window.
    var rates: [FrameKind: Double] = [:]
    /// Recent messages, newest first. Capped.
    var log: [LogEntry] = []
    var isLogPaused = false

    /// The port actually bound (the default, the user's, or the one fallen forward to).
    private(set) var effectivePort: UInt16 = TrackOSCApp.defaultPort
    private(set) var isListening = false
    /// Explains a fall-forward from the default port; nil when on the requested port.
    private(set) var portNote: String?
    var lastError: String?
    private(set) var advertisedName: String?

    /// Total messages received since launch.
    var totalMessages: UInt64 = 0
    /// Messages the codec rejected since launch (unknown address, malformed).
    var unknownMessages: UInt64 = 0

    /// Latest /camerainfo from the sender (nil until one arrives or when stale).
    var cameraInfo: CameraInfo?

    let service = ReceiverService()
    private var refreshTask: Task<Void, Never>?

    static let logCap = 300
    /// A frame older than this is considered stale and no longer drawn.
    static let staleInterval: TimeInterval = 0.5

    init(app: TrackOSCApp) {
        self.app = app
        presentation.cursorHideDelay = settings.cursorHideDelay
        presentation.alwaysOnTop = settings.alwaysOnTop
        service.addTap(forwarder)
        start()
    }

    /// Binds the requested port, or falls forward from the default when it is
    /// taken, then advertises on whatever was bound and starts the UI refresh.
    func start() {
        lastError = nil
        portNote = nil

        let requested = settings.customPort ?? TrackOSCApp.defaultPort
        let candidates = settings.customPort == nil ? [requested] + TrackOSCApp.fallbackPorts : [requested]
        var bound: UInt16?
        for port in candidates {
            do {
                try service.start(port: port)
                bound = port
                break
            } catch let error as UDPDatagramServer.ServerError where error.isPortInUse {
                continue
            } catch {
                lastError = "Could not listen on port \(port): \(error.localizedDescription)"
                break
            }
        }

        if let bound {
            isListening = true
            effectivePort = bound
            if bound != requested {
                portNote = "Port \(requested) is in use – listening on \(bound). Point a sender here, or enable Forward to 127.0.0.1:\(bound) in the app that has \(requested)."
            }
        } else {
            isListening = false
            effectivePort = requested
            if lastError == nil {
                lastError = candidates.count == 1
                    ? "Could not listen on port \(requested): it is already in use"
                    : "Ports \(candidates.first!)–\(candidates.last!) are all in use"
            }
        }

        // The loop guard depends on the port actually bound, so re-evaluate now.
        applyForwarding()

        do {
            let name = app.bonjourName(host: Host.current().localizedName ?? "Mac")
            advertisedName = try service.advertise(name: name, port: effectivePort)
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

    /// Restart on an explicit port. Choosing the default port again clears
    /// the explicit setting so fall-forward applies on the next launch.
    func restart(port: UInt16) {
        settings.customPort = port == TrackOSCApp.defaultPort ? nil : port
        restart()
    }

    func restart() {
        service.stop()
        latest = [:]
        rates = [:]
        start()
    }

    func applyForwarding() {
        var enabled = settings.forwardEnabled
        // Loop guard: never forward to our own port on a local address.
        let loops = settings.forwardPort == effectivePort && Self.isLocal(host: settings.forwardHost)
        if loops {
            enabled = false
            if settings.forwardEnabled {
                lastError = Self.loopMessage(port: effectivePort)
            }
        } else if lastError?.hasPrefix(Self.loopMessagePrefix) == true {
            lastError = nil
        }
        forwarder.configure(host: settings.forwardHost, port: settings.forwardPort, enabled: enabled)
    }

    /// The fresh frame of a kind, or nil when none has arrived recently.
    func fresh(_ kind: FrameKind, at now: Date = .now) -> DecodedFrame? {
        guard let frame = latest[kind], now.timeIntervalSince(frame.receivedAt) < Self.staleInterval else { return nil }
        return frame.decoded
    }

    /// Every kind whose latest frame is fresh.
    func freshFrames(at now: Date = .now) -> [FrameKind: TimestampedFrame] {
        latest.filter { now.timeIntervalSince($0.value.receivedAt) < Self.staleInterval }
    }

    private static let loopMessagePrefix = "Forwarding to this app's own port"
    private static func loopMessage(port: UInt16) -> String {
        "\(loopMessagePrefix) \(port) would loop; forwarding is off."
    }

    private static func isLocal(host: String) -> Bool {
        let h = host.lowercased()
        return h == "127.0.0.1" || h == "localhost" || h == "::1" || h == "0.0.0.0" || h == (Host.current().localizedName ?? "").lowercased()
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
