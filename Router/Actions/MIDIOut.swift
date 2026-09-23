//
//  MIDIOut.swift
//  TrackOSC Router (macOS)
//
//  A virtual MIDI source called "TrackOSC Router" that any DAW or app can
//  choose as an input, plus an optional hardware/other destination. MIDI
//  1.0 messages are sent as Universal MIDI Packets. The sandbox allows
//  CoreMIDI without an entitlement.
//

import CoreMIDI
import Foundation
import Observation

@Observable @MainActor
final class MIDIOut {
    struct Destination: Identifiable, Hashable {
        let id: MIDIUniqueID
        let name: String
    }

    private(set) var isReady = false
    private(set) var destinations: [Destination] = []
    var selectedDestination: MIDIUniqueID? {
        didSet { UserDefaults.standard.set(selectedDestination.map(Int.init) ?? 0, forKey: "midiDestination") }
    }
    private(set) var sentCount = 0

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var outputPort = MIDIPortRef()
    private static let sourceUniqueIDKey = "midiSourceUniqueID"

    init() {
        let stored = UserDefaults.standard.integer(forKey: "midiDestination")
        selectedDestination = stored == 0 ? nil : MIDIUniqueID(stored)
        setUp()
    }

    private func setUp() {
        var status = MIDIClientCreateWithBlock("TrackOSC Router" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                Task { @MainActor in self?.refreshDestinations() }
            }
        }
        guard status == noErr else { return }
        status = MIDISourceCreateWithProtocol(client, "TrackOSC Router" as CFString, ._1_0, &source)
        guard status == noErr else { return }
        // A stable unique ID lets other apps remember this source across launches.
        let storedID = UserDefaults.standard.integer(forKey: Self.sourceUniqueIDKey)
        if storedID != 0 {
            MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, Int32(storedID))
        } else {
            var id: Int32 = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &id)
            UserDefaults.standard.set(Int(id), forKey: Self.sourceUniqueIDKey)
        }
        MIDIOutputPortCreate(client, "TrackOSC Router Out" as CFString, &outputPort)
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

    func note(channel: Int, note: Int, velocity: Int, durationMs: Int) throws {
        try send(status: 0x90, channel: channel, data1: note, data2: velocity)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(max(1, durationMs)))
            try? self?.send(status: 0x80, channel: channel, data1: note, data2: 0)
        }
    }

    func controlChange(channel: Int, controller: Int, value: Int) throws {
        try send(status: 0xB0, channel: channel, data1: controller, data2: value)
    }

    private func send(status: UInt32, channel: Int, data1: Int, data2: Int) throws {
        guard isReady else { throw ActionError.midiUnavailable }
        let ch = UInt32(min(max(channel - 1, 0), 15))
        let d1 = UInt32(min(max(data1, 0), 127))
        let d2 = UInt32(min(max(data2, 0), 127))
        // UMP message type 2 (MIDI 1.0 channel voice), group 0.
        let word: UInt32 = (0x2 << 28) | ((status | ch) << 16) | (d1 << 8) | d2

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
