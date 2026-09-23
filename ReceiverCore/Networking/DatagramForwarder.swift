//
//  DatagramForwarder.swift
//  TrackOSC (ReceiverCore)
//
//  Taps see every datagram the receiver gets, before decoding, on the
//  receive queue: they must be quick and must never block. The forwarder is
//  the tap that lets TrackOSC apps chain on one Mac – sender → Receiver
//  (9527) → Speaker (9528) → … – by re-sending each datagram unchanged.
//

import Foundation
import os.lock

/// Something that wants every raw datagram (forwarding, recording).
protocol DatagramTap: AnyObject, Sendable {
    func receive(_ datagram: Data, from host: String, at instant: ContinuousClock.Instant)
}

final class DatagramForwarder: DatagramTap, Sendable {
    private let sender = UDPDatagramSender()
    private let enabled = OSAllocatedUnfairLock(initialState: false)

    var isEnabled: Bool { enabled.withLock { $0 } }
    var counters: (sent: UInt64, errors: UInt64) { sender.counters }
    var destination: (host: String, port: UInt16) { sender.destination }

    func configure(host: String, port: UInt16, enabled: Bool) {
        sender.setDestination(host: host, port: port)
        self.enabled.withLock { $0 = enabled && !host.isEmpty && port > 0 }
    }

    func receive(_ datagram: Data, from host: String, at instant: ContinuousClock.Instant) {
        guard isEnabled else { return }
        sender.send(datagram)
    }
}
