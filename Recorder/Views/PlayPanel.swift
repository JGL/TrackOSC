//
//  PlayPanel.swift
//  TrackOSC Recorder (macOS)
//

import PoseioscShared
import SwiftUI

struct PlayPanel: View {
    @Bindable var store: RecorderStore
    @State private var hostText = ""
    @State private var portText = ""

    var body: some View {
        @Bindable var player = store.player
        VStack(alignment: .leading, spacing: 8) {
            Text("Play").font(.headline)

            HStack {
                Button("Open…") { player.presentOpenPanel() }
                if !player.recentURLs.isEmpty {
                    Menu("Recent") {
                        ForEach(player.recentURLs, id: \.self) { url in
                            Button(url.lastPathComponent) { player.open(url: url) }
                        }
                    }
                    .fixedSize()
                }
            }

            if let reader = player.reader, let url = player.fileURL {
                Text(url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    Text("\(reader.records.count) messages")
                    Spacer()
                    Text(RecordPanel.format(reader.duration))
                    if reader.wasTruncated {
                        Text("(truncated)").foregroundStyle(.orange)
                    }
                }
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            } else {
                Text("Open a .trackosc file, or drop one on the stage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Toggle("Loop", isOn: $player.isLooping)
                    .toggleStyle(.checkbox)
                Spacer()
                Picker("Speed", selection: $player.speed) {
                    ForEach(PlayerController.speeds, id: \.self) { speed in
                        Text(speed == 1 ? "1×" : "\(speed.formatted())×").tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            Text("Send to").font(.subheadline)
            HStack {
                TextField("Host", text: $hostText)
                    .frame(width: 140)
                TextField("Port", text: $portText)
                    .frame(width: 64)
                Button("Apply", action: applyDestination)
                    .controlSize(.small)
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit(applyDestination)
            if !store.model.bonjour.receivers.isEmpty {
                Menu("Discovered receivers") {
                    ForEach(store.model.bonjour.receivers) { receiver in
                        Button(receiver.name) { select(receiver) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if store.isPlayingIntoSelf {
                Text("Playing into this app's own port \(String(player.destinationPort)): the stage shows the playback.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Sent \(player.sentCount)")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)

            if let error = player.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .onAppear {
            hostText = player.destinationHost
            portText = String(player.destinationPort)
            store.model.bonjour.start()
        }
    }

    private func select(_ receiver: DiscoveredReceiver) {
        Task {
            guard let result = await store.model.bonjour.resolve(receiver) else { return }
            hostText = result.host
            portText = String(result.port)
            applyDestination()
        }
    }

    private func applyDestination() {
        store.player.destinationHost = hostText.trimmingCharacters(in: .whitespaces)
        if let port = UInt16(portText), port > 0 { store.player.destinationPort = port }
    }
}
