//
//  ActionRunner.swift
//  TrackOSC Router (macOS)
//
//  Dispatches a firing to the right backend.
//

import Foundation

@MainActor
final class ActionRunner {
    let midi = MIDIOut()
    let shortcuts = ShortcutRunner()
    let keys = KeyPresser()
    let http = HTTPAction()

    func perform(_ firing: Firing) async throws {
        switch firing.rule.action {
        case .midiNote(let channel, let note, let velocity, let durationMs):
            let vel = firing.rule.trigger.isContinuous ? Int((firing.value ?? Double(velocity)).rounded()) : velocity
            try midi.note(channel: channel, note: note, velocity: vel, durationMs: durationMs)
        case .midiCC(let channel, let controller, let value):
            let v = firing.rule.trigger.isContinuous ? Int((firing.value ?? Double(value)).rounded()) : value
            try midi.controlChange(channel: channel, controller: controller, value: v)
        case .shortcut(let name, let input):
            try await shortcuts.run(name: name, input: firing.fill(input))
        case .keyPress(let keyCode, let modifiers):
            try keys.press(keyCode: keyCode, modifiers: modifiers)
        case .http(let method, let url, let body):
            try await http.send(method: method, url: firing.fill(url), body: firing.fill(body))
        case .log:
            break
        }
    }
}

enum ActionError: LocalizedError {
    case midiUnavailable
    case badURL(String)
    case httpStatus(Int)
    case accessibilityDenied
    case shortcutFailed(String)

    var errorDescription: String? {
        switch self {
        case .midiUnavailable: "MIDI is not available"
        case .badURL(let url): "not a valid URL: \(url)"
        case .httpStatus(let code): "HTTP \(code)"
        case .accessibilityDenied: "key presses need Accessibility access (System Settings › Privacy & Security › Accessibility)"
        case .shortcutFailed(let message): "Shortcut failed: \(message)"
        }
    }
}
