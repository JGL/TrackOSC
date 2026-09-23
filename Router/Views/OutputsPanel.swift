//
//  OutputsPanel.swift
//  TrackOSC Router (macOS)
//

import SwiftUI

struct OutputsPanel: View {
    @Bindable var store: RouterStore

    var body: some View {
        let midi = store.engine.actions.midi
        let keys = store.engine.actions.keys
        VStack(alignment: .leading, spacing: 12) {
            Text("MIDI").font(.headline)
            Text(midi.isReady
                 ? "This app is a MIDI source named \"TrackOSC Router\": choose it as an input in your DAW or synth. Optionally also send to a device below."
                 : "MIDI could not be set up.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Picker("Also send to", selection: Binding(
                    get: { midi.selectedDestination.map(MIDIUniqueIDOptional.some) ?? .none },
                    set: { if case .some(let id) = $0 { midi.selectedDestination = id } else { midi.selectedDestination = nil } }
                )) {
                    Text("Virtual source only").tag(MIDIUniqueIDOptional.none)
                    ForEach(midi.destinations) { destination in
                        Text(destination.name).tag(MIDIUniqueIDOptional.some(destination.id))
                    }
                }
                Button("Refresh") { midi.refreshDestinations() }.controlSize(.small)
            }
            Text("Sent \(midi.sentCount) messages · capped at \(RouterEngine.midiPerSecondCap) per second")
                .font(.footnote.monospaced()).foregroundStyle(.secondary)

            Divider()
            Text("Key presses").font(.headline)
            HStack {
                Circle().fill(keys.isTrusted ? .green : .orange).frame(width: 9, height: 9)
                Text(keys.isTrusted ? "Accessibility access granted" : "Accessibility access needed to press keys")
                Spacer()
                if !keys.isTrusted {
                    Button("Request…") { keys.requestAccess() }.controlSize(.small)
                    Button("Open Settings") { keys.openAccessibilitySettings() }.controlSize(.small)
                }
                Button("Check") { keys.refreshTrust() }.controlSize(.small)
            }

            Divider()
            Text("Shortcuts").font(.headline)
            Text("Runs by name through Shortcuts Events; macOS asks for permission the first time. If refused, the shortcuts:// URL scheme is used instead (the Shortcuts app comes forward).")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = store.engine.actions.shortcuts.lastError {
                Text("Last error: \(error)").font(.footnote).foregroundStyle(.red)
            }

            Divider()
            Text("HTTP").font(.headline)
            Text("GET or POST to any URL, including plain http on the local network; 5 s timeout; non-2xx counts as a failure in the feed.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Divider()
            Text("Rules file").font(.headline)
            Text(RuleStore.fileURL.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.footnote.monospaced()).foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

/// Optional MIDIUniqueID as a Hashable tag for the picker.
private enum MIDIUniqueIDOptional: Hashable {
    case none
    case some(Int32)
}
