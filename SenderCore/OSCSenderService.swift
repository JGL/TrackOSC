//
//  OSCSenderService.swift
//  Poseiosc Sender (iOS)
//
//  Thread-safe wrapper around the SwiftOSC UDP client. Send errors are counted,
//  not thrown – dropping a frame of tracking data is fine, blocking the Vision
//  pipeline is not.
//

import Foundation
import SwiftOSC
import os.lock

final class OSCSenderService: Sendable {
    private struct State {
        var host: String = "127.0.0.1"
        var port: UInt16 = 9527
        var isStarted = false
        var sentCount: UInt64 = 0
        var errorCount: UInt64 = 0
    }

    private let client = OSCUDPClient()
    private let state = OSAllocatedUnfairLock(initialState: State())

    var destination: (host: String, port: UInt16) {
        state.withLock { ($0.host, $0.port) }
    }

    var counters: (sent: UInt64, errors: UInt64) {
        state.withLock { ($0.sentCount, $0.errorCount) }
    }

    func setDestination(host: String, port: UInt16) {
        state.withLock {
            $0.host = host
            $0.port = port
        }
    }

    func start() {
        state.withLock { s in
            guard !s.isStarted else { return }
            do {
                try client.start()
                s.isStarted = true
            } catch {
                s.errorCount += 1
            }
        }
    }

    func send(_ message: OSCMessage) {
        let (host, port, started) = state.withLock { ($0.host, $0.port, $0.isStarted) }
        guard started, !host.isEmpty else { return }
        do {
            try client.send(message, to: host, port: port)
            state.withLock { $0.sentCount += 1 }
        } catch {
            state.withLock { $0.errorCount += 1 }
        }
    }
}
