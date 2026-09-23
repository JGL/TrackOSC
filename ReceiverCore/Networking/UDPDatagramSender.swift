//
//  UDPDatagramSender.swift
//  TrackOSC (ReceiverCore)
//
//  Sends raw datagrams (already-encoded OSC) to a host:port – used by
//  forwarding and by playback, where the bytes must go out exactly as they
//  came in. Errors are counted, never thrown: dropping a frame is fine,
//  stalling the receive path is not.
//

import Darwin
import Foundation
import os.lock

final class UDPDatagramSender: Sendable {
    private struct State {
        var fd: Int32 = -1
        var host = ""
        var port: UInt16 = 0
        var resolved: sockaddr_in?
        var sentCount: UInt64 = 0
        var errorCount: UInt64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var counters: (sent: UInt64, errors: UInt64) {
        state.withLock { ($0.sentCount, $0.errorCount) }
    }

    var destination: (host: String, port: UInt16) {
        state.withLock { ($0.host, $0.port) }
    }

    /// Resolves the host once (IPv4, like the senders) and remembers it.
    func setDestination(host: String, port: UInt16) {
        let resolved = Self.resolve(host: host, port: port)
        state.withLock { s in
            s.host = host
            s.port = port
            s.resolved = resolved
            if s.fd < 0 {
                s.fd = socket(AF_INET, SOCK_DGRAM, 0)
                var nosigpipe: Int32 = 1
                setsockopt(s.fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
            }
        }
    }

    func send(_ datagram: Data) {
        let (fd, target) = state.withLock { ($0.fd, $0.resolved) }
        guard fd >= 0, var target else {
            state.withLock { $0.errorCount += 1 }
            return
        }
        let sent = datagram.withUnsafeBytes { raw -> Int in
            withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        state.withLock { s in
            if sent == datagram.count { s.sentCount += 1 } else { s.errorCount += 1 }
        }
    }

    func close() {
        state.withLock { s in
            if s.fd >= 0 { Darwin.close(s.fd) }
            s.fd = -1
        }
    }

    deinit {
        close()
    }

    private static func resolve(host: String, port: UInt16) -> sockaddr_in? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(result) }
        guard let address = first.pointee.ai_addr, first.pointee.ai_addrlen >= MemoryLayout<sockaddr_in>.size else { return nil }
        return address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
    }
}
