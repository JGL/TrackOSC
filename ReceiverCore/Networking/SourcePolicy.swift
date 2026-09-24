//
//  SourcePolicy.swift
//  TrackOSC (ReceiverCore)
//
//  Which sender an app listens to when several are sending to the same
//  port – for instance an iPhone and the Recorder playing a file back.
//

import Foundation

enum SourcePolicy: String, CaseIterable, Identifiable, Sendable {
    /// Every datagram from every host is processed (they interleave).
    case all
    /// The host that most recently *started* sending owns the stream; other
    /// hosts are ignored until it goes quiet or another host starts afresh.
    case latestWins
    /// Only the chosen host.
    case only

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All senders (mixed)"
        case .latestWins: "Latest sender wins"
        case .only: "Only one host"
        }
    }

    var explanation: String {
        switch self {
        case .all: "Messages from every sender are processed as they arrive."
        case .latestWins: "Whichever host starts sending takes over; playing a recording into this app silences a live sender until playback stops for a second."
        case .only: "Only the chosen host is heard; everything else is counted as ignored."
        }
    }
}

/// Decides, datagram by datagram, whether a host is heard. Kept off the
/// main actor: it runs on the receive queue.
struct SourceSelector: Sendable {
    var policy: SourcePolicy = .latestWins
    var onlyHost = ""
    /// A host that has been silent this long has stopped; the next packet
    /// from it starts a new stream.
    var silenceGap: Duration = .seconds(1)

    private(set) var activeHost: String?
    private var activeLastSeen: ContinuousClock.Instant?
    private var lastSeen: [String: ContinuousClock.Instant] = [:]

    /// Hosts heard from in the last minute, most recent first.
    func recentHosts(at now: ContinuousClock.Instant) -> [String] {
        lastSeen.filter { now - $0.value < .seconds(60) }
            .sorted { $0.value > $1.value }
            .map(\.key)
    }

    mutating func accepts(host: String, at now: ContinuousClock.Instant) -> Bool {
        let previous = lastSeen[host]
        lastSeen[host] = now
        if lastSeen.count > 64 {
            lastSeen = lastSeen.filter { now - $0.value < .seconds(60) }
        }
        switch policy {
        case .all:
            activeHost = host
            activeLastSeen = now
            return true
        case .only:
            let match = host == onlyHost
            if match { activeHost = host; activeLastSeen = now }
            return match
        case .latestWins:
            if activeHost == nil || activeHost == host {
                activeHost = host
                activeLastSeen = now
                return true
            }
            let activeQuiet = activeLastSeen.map { now - $0 > silenceGap } ?? true
            let startsAfresh = previous.map { now - $0 > silenceGap } ?? true
            if activeQuiet || startsAfresh {
                activeHost = host
                activeLastSeen = now
                return true
            }
            return false
        }
    }
}
