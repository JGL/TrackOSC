//
//  KeyPresser.swift
//  TrackOSC Router (macOS)
//
//  Posts a key press to whatever app is frontmost. Needs Accessibility
//  access, which macOS grants per app in System Settings; the first
//  attempt asks for it.
//

import AppKit
import ApplicationServices
import Foundation
import Observation

@Observable @MainActor
final class KeyPresser {
    private(set) var isTrusted = AXIsProcessTrusted()

    func refreshTrust() {
        isTrusted = AXIsProcessTrusted()
    }

    /// Ask the system for access (shows the prompt once).
    func requestAccess() {
        // The key is a C global; spelling it out avoids touching shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func press(keyCode: Int, modifiers: KeyModifiers) throws {
        refreshTrust()
        guard isTrusted else {
            requestAccess()
            throw ActionError.accessibilityDenied
        }
        var flags = CGEventFlags()
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
