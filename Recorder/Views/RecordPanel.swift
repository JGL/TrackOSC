//
//  RecordPanel.swift
//  TrackOSC Recorder (macOS)
//

import SwiftUI

struct RecordPanel: View {
    @Bindable var store: RecorderStore

    var body: some View {
        let status = store.recordingStatus
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Record").font(.headline)
                Spacer()
                if status.isRecording {
                    Circle().fill(.red).frame(width: 9, height: 9)
                    Text(Self.format(status.elapsed))
                        .font(.system(.body, design: .monospaced))
                }
            }

            HStack {
                Button(status.isRecording ? "Stop Recording" : "Start Recording") { store.toggleRecording() }
                    .keyboardShortcut("r")
                Toggle("Record on launch", isOn: $store.recordOnLaunch)
                    .toggleStyle(.checkbox)
                    .help("Start a new recording every time the app opens")
            }

            if status.isRecording, let url = status.url {
                Text(url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    Text("\(status.recordCount) messages")
                    Spacer()
                    Text(Self.format(bytes: status.byteCount))
                }
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                if store.isPlayingIntoSelf, store.player.isPlaying {
                    Text("Playback is aimed at this app's own port, so it is being recorded too.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } else if let last = store.folder.lastRecording {
                HStack {
                    Text("Last: \(last.lastPathComponent)")
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Play") { store.player.open(url: last); store.player.play() }
                        .controlSize(.small)
                    Button("Reveal") { store.folder.reveal(last) }
                        .controlSize(.small)
                }
            }

            if !status.countsByAddress.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(status.countsByAddress.sorted(by: { $0.key < $1.key }), id: \.key) { address, count in
                        HStack {
                            Text(address)
                            Spacer()
                            Text("\(count)")
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = store.recorderError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            HStack {
                Text("Folder:")
                Text(store.folder.url.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.callout)
            HStack {
                Button("Choose…") { store.folder.choose() }
                if store.folder.isCustom {
                    Button("Use Downloads") { store.folder.useDefault() }
                }
                Button("Reveal") { store.folder.reveal() }
            }
            .controlSize(.small)
        }
    }

    static func format(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let m = Int(seconds) / 60
        let s = seconds - Double(m * 60)
        return String(format: "%d:%04.1f", m, s)
    }

    static func format(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
