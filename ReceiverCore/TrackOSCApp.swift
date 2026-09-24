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
    case particles
    case text
    case synth
    case costumes

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
        case .particles: "TrackOSC Particles"
        case .text: "TrackOSC Text"
        case .synth: "TrackOSC Synth"
        case .costumes: "TrackOSC Costumes"
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
        case .particles: "Physics particles, trails and ghosts driven by the tracking stream."
        case .text: "Kinetic typography driven by the tracking stream."
        case .synth: "A 303-and-808-flavoured synth and drum machine played by the tracking stream."
        case .costumes: "Dresses tracked bodies, faces and hands in SVG costumes."
        }
    }

    var accent: Color {
        switch self {
        case .receiver: .blue
        case .speaker: .orange
        case .recorder: .red
        case .router: .teal
        case .colours: .purple
        case .particles: .pink
        case .text: .gray
        case .synth: .indigo
        case .costumes: .yellow
        }
    }

    /// The Bonjour service name senders see in their Discovered receivers list.
    func bonjourName(host: String) -> String {
        "\(displayName) (\(host))"
    }
}
