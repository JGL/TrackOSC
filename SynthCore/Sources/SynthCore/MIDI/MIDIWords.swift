//
//  MIDIWords.swift
//  SynthCore
//
//  Universal MIDI Packet words for MIDI 1.0 channel voice messages, the
//  pure part of MIDI out (tested); the CoreMIDI plumbing lives in the app.
//

import Foundation

public enum MIDIWords {
    /// Message type 2 (MIDI 1.0 channel voice), group 0.
    static func word(status: UInt32, channel: Int, data1: Int, data2: Int) -> UInt32 {
        let ch = UInt32(min(max(channel - 1, 0), 15))
        let d1 = UInt32(min(max(data1, 0), 127))
        let d2 = UInt32(min(max(data2, 0), 127))
        return (0x2 << 28) | ((status | ch) << 16) | (d1 << 8) | d2
    }

    public static func noteOn(channel: Int, note: Int, velocity: Int) -> UInt32 { word(status: 0x90, channel: channel, data1: note, data2: velocity) }
    public static func noteOff(channel: Int, note: Int) -> UInt32 { word(status: 0x80, channel: channel, data1: note, data2: 0) }
    public static func controlChange(channel: Int, controller: Int, value: Int) -> UInt32 { word(status: 0xB0, channel: channel, data1: controller, data2: value) }
    /// System real-time: clock 0xF8, start 0xFA, stop 0xFC (message type 1).
    public static func realtime(_ status: UInt32) -> UInt32 { (0x1 << 28) | (status << 16) }
    public static let clock = realtime(0xF8)
    public static let start = realtime(0xFA)
    public static let stop = realtime(0xFC)

    /// Drum voices on the General MIDI percussion notes.
    public static func gmNote(for kind: DrumVoiceKind) -> Int {
        switch kind {
        case .kick: 36; case .snare: 38; case .closedHat: 42; case .openHat: 46
        case .lowTom: 45; case .highTom: 50; case .clap: 39; case .cowbell: 56
        }
    }
}
