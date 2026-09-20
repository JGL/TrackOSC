//
//  DetectorChip.swift
//  TrackOSC Sender (shared)
//
//  A coloured pill toggle for one detector, and the horizontally scrolling
//  row of all of them, used by both sender apps.
//

import SwiftUI

struct DetectorChip: View {
    let label: String
    let color: Color
    var onTextColor: Color = .black
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(isOn ? color.opacity(0.85) : .black.opacity(0.4), in: .capsule)
                .foregroundStyle(isOn ? onTextColor : .white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) detection")
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// One chip per `Detector`, in `allCases` order, scrolling horizontally when
/// the row is wider than the screen (nine chips overflow an iPhone).
struct DetectorChipRow: View {
    let isOn: (Detector) -> Bool
    let toggle: (Detector) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Detector.allCases) { detector in
                    DetectorChip(
                        label: detector.label,
                        color: detector.color,
                        onTextColor: detector.chipTextColor,
                        isOn: isOn(detector)
                    ) {
                        toggle(detector)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}
