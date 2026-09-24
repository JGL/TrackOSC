//
//  ConnectionToolbar.swift
//  TrackOSC (ReceiverCore)
//
//  Listening status, port, Restart, the advertised Bonjour name and the
//  forwarding popover – the same in every receiver-type app.
//

import AppKit
import PoseioscShared
import SwiftUI

struct ConnectionToolbar: ToolbarContent {
    @Bindable var model: ReceiverModel
    @State private var portText = ""
    @State private var showForwarding = false
    @State private var showSenders = false

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

            Button {
                showSenders.toggle()
            } label: {
                Label("Senders", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(model.settings.sourcePolicy == .all ? Color.primary : Color.accentColor)
            }
            .help("Which sender is heard when several send to this port")
            .popover(isPresented: $showSenders) {
                SendersPopover(model: model)
            }

            ColorPicker("Background", selection: Binding(
                get: { model.settings.stageBackground },
                set: { model.settings.stageBackground = $0 }
            ), supportsOpacity: false)
            .labelsHidden()
            .help("Stage background colour (also the window's colour in full screen)")

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

/// Source selection: which host is heard, with the hosts seen recently.
struct SendersPopover: View {
    @Bindable var model: ReceiverModel
    @State private var hostText = ""

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 10) {
            Picker("Listen to", selection: $settings.sourcePolicy) {
                ForEach(SourcePolicy.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: settings.sourcePolicy) { model.applySourcePolicy() }
            Text(settings.sourcePolicy.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if settings.sourcePolicy == .only {
                HStack {
                    TextField("Host", text: $hostText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(applyHost)
                    Button("Apply", action: applyHost)
                }
            }

            if !model.recentHosts.isEmpty {
                Text("Heard from in the last minute").font(.subheadline)
                ForEach(model.recentHosts, id: \.self) { host in
                    HStack {
                        Circle()
                            .fill(host == model.activeHost ? .green : .gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text(host).font(.system(.body, design: .monospaced))
                        Spacer()
                        if settings.sourcePolicy == .only {
                            Button("Use") { hostText = host; applyHost() }.controlSize(.small)
                        }
                    }
                }
            }
            Text("Ignored \(model.ignoredMessages) messages from other senders")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            Divider()
            Text("Not appearing on the phone?").font(.subheadline)
            Text("Each app needs its own Local Network permission before senders can discover it. Check System Settings → Privacy & Security → Local Network, and that the sender targets port \(String(model.effectivePort)).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Local Network settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        .padding()
        .frame(width: 360)
        .onAppear { hostText = settings.sourceHost }
    }

    private func applyHost() {
        model.settings.sourceHost = hostText.trimmingCharacters(in: .whitespaces)
        model.applySourcePolicy()
    }
}
