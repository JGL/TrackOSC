//
//  MappingPanel.swift
//  TrackOSC Synth (macOS)
//
//  How tracking plays the instrument: continuous mappings (a source, a
//  target, ranges, curve, smoothing) with live readouts, and event
//  mappings (a gesture fires a drum, a note, a pattern, a step).
//

import SwiftUI
import SynthCore

struct MappingPanel: View {
    @Bindable var store: SynthStore
    @State private var expanded: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Tracking plays the instrument", isOn: $store.mappingsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                sectionHeader("Continuous", count: store.continuous.count) { store.addContinuous() }
                ForEach($store.continuous) { $mapping in
                    ContinuousRow(store: store, mapping: $mapping, isExpanded: expanded == mapping.id) {
                        expanded = expanded == mapping.id ? nil : mapping.id
                    }
                }
                if store.continuous.isEmpty {
                    Text("No continuous mappings. Add one to let, say, your nose sweep the filter.").font(.caption).foregroundStyle(.secondary)
                }

                sectionHeader("Events", count: store.events.count) { store.addEvent() }
                ForEach($store.events) { $mapping in
                    EventRow(store: store, mapping: $mapping)
                }
                if store.events.isEmpty {
                    Text("No event mappings. Add one to fire a drum when a hand goes up.").font(.caption).foregroundStyle(.secondary)
                }

                GroupBox("Live sources") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(ContinuousSource.allCases) { source in
                            HStack {
                                Text(source.name).font(.caption)
                                Spacer()
                                if let v = store.readings.continuous[source] {
                                    Text(String(format: "%.2f", v)).font(.caption.monospaced())
                                } else {
                                    Text("\u{2013}").font(.caption.monospaced()).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding()
        }
    }

    private func sectionHeader(_ title: String, count: Int, add: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.headline)
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(action: add) { Image(systemName: "plus") }
                .controlSize(.small)
        }
    }
}

