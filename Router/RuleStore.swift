//
//  RuleStore.swift
//  TrackOSC Router (macOS)
//
//  Rules live as JSON in Application Support; presets are built in and
//  can be added any time; import/export use the same JSON.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum RuleStore {
    static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("TrackOSC Router", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("rules.json")
    }()

    static func load() -> [Rule]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode([Rule].self, from: data)
    }

    static func save(_ rules: [Rule]) {
        guard let data = try? encoder.encode(rules) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func exportPanel(_ rules: [Rule]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "TrackOSC Router rules.json"
        guard panel.runModal() == .OK, let url = panel.url, let data = try? encoder.encode(rules) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func importPanel() -> [Rule]? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode([Rule].self, from: data)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder = JSONDecoder()

    /// Ready-made rules that show each trigger and action.
    static let presets: [Rule] = [
        Rule(name: "Person appears → MIDI note", trigger: .presence(kind: .poses, edge: .appear), action: .midiNote(channel: 1, note: 60, velocity: 100, durationMs: 200)),
        Rule(name: "Person leaves → MIDI note", trigger: .presence(kind: .poses, edge: .leave), action: .midiNote(channel: 1, note: 48, velocity: 100, durationMs: 200)),
        Rule(name: "Nose across → MIDI CC 1", trigger: .continuous(source: ValueSource(kind: .noseX), inMin: 0, inMax: 1, outMin: 0, outMax: 127, rateHz: 30), action: .midiCC(channel: 1, controller: 1, value: 0)),
        Rule(name: "Nose down → MIDI CC 2", trigger: .continuous(source: ValueSource(kind: .noseY), inMin: 0, inMax: 1, outMin: 127, outMax: 0, rateHz: 30), action: .midiCC(channel: 1, controller: 2, value: 0)),
        Rule(name: "Right hand raised → Space", trigger: .threshold(source: ValueSource(kind: .rightHandRaised), value: 0.5, direction: .rise, hysteresis: 0), action: .keyPress(keyCode: 49, modifiers: [])),
        Rule(name: "Hand count changes → log", trigger: .presence(kind: .hands, edge: .change), action: .log),
        Rule(name: "Close to camera → HTTP", trigger: .range(source: ValueSource(kind: .distance3D), low: 0, high: 1.2, edge: .enter), action: .http(method: "GET", url: "http://127.0.0.1:8080/close?value={value}", body: "")),
        Rule(name: "QR code → Shortcut", trigger: .stringMatch(source: ValueSource(kind: .barcodePayload), mode: .contains, pattern: "http", cooldown: 30), action: .shortcut(name: "Open URLs", input: "{text}")),
        Rule(name: "Text HELLO → log", trigger: .stringMatch(source: ValueSource(kind: .recognisedText), mode: .equals, pattern: "HELLO", cooldown: 10), action: .log),
        Rule(name: "Mouth opens → MIDI note", trigger: .threshold(source: ValueSource(kind: .mouthOpenness), value: 0.4, direction: .rise, hysteresis: 0.1), action: .midiNote(channel: 1, note: 72, velocity: 110, durationMs: 150)),
    ]

    static let starterRules: [Rule] = [
        presets[0], presets[1], presets[2], presets[5],
    ]
}
