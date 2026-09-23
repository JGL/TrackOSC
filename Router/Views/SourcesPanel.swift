//
//  SourcesPanel.swift
//  TrackOSC Router (macOS)
//
//  Live readout of every source for the first detection, so you can see
//  what a rule would see before writing it.
//

import SwiftUI

struct SourcesPanel: View {
    @Bindable var store: RouterStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            List(SourceKind.allCases) { kind in
                HStack {
                    Text(kind.label)
                    Spacer()
                    Text(store.engine.read(ValueSource(kind: kind), latest: store.model.latest).display)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
    }
}
