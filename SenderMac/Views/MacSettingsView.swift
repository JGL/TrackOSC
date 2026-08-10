//
//  MacSettingsView.swift
//  Poseiosc Sender (macOS)
//
//  Destination (Bonjour-discovered or manual), camera selection, rig
//  rotation, mirror, and statistics.
//

import SwiftUI
import PoseioscShared

struct MacSettingsView: View {
    @Bindable var model: MacAppModel
    @Environment(\.dismiss) private var dismiss

    @State private var hostText = ""
    @State private var portText = ""
    @State private var resolvingReceiver: String?
    @State private var resolveFailed = false

    var body: some View {
        @Bindable var settings = model.settings
        VStack(spacing: 0) {
            Form {
                Section("Discovered receivers") {
                    if model.bonjour.receivers.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching for receivers on this network…")
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
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
                                        .controlSize(.small)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if resolveFailed {
                        Text("Could not resolve that receiver — enter its address manually below.")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                Section("Destination") {
                    TextField("Host or IP", text: $hostText, prompt: Text("e.g. 192.168.1.20 (or 127.0.0.1 for this Mac)"))
                    TextField("Port", text: $portText)
                    Button("Apply", action: applyDestination)
                }

                Section("Camera") {
                    Picker("Camera", selection: cameraSelection) {
                        ForEach(model.cameras) { camera in
                            Text(camera.name).tag(camera.id)
                        }
                    }
                    Picker("Rig rotation", selection: $settings.rotationDegrees) {
                        Text("0° (normal)").tag(0)
                        Text("90°").tag(90)
                        Text("180°").tag(180)
                        Text("270°").tag(270)
                    }
                    Text("For cameras mounted rotated. iPhones via Continuity Camera also appear in the camera list.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Toggle("Mirror preview", isOn: $settings.mirrorPreview)
                    Text("Display-only — OSC coordinates are always unmirrored.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Toggle("Hide video preview", isOn: $settings.hideVideoPreview)
                    Text("Shows only the tracking overlay on black. The camera and OSC output keep running.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("Statistics") {
                    LabeledContent("Messages sent", value: "\(model.sentCount)")
                    LabeledContent("Processed", value: "\(Int(model.processedFPS)) fps")
                    LabeledContent("Frame", value: frameDescription)
                    LabeledContent("App version", value: appVersion)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Done") {
                    applyDestination()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 560)
        .onAppear {
            hostText = model.settings.host
            portText = String(model.settings.port)
        }
        .onChange(of: model.settings.rotationDegrees) {
            model.applySettings()
        }
    }

    private var cameraSelection: Binding<String> {
        Binding(
            get: { model.settings.cameraID ?? model.camera.currentDeviceID ?? "" },
            set: { model.selectCamera(id: $0) }
        )
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

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
