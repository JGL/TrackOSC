//
//  BonjourAdvertiser.swift
//  Poseiosc Receiver (macOS)
//
//  Registers an "_osc._udp" Bonjour service via the dnssd C API.
//  mDNS registration is just a name/type/port record – it does not need to own
//  the UDP socket, so it coexists with SwiftOSC's server binding the port.
//  (NetService could do the same but has been deprecated since macOS 10.15.)
//

import Foundation
import dnssd

final class BonjourAdvertiser: @unchecked Sendable {
    private var serviceRef: DNSServiceRef?
    private let queue = DispatchQueue(label: "poseiosc.bonjour")
    private let lock = NSLock()

    enum AdvertiseError: Error, LocalizedError {
        case registrationFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .registrationFailed(let code): "DNSServiceRegister failed (\(code))"
            }
        }
    }

    func start(name: String, port: UInt16) throws {
        lock.lock()
        defer { lock.unlock() }

        stopLocked()

        var ref: DNSServiceRef?
        let error = DNSServiceRegister(
            &ref,
            0,                          // flags
            0,                          // all interfaces
            name,
            "_osc._udp",
            nil,                        // default domain
            nil,                        // default host
            port.bigEndian,             // port in network byte order
            0, nil,                     // no TXT record
            nil, nil                    // no callback needed
        )
        guard error == kDNSServiceErr_NoError, let ref else {
            throw AdvertiseError.registrationFailed(error)
        }
        DNSServiceSetDispatchQueue(ref, queue)
        serviceRef = ref
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        if let ref = serviceRef {
            DNSServiceRefDeallocate(ref)
            serviceRef = nil
        }
    }

    deinit {
        stop()
    }
}
