//
//  TransportStrip.swift
//  TrackOSC Recorder (macOS)
//
//  Play/pause, a scrubber and the time, floating over the stage.
//

import SwiftUI

struct TransportStrip: View {
    @Bindable var store: RecorderStore
    @State private var scrubbing = false
    @State private var scrubValue = 0.0

    var body: some View {
        let player = store.player
        let total = seconds(player.duration)
        HStack(spacing: 12) {
            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .disabled(player.reader == nil)
            .keyboardShortcut(.space, modifiers: [])

            Button {
                player.stop()
            } label: {
                Image(systemName: "stop.fill").frame(width: 18)
            }
            .disabled(player.reader == nil)

            Text(RecordPanel.format(scrubbing ? .seconds(scrubValue) : player.position))
                .font(.system(.callout, design: .monospaced))
                .frame(width: 64, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { scrubbing ? scrubValue : seconds(player.position) },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(total, 0.001)
            ) { editing in
                if editing {
                    scrubbing = true
                    scrubValue = seconds(player.position)
                } else {
                    scrubbing = false
                    player.seek(to: .seconds(scrubValue))
                }
            }
            .disabled(player.reader == nil)

            Text(RecordPanel.format(player.duration))
                .font(.system(.callout, design: .monospaced))
                .frame(width: 64, alignment: .leading)

            if store.recorder.isRecording {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text("REC")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: .rect(cornerRadius: 10))
        .padding(12)
        .foregroundStyle(.white)
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
