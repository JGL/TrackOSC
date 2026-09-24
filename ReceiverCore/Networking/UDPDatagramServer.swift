//
//  UDPDatagramServer.swift
//  TrackOSC (ReceiverCore)
//
//  A minimal IPv4 UDP listener that hands every datagram over as raw bytes.
//  It replaces SwiftOSC's server on the receiving side because the raw bytes
//  are what forwarding (chaining apps) and recording need, and because an
//  undecodable datagram should be counted rather than silently dropped.
//  Decoding still happens with SwiftOSC, one step later.
//
//  A BSD socket read by a DispatchSource: no NIO event loop, synchronous bind
//  errors (a port in use is reported the moment `start` is called), and it
//  works under the App Sandbox with the network.server entitlement.
//

import Darwin
import Foundation

final class UDPDatagramServer: @unchecked Sendable {
    typealias Handler = @Sendable (_ datagram: Data, _ host: String, _ instant: ContinuousClock.Instant) -> Void

    enum ServerError: Error, LocalizedError {
        case portInUse(UInt16)
        case socketFailed(errno: Int32, while: String)

        var errorDescription: String? {
            switch self {
            case .portInUse(let port):
                "UDP port \(port) is already in use"
            case .socketFailed(let code, let stage):
                "\(stage) failed: \(String(cString: strerror(code))) (\(code))"
            }
        }

        var isPortInUse: Bool {
            if case .portInUse = self { return true }
            return false
        }
    }

    let port: UInt16
    private let handler: Handler
    private let queue = DispatchQueue(label: "trackosc.udp.receive", qos: .userInteractive)
    private var source: DispatchSourceRead?
    private var fd: Int32 = -1
    private let lock = NSLock()

    /// Largest datagram accepted (UDP's own limit; /faces/arr with 32 faces is ~37 KB).
    private static let maximumDatagram = 65_536

    /// Binds immediately; throws `ServerError.portInUse` when another process owns the port.
    init(port: UInt16, handler: @escaping Handler) throws {
        self.port = port
        self.handler = handler

        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw ServerError.socketFailed(errno: errno, while: "socket") }

        // Deliberately NOT SO_REUSEPORT: a second listener must fail so the
        // app can fall forward to another port rather than silently share
        // (and split) the stream with the app that already owns this one.
        var receiveBuffer: Int32 = 4 * 1024 * 1024
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &receiveBuffer, socklen_t(MemoryLayout<Int32>.size))
        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw code == EADDRINUSE ? ServerError.portInUse(port) : ServerError.socketFailed(errno: code, while: "bind")
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        self.fd = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        source?.cancel()   // the cancel handler closes the descriptor
        source = nil
        fd = -1
    }

    deinit {
        stop()
    }

    /// Reads every datagram currently queued on the socket.
    private func drain() {
        let fd = lock.withLock { self.fd }
        guard fd >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: Self.maximumDatagram)
        var sender = sockaddr_in()
        var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)

        while true {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                withUnsafeMutablePointer(to: &sender) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        recvfrom(fd, raw.baseAddress, raw.count, 0, sa, &senderLength)
                    }
                }
            }
            if count < 0 {
                return   // EWOULDBLOCK: the queue is empty (any other error also ends this pass)
            }
            let instant = ContinuousClock.now
            var addressText = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var addressCopy = sender.sin_addr
            inet_ntop(AF_INET, &addressCopy, &addressText, socklen_t(INET_ADDRSTRLEN))
            let hostBytes = addressText.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let host = String(decoding: hostBytes, as: UTF8.self)
            handler(Data(buffer[0..<count]), host, instant)
        }
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
