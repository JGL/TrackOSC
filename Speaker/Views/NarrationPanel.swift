//
//  NarrationPanel.swift
//  TrackOSC Speaker (macOS)
//

import SwiftUI

struct NarrationPanel: View {
    @Bindable var store: SpeakerStore

    var body: some View {
        @Bindable var settings = store.settings
        VStack(alignment: .leading, spacing: 12) {
            Text("What to narrate").font(.headline)
            Text("Appearances, departures and counts are spoken for the ticked kinds. Body, human and 3D body all mean \"a person\"; tick one to avoid saying it twice.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(FrameKind.allCases) { kind in
                Toggle(isOn: Binding(
                    get: { settings.narratedKinds.contains(kind) },
                    set: { on in if on { settings.narratedKinds.insert(kind) } else { settings.narratedKinds.remove(kind) } }
                )) {
                    HStack {
                        Circle().fill(kind.color).frame(width: 8, height: 8)
                        Text(kind.address).font(.system(.body, design: .monospaced))
                    }
                }
                .toggleStyle(.checkbox)
            }

            Divider()
            Text("Summary").font(.headline)
            HStack {
                Text("Every")
                Slider(value: $settings.summaryInterval, in: 0...120, step: 5)
                Text(settings.summaryInterval == 0 ? "off" : "\(Int(settings.summaryInterval)) s")
                    .frame(width: 40, alignment: .trailing)
                    .font(.system(.body, design: .monospaced))
            }
            Picker("Detail", selection: $settings.verbosity) {
                ForEach(Verbosity.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(verbosityHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Say \"Nobody here\" when everyone has gone", isOn: $settings.announceEmpty)
                .toggleStyle(.checkbox)

            Divider()
            Text("Timing").font(.headline)
            HStack {
                Text("Repeat text or codes after")
                Slider(value: $settings.textCooldown, in: 5...300, step: 5)
                Text("\(Int(settings.textCooldown)) s")
                    .frame(width: 40, alignment: .trailing)
                    .font(.system(.body, design: .monospaced))
            }
            HStack {
                Text("Merge events within")
                Slider(value: $settings.coalesceWindow, in: 0...2, step: 0.05)
                Text(String(format: "%.2f s", settings.coalesceWindow))
                    .frame(width: 52, alignment: .trailing)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private var verbosityHint: String {
        switch store.settings.verbosity {
        case .terse: "\"One person and one hand.\""
        case .normal: "\"One person and one hand. Nose 52 percent across, 31 percent down. Left hand raised.\""
        case .detailed: "Adds where the face is looking, mouth open, and distance and height from the 3D body."
        }
    }
}
