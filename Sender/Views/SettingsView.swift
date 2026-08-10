//
//  SettingsView.swift
//  Poseiosc Sender (iOS)
//
//  Destination configuration: Bonjour-discovered receivers plus manual entry.
//

import SwiftUI
import PoseioscShared

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var hostText = ""
    @State private var portText = ""
    @State private var resolvingReceiver: String?
    @State private var resolveFailed = false

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                Section("Discovered receivers") {
                    if model.bonjour.receivers.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Searching for receivers on this network…")
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                    }
                    ForEach(model.bonjour.receivers) { receiver in
                        Button {
                            select(receiver)
                        } label: {
                            HStack {
                                Label(receiver.name, systemImage: "dot.radiowaves.left.and.right")
                                Spacer()
                                if resolvingReceiver == receiver.name {
                                    ProgressView()
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    if resolveFailed {
                        Text("Could not resolve that receiver — enter its address manually below.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Destination") {
                    TextField("Host or IP (e.g. 192.168.1.20)", text: $hostText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)
                    Button("Apply") {
                        applyDestination()
                    }
                }

                Section("Camera") {
                    Picker("Orientation", selection: $settings.cameraOrientation) {
                        ForEach(CameraOrientationSetting.allCases) { setting in
                            Text(setting.label).tag(setting)
                        }
                    }
                    Text("Lock the orientation when the phone is mounted (tripod, flat rig) — automatic detection relies on gravity and fails when the phone lies flat. If a locked landscape preview appears upside down, pick the other landscape option.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: settings.cameraOrientation) {
                    model.applySettings()
                }

                Section("Preview") {
                    Toggle("Mirror selfie preview", isOn: $settings.mirrorFrontPreview)
                    Text("Front camera only. Display-only — the OSC coordinates sent to receivers are always unmirrored.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("Hide video preview", isOn: $settings.hideVideoPreview)
                    Text("Shows only the tracking overlay on black. The camera and OSC output keep running.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Statistics") {
                    LabeledContent("Messages sent", value: "\(model.sentCount)")
                    LabeledContent("Processed", value: "\(Int(model.processedFPS)) fps")
                    LabeledContent("Frame", value: frameDescription)
                    LabeledContent("App version", value: appVersion)
                }

                Section {
                    Text("Default port 9527 matches VisionOSC. The macOS TrackOSC Receiver listens on that port; other OSC tools (TouchDesigner, Max/MSP, Processing) can receive on any port you set here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyDestination()
                        dismiss()
                    }
                }
            }
            .onAppear {
                hostText = model.settings.host
                portText = String(model.settings.port)
            }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// e.g. "720×1280 · 90° portrait" — mirrors what /camerainfo broadcasts.
    private var frameDescription: String {
        let snapshot = model.overlay
        guard snapshot.width > 0 else { return "—" }
        let info = CameraInfo(
            width: snapshot.width, height: snapshot.height,
            orientationDegrees: snapshot.rotationDegrees,
            facing: snapshot.isFrontCamera ? 1 : 0
        )
        return "\(info.width)×\(info.height) · \(info.orientationDegrees)° \(info.orientationName)"
    }

    private func select(_ receiver: DiscoveredReceiver) {
        resolvingReceiver = receiver.name
        resolveFailed = false
        Task {
            let result = await model.bonjour.resolve(receiver)
            resolvingReceiver = nil
            guard let result else {
                resolveFailed = true
                return
            }
            hostText = result.host
            portText = String(result.port)
            applyDestination()
        }
    }

    private func applyDestination() {
        model.settings.host = hostText.trimmingCharacters(in: .whitespaces)
        if let port = UInt16(portText), port > 0 {
            model.settings.port = port
        } else {
            portText = String(model.settings.port)
        }
        model.applySettings()
    }
}
