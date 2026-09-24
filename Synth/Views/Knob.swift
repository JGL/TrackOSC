//
//  Knob.swift
//  TrackOSC Synth (macOS)
//
//  A rotary knob: drag up and down to turn, double-click to reset, with
//  the name under it and the value while dragging. A mapped knob shows a
//  ring in the app accent so it is obvious tracking is driving it.
//

import SwiftUI
import SynthCore

struct Knob: View {
    let id: ParameterID
    @Bindable var store: SynthStore
    var isMapped = false
    var size: CGFloat = 44

    @State private var dragStart: Float?
    @State private var isDragging = false

    private var range: ClosedRange<Float> { id.range }
    private var normalised: Float {
        let v = store.value(id)
        return (v - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(normalised) * 0.75)
                    .stroke(isMapped ? Color.accentColor : Color.primary.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .padding(6)
                    .shadow(radius: 1)
                Rectangle()
                    .fill(isMapped ? Color.accentColor : Color.primary)
                    .frame(width: 2, height: size * 0.22)
                    .offset(y: -size * 0.24)
                    .rotationEffect(.degrees(Double(normalised) * 270 - 135))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        if dragStart == nil { dragStart = normalised; isDragging = true }
                        let delta = Float(-drag.translation.height / 150)
                        let t = min(max((dragStart ?? 0) + delta, 0), 1)
                        store.set(id, range.lowerBound + t * (range.upperBound - range.lowerBound))
                    }
                    .onEnded { _ in dragStart = nil; isDragging = false }
            )
            .onTapGesture(count: 2) { store.set(id, id.defaultValue) }
            Text(isDragging ? formatted : label)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(isDragging ? .primary : .secondary)
                .frame(width: size + 16)
        }
        .help("\(id.name): \(formatted). Drag up or down; double-click to reset.")
    }

    private var label: String {
        if let (_, which) = id.drumComponents { return ["Tune", "Decay", "Tone", "Level"][which] }
        return id.name
    }

    private var formatted: String {
        let v = store.value(id)
        switch id {
        case .bassCutoff: return "\(Int(v)) Hz"
        case .tempo: return "\(Int(v)) BPM"
        case .bassTune: return String(format: "%+.1f st", v)
        case .delayTime: return String(format: "%.0f ms", v * 1000)
        case .bassDecay: return String(format: "%.2f s", v)
        case .swing: return "\(Int(v * 100)) %"
        case .bassWaveform: return v < 0.5 ? "Saw" : "Pulse"
        default: return String(format: "%.2f", v)
        }
    }
}
