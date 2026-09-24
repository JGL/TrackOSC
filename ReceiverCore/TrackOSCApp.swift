//
//  TrackOSCApp.swift
//  TrackOSC (ReceiverCore)
//
//  The registry of receiver-type apps built on ReceiverCore: display names,
//  Bonjour names and accent colours. Every app listens on the same default
//  port as the senders target, so each works out of the box; when the port
//  is already owned by another TrackOSC app the newcomer falls forward to
//  the next free one (see ReceiverModel).
//

import SwiftUI

enum TrackOSCApp: String, CaseIterable, Sendable {
    case receiver
    case speaker
    case recorder
    case router
    case colours

    /// The port every sender targets by default (VisionOSC's).
    static let defaultPort: UInt16 = 9527
    /// Ports tried, in order, when the default is already taken.
    static let fallbackPorts: [UInt16] = Array(9528...9536)

    var displayName: String {
        switch self {
        case .receiver: "TrackOSC Receiver"
        case .speaker: "TrackOSC Speaker"
        case .recorder: "TrackOSC Recorder"
        case .router: "TrackOSC Router"
        case .colours: "TrackOSC Colours"
        }
    }

    /// One-line purpose, shown in the connection popover and About text.
    var summary: String {
        switch self {
        case .receiver: "Draws the tracking stream in 2D and 3D."
        case .speaker: "Reads the tracking stream aloud."
        case .recorder: "Records the tracking stream and plays it back."
        case .router: "Turns tracking events into MIDI, Shortcuts, key presses and HTTP."
        case .colours: "Gradients, colour fields and patterns driven by the tracking stream."
        }
    }

    var accent: Color {
        switch self {
        case .receiver: .blue
        case .speaker: .orange
        case .recorder: .red
        case .router: .teal
        case .colours: .purple
        }
    }

    /// The Bonjour service name senders see in their Discovered receivers list.
    func bonjourName(host: String) -> String {
        "\(displayName) (\(host))"
    }
}
