//
//  DrumsPanel.swift
//  TrackOSC Synth (macOS)
//

import SwiftUI
import SynthCore

struct DrumsPanel: View {
    @Bindable var store: SynthStore

    private var mapped: Set<ParameterID> {
        Set(store.continuous.compactMap { m in if case .parameter(let id) = m.target, m.isEnabled { id } else { nil } })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(DrumVoiceKind.allCases, id: \.self) { kind in
                    let hit = store.lastDrumHits[kind].map { Date().timeIntervalSince($0) < 0.12 } ?? false
                    HStack(spacing: 8) {
                        Button {
                            store.hit(kind)
                        } label: {
                            Text(kind.shortName)
                                .font(.caption.bold().monospaced())
                                .frame(width: 34, height: 34)
                                .background(hit ? Color.accentColor : Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("\(kind.name): click to audition")
                        ForEach(0..<4, id: \.self) { component in
                            let id = ParameterID.drum(kind, component: component)
                            Knob(id: id, store: store, isMapped: mapped.contains(id), size: 36)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Text("808-style models: a swept sine kick, two-tone snare with filtered noise, six-square hats, toms, a clap of noise bursts and a two-square cowbell.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
    }
}
