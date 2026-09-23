//
//  ActivityStage.swift
//  TrackOSC Router (macOS)
//
//  The stage: one LED per rule, lit for a moment when it fires, over the
//  activity feed. Readable from across a room in presentation mode.
//

import SwiftUI

struct ActivityStage: View {
    @Bindable var store: RouterStore
    private static let timeFormat = Date.FormatStyle(date: .omitted, time: .standard)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let now = timeline.date
            ZStack {
                Color.black
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(store.engine.rules) { rule in
                            let age = store.engine.lastFired[rule.id].map { now.timeIntervalSince($0) } ?? 10
                            let lit = max(0, 1 - age / 0.4)
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(rule.isEnabled ? store.model.app.accent.opacity(0.25 + 0.75 * lit) : Color.gray.opacity(0.3))
                                    .frame(width: 12, height: 12)
                                    .shadow(color: store.model.app.accent.opacity(lit), radius: 6)
                                Text(rule.name)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .foregroundStyle(rule.isEnabled ? .white : .white.opacity(0.4))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.06), in: .rect(cornerRadius: 8))
                        }
                    }
                    .padding([.horizontal, .top], 16)

                    if store.engine.dryRun {
                        Label("Dry run: nothing is sent", systemImage: "eye")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(store.engine.feed) { entry in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(entry.time, format: Self.timeFormat)
                                        .foregroundStyle(.white.opacity(0.4))
                                    Text(entry.ruleName)
                                        .foregroundStyle(entry.isError ? .red : store.model.app.accent)
                                        .frame(width: 200, alignment: .leading)
                                        .lineLimit(1)
                                    Text(entry.detail)
                                        .foregroundStyle(entry.isError ? .red : .white.opacity(0.85))
                                        .lineLimit(2)
                                    Spacer()
                                }
                                .font(.system(size: 13, design: .monospaced))
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }
}
