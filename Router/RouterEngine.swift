//
//  RouterEngine.swift
//  TrackOSC Router (macOS)
//
//  Evaluates every enabled rule at display rate against the latest frames
//  and runs its action through the ActionRunner. Per-rule state gives
//  edges, hysteresis, cooldowns and rate limits; nothing here can flood.
//

import Foundation
import Observation
import PoseioscShared

struct ActivityEntry: Identifiable, Sendable {
    let id = UUID()
    var time: Date
    var ruleID: UUID?
    var ruleName: String
    var detail: String
    var isError = false
}

@Observable @MainActor
final class RouterEngine {
    var rules: [Rule] = [] {
        didSet { ruleIDs = Set(rules.map(\.id)); states = states.filter { ruleIDs.contains($0.key) } }
    }
    /// Log actions without performing them.
    var dryRun = false
    private(set) var feed: [ActivityEntry] = []
    /// When each rule last fired, for the LEDs.
    private(set) var lastFired: [UUID: Date] = [:]
    /// Live readings of every source in use, for the editor.
    private(set) var readings: [ValueSource: SourceValue] = [:]
    private(set) var firedCount = 0

    let actions = ActionRunner()
    static let feedCap = 300
    static let midiPerSecondCap = 200

    private struct RuleState {
        var lastBool: Bool?
        var lastFire: Date?
        var lastContinuous: Date?
        var lastMapped: Double?
        var lastText: String?
    }

    private var states: [UUID: RuleState] = [:]
    private var ruleIDs: Set<UUID> = []
    private var presence = PresenceTracker()
    private var midiWindow: [Date] = []

    /// Called at display rate with the model's latest frames.
    func tick(latest: [FrameKind: TimestampedFrame], now: Date = .now, instant: ContinuousClock.Instant = .now) {
        // Presence edges.
        for kind in FrameKind.allCases {
            if let frame = latest[kind], now.timeIntervalSince(frame.receivedAt) < ReceiverModel.staleInterval {
                for event in presence.observe(kind: kind, count: frame.decoded.detectionCount, at: instant) {
                    firePresence(event, now: now)
                }
            }
        }
        for event in presence.tick(at: instant) {
            firePresence(event, now: now)
        }

        // Value-based rules.
        var newReadings: [ValueSource: SourceValue] = [:]
        for rule in rules where rule.isEnabled {
            guard let source = rule.trigger.source else { continue }
            let value = newReadings[source] ?? SourceReader.read(source, latest: latest, now: now, staleInterval: ReceiverModel.staleInterval)
            newReadings[source] = value
            evaluate(rule, value: value, now: now)
        }
        readings = newReadings
    }

    /// Read any source on demand (for the editor's live readout).
    func read(_ source: ValueSource, latest: [FrameKind: TimestampedFrame]) -> SourceValue {
        SourceReader.read(source, latest: latest, now: .now, staleInterval: ReceiverModel.staleInterval)
    }

    /// Run a rule's action once with a representative value.
    func test(_ rule: Rule) {
        var value: Double? = nil
        if case .continuous(_, _, _, let outMin, let outMax, _) = rule.trigger { value = (outMin + outMax) / 2 }
        run(Firing(rule: rule, value: value, text: "test"), note: "test")
    }

    // MARK: - Evaluation

    private func firePresence(_ event: PresenceEvent, now: Date) {
        for rule in rules where rule.isEnabled {
            guard case .presence(let kind, let edge) = rule.trigger, kind == event.kind else { continue }
            let matches: Bool = switch edge {
            case .appear: event.change == .appeared
            case .leave: event.change == .left
            case .change: true
            }
            if matches {
                run(Firing(rule: rule, value: Double(event.count), text: nil, time: now), note: "\(kind.address) \(event.change)")
            }
        }
    }