private struct ContinuousRow: View {
    @Bindable var store: SynthStore
    @Binding var mapping: ContinuousMapping
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Toggle("", isOn: $mapping.isEnabled).labelsHidden().toggleStyle(.checkbox)
                Picker("", selection: $mapping.source) {
                    ForEach(ContinuousSource.allCases) { Text($0.name).tag($0) }
                }
                .labelsHidden()
                .onChange(of: mapping.source) { _, new in mapping.inputRange = new.defaultRange }
                Image(systemName: "arrow.right").foregroundStyle(.secondary).font(.caption)
                TargetPicker(target: $mapping.target)
                Button { toggle() } label: { Image(systemName: isExpanded ? "chevron.up" : "chevron.down") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Button { store.remove(continuousID: mapping.id) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .controlSize(.small)
            // Live bar: input position and mapped output.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    if let raw = store.readings.continuous[mapping.source] {
                        let t = CGFloat(min(max((raw - mapping.inputRange.lowerBound) / max(0.0001, mapping.inputRange.upperBound - mapping.inputRange.lowerBound), 0), 1))
                        Capsule().fill(Color.accentColor.opacity(0.6)).frame(width: max(4, geo.size.width * t))
                    }
                }
            }
            .frame(height: 4)
            if isExpanded {
                Grid(alignment: .leading, verticalSpacing: 6) {
                    GridRow {
                        Text("In").font(.caption)
                        rangeFields($mapping.inputRange)
                    }
                    GridRow {
                        Text("Out").font(.caption)
                        rangeFields($mapping.outputRange)
                    }
                    GridRow {
                        Text("Curve").font(.caption)
                        HStack {
                            Picker("", selection: $mapping.curve) {
                                ForEach(Curve.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                            }
                            .labelsHidden()
                            Toggle("Invert", isOn: $mapping.invert).toggleStyle(.checkbox)
                        }
                    }
                    GridRow {
                        Text("Smooth").font(.caption)
                        HStack {
                            Slider(value: $mapping.smoothing, in: 0...2)
                            Text(String(format: "%.2f s", mapping.smoothing)).font(.caption.monospaced()).frame(width: 46)
                        }
                    }
                    GridRow {
                        Text("Person").font(.caption)
                        Stepper("\(mapping.person + 1)", value: $mapping.person, in: 0...7)
                    }
                }
                .controlSize(.small)
                .padding(.leading, 20)
                if let out = store.mappedValues[mapping.id] {
                    Text("Now: \(String(format: "%.2f", out))").font(.caption.monospaced()).foregroundStyle(.secondary).padding(.leading, 20)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func rangeFields(_ range: Binding<ClosedRange<Float>>) -> some View {
        HStack {
            TextField("", value: Binding(get: { range.wrappedValue.lowerBound }, set: { lo in
                let hi = max(range.wrappedValue.upperBound, lo)
                range.wrappedValue = lo...hi
            }), format: .number.precision(.fractionLength(0...2)))
            .frame(width: 60)
            Text("to").font(.caption)
            TextField("", value: Binding(get: { range.wrappedValue.upperBound }, set: { hi in
                let lo = min(range.wrappedValue.lowerBound, hi)
                range.wrappedValue = lo...hi
            }), format: .number.precision(.fractionLength(0...2)))
            .frame(width: 60)
        }
        .textFieldStyle(.roundedBorder)
    }
}

private struct EventRow: View {
    @Bindable var store: SynthStore
    @Binding var mapping: EventMapping

    var body: some View {
        HStack(spacing: 6) {
            let flashed = store.eventFlashes[mapping.id].map { Date().timeIntervalSince($0) < 0.15 } ?? false
            Circle().fill(flashed ? Color.accentColor : Color.primary.opacity(0.15)).frame(width: 8, height: 8)
            Toggle("", isOn: $mapping.isEnabled).labelsHidden().toggleStyle(.checkbox)
            Picker("", selection: $mapping.source) {
                ForEach(EventSource.allCases) { Text($0.name).tag($0) }
            }
            .labelsHidden()
            Image(systemName: "arrow.right").foregroundStyle(.secondary).font(.caption)
            EventTargetPicker(target: $mapping.target)
            Button { store.remove(eventID: mapping.id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Continuous targets as one menu: knobs grouped, then MIDI CCs.
private struct TargetPicker: View {
    @Binding var target: ContinuousTarget

    var body: some View {
        Menu {
            Section("Bass") {
                ForEach([ParameterID.bassTune, .bassCutoff, .bassResonance, .bassEnvMod, .bassDecay, .bassAccent, .bassOverdrive, .bassLevel], id: \.self) { id in
                    Button(id.name) { target = .parameter(id) }
                }
            }
            Section("Drums") {
                ForEach(DrumVoiceKind.allCases, id: \.self) { kind in
                    Menu(kind.name) {
                        ForEach(0..<4, id: \.self) { c in
                            let id = ParameterID.drum(kind, component: c)
                            Button(["Tune", "Decay", "Tone", "Level"][c]) { target = .parameter(id) }
                        }
                    }
                }
            }
            Section("Mix and transport") {
                ForEach([ParameterID.tempo, .swing, .delayMix, .delayTime, .delayFeedback, .reverbMix, .masterLevel], id: \.self) { id in
                    Button(id.name) { target = .parameter(id) }
                }
            }
            Section("MIDI CC (channel 1)") {
                ForEach([1, 2, 7, 10, 11, 71, 74], id: \.self) { cc in
                    Button("CC \(cc)") { target = .midiCC(channel: 1, controller: cc) }
                }
            }
        } label: {
            Text(target.name).lineLimit(1)
        }
        .menuStyle(.borderedButton)
        .onChange(of: target) { _, _ in }
    }
}

private struct EventTargetPicker: View {
    @Binding var target: EventTarget

    var body: some View {
        Menu {
            Section("Drums") {
                ForEach(DrumVoiceKind.allCases, id: \.self) { kind in
                    Button(kind.name) { target = .drum(kind) }
                }
            }
            Section("Bass notes") {
                ForEach([36, 38, 39, 41, 43, 46, 48], id: \.self) { note in
                    Button(String.noteName(note)) { target = .bassNote(note) }
                }
            }
            Section("Patterns") {
                ForEach(0..<8, id: \.self) { i in Button("Pattern \(i + 1)") { target = .selectPattern(i) } }
            }
            Section("Transport") {
                Button("Advance step (conductor)") { target = .advanceStep }
                Button("Play / stop") { target = .playStop }
            }
            Section("MIDI note (channel 1)") {
                ForEach([48, 52, 55, 60, 64, 67, 72], id: \.self) { note in
                    Button(String.noteName(note)) { target = .midiNote(channel: 1, note: note) }
                }
            }
        } label: {
            Text(target.name).lineLimit(1)
        }
        .menuStyle(.borderedButton)
    }
}
