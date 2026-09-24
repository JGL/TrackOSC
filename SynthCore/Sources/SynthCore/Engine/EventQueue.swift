//
//  EventQueue.swift
//  SynthCore
//
//  A single-producer single-consumer ring of events from the UI/mapping
//  side to the audio thread: no locks, no allocation on either side.
//

import Foundation
import Synchronization

public enum SynthEvent: Sendable, Equatable {
    case bassNoteOn(note: Int, accent: Bool, slide: Bool)
    case bassNoteOff
    case drum(DrumVoiceKind, velocity: Float)
    case play
    case stop
    case advanceStep
    case selectPattern(Int)
    case toggleDrumStep(DrumVoiceKind, Int)
    case setBassStep(Int, BassStep)
    case setConductor(Bool)
    case setPattern(Int, StepPattern)
}

public final class EventQueue: @unchecked Sendable {
    private let capacity: Int
    private var slots: [SynthEvent?]
    private let head = Atomic<Int>(0)   // consumer reads here
    private let tail = Atomic<Int>(0)   // producer writes here

    public init(capacity: Int = 1024) {
        self.capacity = capacity
        slots = Array(repeating: nil, count: capacity)
    }

    /// Producer side. Returns false when the ring is full (the event is dropped).
    @discardableResult
    public func push(_ event: SynthEvent) -> Bool {
        let t = tail.load(ordering: .relaxed)
        let next = (t + 1) % capacity
        if next == head.load(ordering: .acquiring) { return false }
        slots[t] = event
        tail.store(next, ordering: .releasing)
        return true
    }

    /// Consumer side (audio thread).
    @inline(__always)
    public func pop() -> SynthEvent? {
        let h = head.load(ordering: .relaxed)
        if h == tail.load(ordering: .acquiring) { return nil }
        let event = slots[h]
        slots[h] = nil
        head.store((h + 1) % capacity, ordering: .releasing)
        return event
    }
}