    private func evaluate(_ rule: Rule, value: SourceValue, now: Date) {
        var state = states[rule.id] ?? RuleState()
        defer { states[rule.id] = state }

        switch rule.trigger {
        case .presence:
            return

        case .threshold(_, let threshold, let direction, let hysteresis):
            guard let v = value.number else { return }
            let above = state.lastBool ?? (v > threshold)
            let nowAbove: Bool
            if above {
                nowAbove = v > threshold - hysteresis
            } else {
                nowAbove = v > threshold
            }
            if state.lastBool == nil {
                state.lastBool = v > threshold
                return
            }
            if nowAbove != above {
                state.lastBool = nowAbove
                let crossed = direction == .rise ? nowAbove : !nowAbove
                if crossed {
                    run(Firing(rule: rule, value: v, text: nil, time: now), note: "value \(value.display)")
                }
            }

        case .range(_, let low, let high, let edge):
            guard let v = value.number else { return }
            let inside = v >= low && v <= high
            if let last = state.lastBool, last != inside {
                let fires = edge == .enter ? inside : !inside
                if fires {
                    run(Firing(rule: rule, value: v, text: nil, time: now), note: "value \(value.display)")
                }
            }
            state.lastBool = inside

        case .continuous(_, let inMin, let inMax, let outMin, let outMax, let rateHz):
            guard let v = value.number else { return }
            let interval = 1 / max(1, rateHz)
            if let last = state.lastContinuous, now.timeIntervalSince(last) < interval { return }
            let t = inMax == inMin ? 0 : min(max((v - inMin) / (inMax - inMin), 0), 1)
            let mapped = outMin + t * (outMax - outMin)
            // Send when changed, or once a second regardless so late listeners catch up.
            if let lastMapped = state.lastMapped, abs(lastMapped - mapped) < 0.0005,
               let lastFire = state.lastFire, now.timeIntervalSince(lastFire) < 1 { return }
            state.lastContinuous = now
            state.lastMapped = mapped
            state.lastFire = now
            run(Firing(rule: rule, value: mapped, text: nil, time: now), note: "\(value.display) → \(String(format: "%.2f", mapped))", quiet: true)

        case .stringMatch(_, let mode, let pattern, let cooldown):
            guard let text = value.text, !text.isEmpty else { state.lastText = nil; return }
            let matched: Bool = switch mode {
            case .equals: text.caseInsensitiveCompare(pattern) == .orderedSame
            case .contains: text.range(of: pattern, options: .caseInsensitive) != nil
            case .regex: (try? Regex(pattern).ignoresCase().firstMatch(in: text)) != nil
            }
            guard matched else { state.lastText = nil; return }
            if state.lastText == text, let last = state.lastFire, now.timeIntervalSince(last) < cooldown { return }
            state.lastText = text
            state.lastFire = now
            run(Firing(rule: rule, value: nil, text: text, time: now), note: "matched \(value.display)")
        }
    }

    // MARK: - Running

    private func run(_ firing: Firing, note: String, quiet: Bool = false) {
        lastFired[firing.rule.id] = firing.time
        firedCount += 1
        if case .midiNote = firing.rule.action { guard midiAllowed(now: firing.time) else { return } }
        if case .midiCC = firing.rule.action { guard midiAllowed(now: firing.time) else { return } }

        if dryRun {
            log(firing.rule, "dry run · \(note) · \(firing.rule.action.summary)")
            return
        }
        if !quiet || feed.first?.ruleID != firing.rule.id {
            log(firing.rule, "\(note) · \(firing.rule.action.summary)")
        }
        Task {
            do {
                try await actions.perform(firing)
            } catch {
                log(firing.rule, "failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func midiAllowed(now: Date) -> Bool {
        midiWindow.removeAll { now.timeIntervalSince($0) > 1 }
        guard midiWindow.count < Self.midiPerSecondCap else { return false }
        midiWindow.append(now)
        return true
    }

    func log(_ rule: Rule?, _ detail: String, isError: Bool = false) {
        feed.insert(ActivityEntry(time: .now, ruleID: rule?.id, ruleName: rule?.name ?? "Router", detail: detail, isError: isError), at: 0)
        if feed.count > Self.feedCap { feed.removeLast(feed.count - Self.feedCap) }
    }

    func clearFeed() {
        feed.removeAll()
    }
}
