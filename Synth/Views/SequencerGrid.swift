//
//  SequencerGrid.swift
//  TrackOSC Synth (macOS)
//
//  Sixteen steps: a bass row (click a step to gate it, drag up and down
//  for the note, ⌥-click for accent, ⇧-click for slide) and one row per
//  drum (click cycles off / on / accent). The playing step lights up.
//

import SwiftUI
import SynthCore

struct SequencerGrid: View {
    @Bindable var store: SynthStore

    private let cell: CGFloat = 19
    private let gap: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Pattern", selection: Binding(get: { store.patternIndex }, set: { store.selectPattern($0) })) {
                    ForEach(0..<8, id: \.self) { Text("\($0 + 1)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Menu {
                    Button("Randomise") { store.randomisePattern() }
                    Button("Clear") { store.clearPattern() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
            }
            HStack(spacing: 8) {
                Button(store.isPlaying ? "Stop" : "Play") { store.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                Toggle("Conductor", isOn: $store.conductorMode)
                    .toggleStyle(.checkbox)
                    .help("Steps advance only when an event mapping fires Advance step (a hit, a raised hand), not on a clock.")
                Spacer()
                Text("\(Int(store.value(.tempo))) BPM")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)

            VStack(alignment: .leading, spacing: gap) {
                stepHeader
                bassRow
                ForEach(DrumVoiceKind.allCases, id: \.self) { kind in
                    drumRow(kind)
                }
            }
            Text("Bass: click gates a step, drag up or down changes the note, \u{2325}-click accents, \u{21E7}-click slides. Drums: click cycles off, on, accent.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var stepHeader: some View {
        HStack(spacing: gap) {
            Text("").frame(width: 30)
            ForEach(0..<StepPattern.steps, id: \.self) { s in
                Circle()
                    .fill(s == store.step ? Color.accentColor : Color.primary.opacity(s % 4 == 0 ? 0.3 : 0.12))
                    .frame(width: 6, height: 6)
                    .frame(width: cell, height: 8)
            }
        }
    }

    private var bassRow: some View {
        HStack(spacing: gap) {
            Text("Bass").font(.caption2).frame(width: 30, alignment: .leading)
            ForEach(0..<StepPattern.steps, id: \.self) { s in
                BassCell(step: s, value: store.patterns[store.patternIndex].bass[s], isCurrent: s == store.step, size: cell) { newValue in
                    store.setBassStep(s, newValue)
                }
            }
        }
    }

    private func drumRow(_ kind: DrumVoiceKind) -> some View {
        HStack(spacing: gap) {
            Text(kind.shortName).font(.caption2.monospaced()).frame(width: 30, alignment: .leading)
            ForEach(0..<StepPattern.steps, id: \.self) { s in
                let v = store.patterns[store.patternIndex].drum(kind, at: s)
                RoundedRectangle(cornerRadius: 3)
                    .fill(v == 0 ? Color.primary.opacity(s % 4 == 0 ? 0.1 : 0.06) : (v == 2 ? Color.accentColor : Color.accentColor.opacity(0.55)))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(s == store.step ? Color.primary.opacity(0.6) : .clear, lineWidth: 1))
                    .frame(width: cell, height: cell)
                    .contentShape(Rectangle())
                    .onTapGesture { store.toggleDrum(kind, step: s) }
            }
        }
    }
}

private struct BassCell: View {
    let step: Int
    let value: BassStep
    let isCurrent: Bool
    let size: CGFloat
    let onChange: (BassStep) -> Void

    @State private var dragStartNote: Int?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(value.gate ? (value.accent ? Color.orange : Color.orange.opacity(0.55)) : Color.primary.opacity(step % 4 == 0 ? 0.1 : 0.06))
            if value.gate {
                Text(noteLabel)
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.8))
            }
            if value.slide {
                Rectangle().fill(Color.black.opacity(0.5)).frame(height: 2).offset(y: size / 2 - 2)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(isCurrent ? Color.primary.opacity(0.6) : .clear, lineWidth: 1))
        .frame(width: size, height: size * 1.6)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { drag in
                    if dragStartNote == nil { dragStartNote = value.note }
                    let delta = Int((-drag.translation.height / 6).rounded())
                    var v = value
                    v.note = min(max((dragStartNote ?? 36) + delta, 24), 60)
                    v.gate = true
                    if v != value { onChange(v) }
                }
                .onEnded { _ in dragStartNote = nil }
        )
        .onTapGesture {
            var v = value
            let flags = NSEvent.modifierFlags
            if flags.contains(.option) { v.accent.toggle(); v.gate = true }
            else if flags.contains(.shift) { v.slide.toggle(); v.gate = true }
            else { v.gate.toggle() }
            onChange(v)
        }
        .help(value.gate ? "\(String.noteName(value.note))\(value.accent ? " accent" : "")\(value.slide ? " slide" : "")" : "Off")
    }

    private var noteLabel: String {
        let name = String.noteName(value.note)
        return name.count > 2 ? String(name.prefix(2)) : name
    }
}
