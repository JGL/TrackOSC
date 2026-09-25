//
//  SynthMIDI.swift
//  TrackOSC Synth (macOS)
//
//  A virtual MIDI source called "TrackOSC Synth" (every note and CC the
//  synth plays goes out too, so a DAW can double it), plus an optional
//  destination and MIDI clock.
//

import CoreMIDI
import Foundation
import Observation
import SynthCore

@Observable @MainActor
final class SynthMIDI {
    struct Destination: Identifiable, Hashable {
        let id: MIDIUniqueID
        let name: String
    }

    private(set) var isReady = false
    private(set) var destinations: [Destination] = []
    var selectedDestination: MIDIUniqueID? {
        didSet { UserDefaults.standard.set(selectedDestination.map(Int.init) ?? 0, forKey: "midiDestination") }
    }
    var isEnabled: Bool { didSet { UserDefaults.standard.set(isEnabled, forKey: "midiEnabled") } }
    var sendsClock: Bool { didSet { UserDefaults.standard.set(sendsClock, forKey: "midiClock") } }
    var bassChannel = 1
    var drumChannel = 10
    private(set) var sentCount = 0

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var outputPort = MIDIPortRef()
    private static let sourceUniqueIDKey = "midiSourceUniqueID"

    init() {
        let stored = UserDefaults.standard.integer(forKey: "midiDestination")
        selectedDestination = stored == 0 ? nil : MIDIUniqueID(stored)
        isEnabled = UserDefaults.standard.object(forKey: "midiEnabled") as? Bool ?? true
        sendsClock = UserDefaults.standard.bool(forKey: "midiClock")
        setUp()
    }

    private func setUp() {
        var status = MIDIClientCreateWithBlock("TrackOSC Synth" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                Task { @MainActor in self?.refreshDestinations() }
            }
        }
        guard status == noErr else { return }
        status = MIDISourceCreateWithProtocol(client, "TrackOSC Synth" as CFString, ._1_0, &source)
        guard status == noErr else { return }
        let storedID = UserDefaults.standard.integer(forKey: Self.sourceUniqueIDKey)
        if storedID != 0 {
            MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, Int32(storedID))
        } else {
            var id: Int32 = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &id)
            UserDefaults.standard.set(Int(id), forKey: Self.sourceUniqueIDKey)
        }
        MIDIOutputPortCreate(client, "TrackOSC Synth Out" as CFString, &outputPort)
        isReady = true
        refreshDestinations()
    }

    func refreshDestinations() {
        var found: [Destination] = []
        for index in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(index)
            var id: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &id)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
            let label = name?.takeRetainedValue() as String? ?? "Destination \(index)"
            found.append(Destination(id: id, name: label))
        }
        destinations = found
    }

    /// Mirror what the audio graph just played.
    func send(_ trigger: GraphTrigger) {
        guard isEnabled else { return }
        switch trigger.kind {
        case .bassOn(let note, let accent):
            send(MIDIWords.noteOn(channel: bassChannel, note: note, velocity: accent ? 127 : 96))
        case .bassOff:
            // Note-off for every bass note is noisy; send an all-notes-off CC instead.
            send(MIDIWords.controlChange(channel: bassChannel, controller: 123, value: 0))
        case .drum(let kind, let velocity):
            let note = MIDIWords.gmNote(for: kind)
            send(MIDIWords.noteOn(channel: drumChannel, note: note, velocity: Int(velocity * 127)))
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(60))
                self?.send(MIDIWords.noteOff(channel: self?.drumChannel ?? 10, note: note))
            }
        }
    }

    func note(channel: Int, note: Int, velocity: Float) {
        guard isEnabled else { return }
        send(MIDIWords.noteOn(channel: channel, note: note, velocity: Int(velocity * 127)))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            self?.send(MIDIWords.noteOff(channel: channel, note: note))
        }
    }

    func controlChange(channel: Int, controller: Int, value: Int) {
        guard isEnabled else { return }
        send(MIDIWords.controlChange(channel: channel, controller: controller, value: value))
    }

    func transport(playing: Bool) {
        guard isEnabled, sendsClock else { return }
        send(playing ? MIDIWords.start : MIDIWords.stop)
    }

    func clockTick() {
        guard isEnabled, sendsClock else { return }
        send(MIDIWords.clock)
    }

    private func send(_ word: UInt32) {
        guard isReady else { return }
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        _ = withUnsafePointer(to: word) { wordPointer in
            MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 1, wordPointer)
        }
        MIDIReceivedEventList(source, &list)
        if let selectedDestination, let endpoint = Self.endpoint(for: selectedDestination) {
            MIDISendEventList(outputPort, endpoint, &list)
        }
        sentCount += 1
    }

    private static func endpoint(for uniqueID: MIDIUniqueID) -> MIDIEndpointRef? {
        var object = MIDIObjectRef()
        var type = MIDIObjectType.other
        guard MIDIObjectFindByUniqueID(uniqueID, &object, &type) == noErr, type == .destination else { return nil }
        return object
    }
}
