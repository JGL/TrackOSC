//
//  PresenceTracker.swift
//  TrackOSC (ReceiverCore)
//
//  Turns per-frame detection counts into debounced appear / leave / count
//  events, so a flickering detector does not produce a flickering
//  narration. A count must hold for `appearDelay` to be believed upward
//  and `leaveDelay` downward; a kind whose frames stop arriving (detector
//  switched off, sender gone) counts as zero after the stale interval.
//

import Foundation

struct PresenceEvent: Equatable, Sendable {
    enum Change: Equatable, Sendable {
        case appeared
        case left
        case countChanged
    }

    var kind: FrameKind
    var change: Change
    var count: Int
    var previousCount: Int
}

struct PresenceTracker: Sendable {
    var appearDelay: Duration = .milliseconds(400)
    var leaveDelay: Duration = .milliseconds(800)
    /// Frames older than this count as "no frame".
    var staleInterval: Duration = .milliseconds(500)

    private struct KindState {
        var confirmed = 0
        var candidate = 0
        var candidateSince: ContinuousClock.Instant?
        var lastFrame: ContinuousClock.Instant?
    }

    private var states: [FrameKind: KindState] = [:]

    /// The count believed right now for a kind.
    func count(of kind: FrameKind) -> Int {
        states[kind]?.confirmed ?? 0
    }

    /// Feed one frame's detection count.
    mutating func observe(kind: FrameKind, count: Int, at now: ContinuousClock.Instant) -> [PresenceEvent] {
        var state = states[kind] ?? KindState()
        state.lastFrame = now
        let events = update(&state, kind: kind, candidate: count, now: now)
        states[kind] = state
        return events
    }

    /// Call regularly (at display rate is fine) so kinds that went quiet
    /// are released even though no frame arrives to say so.
    mutating func tick(at now: ContinuousClock.Instant) -> [PresenceEvent] {
        var events: [PresenceEvent] = []
        for kind in FrameKind.allCases where states[kind] != nil {
            guard var state = states[kind], let last = state.lastFrame, now - last > staleInterval else { continue }
            events += update(&state, kind: kind, candidate: 0, now: now)
            states[kind] = state
        }
        return events
    }

    private func update(_ state: inout KindState, kind: FrameKind, candidate: Int, now: ContinuousClock.Instant) -> [PresenceEvent] {
        if candidate == state.confirmed {
            state.candidate = candidate
            state.candidateSince = nil
            return []
        }
        if candidate != state.candidate || state.candidateSince == nil {
            state.candidate = candidate
            state.candidateSince = now
            return []
        }
        let needed = candidate > state.confirmed ? appearDelay : leaveDelay
        guard let since = state.candidateSince, now - since >= needed else { return [] }
        let previous = state.confirmed
        state.confirmed = candidate
        state.candidateSince = nil
        let change: PresenceEvent.Change = previous == 0 ? .appeared : (candidate == 0 ? .left : .countChanged)
        return [PresenceEvent(kind: kind, change: change, count: candidate, previousCount: previous)]
    }
}
