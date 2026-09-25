//
//  BassPanel.swift
//  TrackOSC Synth (macOS)
//

import SwiftUI
import SynthCore

struct BassPanel: View {
    @Bindable var store: SynthStore

    private var mapped: Set<ParameterID> {
        Set(store.continuous.compactMap { m in if case .parameter(let id) = m.target, m.isEnabled { id } else { nil } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Bass (303)") {
                    VStack(spacing: 12) {
                        Picker("Waveform", selection: Binding(get: { store.value(.bassWaveform) < 0.5 ? 0 : 1 }, set: { store.set(.bassWaveform, $0 == 0 ? 0 : 1) })) {
                            Text("Saw").tag(0)
                            Text("Pulse").tag(1)
                        }
                        .pickerStyle(.segmented)
                        knobRow([.bassTune, .bassCutoff, .bassResonance, .bassEnvMod])
                        knobRow([.bassDecay, .bassAccent, .bassOverdrive, .bassLevel])
                        HStack {
                            ForEach([36, 38, 39, 41, 43, 46, 48], id: \.self) { note in
                                Button(noteName(note)) { store.playBass(note) }
                                    .font(.caption.monospaced())
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                GroupBox("Mix") {
                    VStack(spacing: 12) {
                        knobRow([.delayMix, .delayTime, .delayFeedback, .reverbMix])
                        knobRow([.masterLevel, .tempo, .swing])
                    }
                    .padding(.vertical, 4)
                }
                GroupBox("Output") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Device", selection: Binding(get: { store.selectedOutputDevice ?? 0 }, set: { store.selectedOutputDevice = $0 })) {
                            ForEach(store.outputDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        if let error = store.host.lastError {
                            Text(error).font(.caption).foregroundStyle(.red)
                        } else {
                            Text("Audio keeps running with the controls hidden and in full screen.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                GroupBox("MIDI out") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Send what the synth plays as MIDI", isOn: Binding(get: { store.midi.isEnabled }, set: { store.midi.isEnabled = $0 }))
                        Toggle("Send MIDI clock and start/stop", isOn: Binding(get: { store.midi.sendsClock }, set: { store.midi.sendsClock = $0 }))
                        Picker("Also send to", selection: Binding(get: { store.midi.selectedDestination ?? 0 }, set: { store.midi.selectedDestination = $0 == 0 ? nil : $0 })) {
                            Text("Virtual source only").tag(Int32(0))
                            ForEach(store.midi.destinations) { destination in
                                Text(destination.name).tag(destination.id)
                            }
                        }
                        Text("Other apps see a MIDI source called \u{201C}TrackOSC Synth\u{201D}: bass on channel 1, drums on channel 10 (General MIDI notes).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
    }

    private func knobRow(_ ids: [ParameterID]) -> some View {
        HStack(spacing: 8) {
            ForEach(ids, id: \.self) { id in
                Knob(id: id, store: store, isMapped: mapped.contains(id))
            }
        }
        .frame(maxWidth: .infinity)
    }

    nonisolated static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private func noteName(_ midi: Int) -> String { "\(Self.noteNames[midi % 12])\(midi / 12 - 1)" }
}

extension String {
    static func noteName(_ midi: Int) -> String { "\(BassPanel.noteNames[Swift.max(0, midi) % 12])\(midi / 12 - 1)" }
}
