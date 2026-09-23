//
//  ShortcutRunner.swift
//  TrackOSC Router (macOS)
//
//  Runs a Shortcut by name through Shortcuts Events (Apple events; the
//  system asks for automation permission the first time). If that is
//  refused or fails, falls back to the shortcuts:// URL scheme, which
//  brings the Shortcuts app forward but always works.
//

import AppKit
import Foundation

@MainActor
final class ShortcutRunner {
    private(set) var lastError: String?

    func run(name: String, input: String) async throws {
        let escapedName = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedInput = input.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = input.isEmpty
            ? "tell application \"Shortcuts Events\" to run shortcut \"\(escapedName)\""
            : "tell application \"Shortcuts Events\" to run shortcut \"\(escapedName)\" with input \"\(escapedInput)\""
        var errorInfo: NSDictionary?
        // NSAppleScript is main-thread only; we are on the main actor.
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&errorInfo)
        }
        guard let errorInfo else { return }
        let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "unknown error"
        lastError = message
        // Fallback: the URL scheme.
        var components = URLComponents(string: "shortcuts://run-shortcut")!
        var items = [URLQueryItem(name: "name", value: name)]
        if !input.isEmpty {
            items.append(URLQueryItem(name: "input", value: "text"))
            items.append(URLQueryItem(name: "text", value: input))
        }
        components.queryItems = items
        guard let url = components.url, NSWorkspace.shared.open(url) else {
            throw ActionError.shortcutFailed(message)
        }
    }
}
