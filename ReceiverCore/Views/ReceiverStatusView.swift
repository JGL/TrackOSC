//
//  ReceiverStatusView.swift
//  TrackOSC (ReceiverCore)
//
//  Per-address message rates and a scrolling (sampled) message log.
//

import SwiftUI

struct ReceiverStatusView: View {
    @Bindable var model: ReceiverModel

    private static let timeFormat = Date.FormatStyle(date: .omitted, time: .standard)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ratesSection
            Divider()
            logSection
        }
        .background(.background)
    }

    private var ratesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Message rates")
                .font(.headline)
            ForEach(FrameKind.allCases) { kind in
                HStack {
                    Circle().fill(kind.color).frame(width: 8, height: 8)
                    Text(kind.address)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text("\(Int(model.rates[kind] ?? 0)) Hz")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle((model.rates[kind] ?? 0) > 0 ? .primary : .tertiary)
                }
            }
            HStack {
                Text("Total messages")
                Spacer()
                Text("\(model.totalMessages)")
                    .font(.system(.body, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .padding(.top, 4)

            HStack {
                Text("Unknown / undecodable")
                Spacer()
                Text("\(model.unknownMessages)")
                    .font(.system(.body, design: .monospaced))
            }
            .foregroundStyle(model.unknownMessages > 0 ? .orange : .secondary)
            .help("Messages whose address or layout the receiver doesn't understand; the log shows one line per address every few seconds.")

            if model.ignoredMessages > 0 || model.settings.sourcePolicy != .all {
                HStack {
                    Text("Ignored (other senders)")
                    Spacer()
                    Text("\(model.ignoredMessages)")
                        .font(.system(.body, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .help("Messages dropped by the Senders policy in the toolbar")
            }
            if let host = model.activeHost {
                HStack {
                    Text("Sender")
                    Spacer()
                    Text(host)
                        .font(.system(.body, design: .monospaced))
                }
                .foregroundStyle(.secondary)
            }

            HStack {
                Text("Camera")
                Spacer()
                Text(cameraLabel)
                    .font(.system(.body, design: .monospaced))
            }
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var cameraLabel: String {
        guard let info = model.cameraInfo else { return "–" }
        return "\(info.width)×\(info.height) \(info.orientationName), \(info.isFrontCamera ? "front" : "back")"
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Log")
                    .font(.headline)
                Text("(sampled)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Pause", isOn: $model.isLogPaused)
                    .toggleStyle(.checkbox)
            }
            .padding([.horizontal, .top])

            List(model.log) { entry in
                HStack(spacing: 8) {
                    Text(entry.time, format: Self.timeFormat)
                        .foregroundStyle(.secondary)
                    Text(entry.address)
                    if let note = entry.note {
                        Text(note)
                            .foregroundStyle(.orange)
                    } else {
                        Text("n=\(entry.detectionCount)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(entry.senderHost)
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 11, design: .monospaced))
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
    }
}
