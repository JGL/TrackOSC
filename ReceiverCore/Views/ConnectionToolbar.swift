//
//  ConnectionToolbar.swift
//  TrackOSC (ReceiverCore)
//
//  Listening status, port, Restart, the advertised Bonjour name and the
//  forwarding popover – the same in every receiver-type app.
//

import PoseioscShared
import SwiftUI

struct ConnectionToolbar: ToolbarContent {
    @Bindable var model: ReceiverModel
    @State private var portText = ""
    @State private var showForwarding = false

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Circle()
                .fill(model.isListening ? .green : .red)
                .frame(width: 10, height: 10)
            Text(model.isListening ? "Listening on UDP" : "Not listening")
                .font(.callout)

            TextField("Port", text: $portText)
                .frame(width: 64)
                .textFieldStyle(.roundedBorder)
                .onSubmit(applyPort)
                .onAppear { portText = String(model.effectivePort) }
                .onChange(of: model.effectivePort) { portText = String(model.effectivePort) }
            Button("Restart", action: applyPort)

            Button {
                showForwarding.toggle()
            } label: {
                Label("Forward", systemImage: "arrow.turn.down.right")
                    .foregroundStyle(model.settings.forwardEnabled ? Color.accentColor : Color.primary)
            }
            .help("Forward every incoming message to another app or machine")
            .popover(isPresented: $showForwarding) {
                ForwardingPopover(model: model)
            }

            if let name = model.advertisedName {
                Label(name, systemImage: "dot.radiowaves.left.and.right")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func applyPort() {
        guard let port = UInt16(portText), port > 0 else {
            portText = String(model.effectivePort)
            return
        }
        model.restart(port: port)
    }
}

/// Forwarding settings: enable, destination (typed or picked from Bonjour), counters.
struct ForwardingPopover: View {
    @Bindable var model: ReceiverModel
    @State private var hostText = ""
    @State private var portText = ""

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Forward incoming messages", isOn: $settings.forwardEnabled)
                .onChange(of: settings.forwardEnabled) { model.applyForwarding() }
            Text("Every datagram is re-sent unchanged, so TrackOSC apps can be chained on one Mac: sender → this app → the next one.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                TextField("Host", text: $hostText)
                    .frame(width: 160)
                TextField("Port", text: $portText)
                    .frame(width: 64)
                Button("Apply", action: applyDestination)
            }
            .textFieldStyle(.roundedBorder)

            if !model.bonjour.receivers.isEmpty {
                Menu("Discovered receivers") {
                    ForEach(model.bonjour.receivers) { receiver in
                        Button(receiver.name) { select(receiver) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            let counters = model.forwarder.counters
            Text("Forwarded \(counters.sent) · errors \(counters.errors)")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 360)
        .onAppear {
            hostText = settings.forwardHost
            portText = String(settings.forwardPort)
            model.bonjour.start()
        }
    }

    private func select(_ receiver: DiscoveredReceiver) {
        Task {
            guard let result = await model.bonjour.resolve(receiver) else { return }
            hostText = result.host
            portText = String(result.port)
            applyDestination()
        }
    }

    private func applyDestination() {
        model.settings.forwardHost = hostText.trimmingCharacters(in: .whitespaces)
        if let port = UInt16(portText), port > 0 { model.settings.forwardPort = port }
        model.applyForwarding()
    }
}
