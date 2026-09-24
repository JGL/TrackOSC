//
//  InspectorPanel.swift
//  TrackOSC Costumes (macOS)
//
//  What the current costume contains, which layers are placed right now,
//  and the parser's warnings.
//

import CostumeCore
import SwiftUI

struct InspectorPanel: View {
    @Bindable var store: CostumesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let costume = store.costume {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(costume.name).font(.headline)
                        Text(costume.summary).font(.caption).foregroundStyle(.secondary)
                        Text("viewBox \(Int(costume.document.viewBox.width)) \u{00D7} \(Int(costume.document.viewBox.height)), \(costume.guides.count) guide\(costume.guides.count == 1 ? "" : "s")")
                            .font(.caption2).foregroundStyle(.tertiary)
                        if store.scene.isLive {
                            Text(store.isFacingAway ? "Facing away (mirrored)" : "Facing the camera").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !costume.warnings.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(costume.warnings.enumerated()), id: \.offset) { _, warning in
                                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption)
                                }
                            }
                        } label: { Text("Warnings").foregroundStyle(.orange) }
                    }
                    GroupBox("Layers") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(costume.layers) { layer in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(store.liveLayers.contains(layer.id) ? Color.green : Color.primary.opacity(0.15))
                                        .frame(width: 7, height: 7)
                                    Text(layer.label).font(.caption.monospaced()).lineLimit(1)
                                    Spacer()
                                    Text(roleName(layer.name.role)).font(.caption2).foregroundStyle(.secondary)
                                    if layer.pivot != nil { Image(systemName: "line.diagonal").font(.caption2).foregroundStyle(.tertiary).help("Has a pivot") }
                                }
                            }
                        }
                    }
                    incoming
                } else {
                    Text(store.loadError ?? "No costume selected.").foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private var incoming: some View {
        GroupBox("Arriving") {
            VStack(alignment: .leading, spacing: 3) {
                row("Bodies", store.scene.persons.count)
                row("Hands", store.scene.hands.count)
                row("Faces", store.scene.faces.count, note: store.scene.faces.contains { $0.landmarks.count >= 76 } ? "with landmarks" : nil)
                if store.scene.isAttract { Text("Attract figure").font(.caption).foregroundStyle(.secondary) }
                Text("Face parts need the Face Landmarks detector; hand parts need Hands. Without them they follow the head and the wrists.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ name: String, _ count: Int, note: String? = nil) -> some View {
        HStack {
            Text(name).font(.caption)
            Spacer()
            if let note, count > 0 { Text(note).font(.caption2).foregroundStyle(.secondary) }
            Text("\(count)").font(.caption.monospaced()).foregroundStyle(count > 0 ? .primary : .tertiary)
        }
    }

    private func roleName(_ role: LayerRole) -> String {
        switch role {
        case .bone(let bone, let side): "\(bone.rawValue)\(side.map { " \($0.rawValue)" } ?? "")"
        case .head: "head"
        case .face(let part): "face \(part.rawValue)"
        case .hand(let part, let phalanx, let side): "hand \(part.rawValue)\(phalanx.map { " \($0)" } ?? "")\(side == .any ? "" : " \(side.rawValue)")"
        case .guide(let g): "guide \(g)"
        case .pivot: "pivot"
        case .scenery: "scenery"
        }
    }
}

struct DisplayPanel: View {
    @Bindable var store: CostumesStore

    var body: some View {
        Form {
            Section("Stage") {
                Toggle("Mirror (like a mirror on the wall)", isOn: $store.mirror)
                Picker("Frame", selection: $store.fit) {
                    ForEach(StageFit.allCases) { Text($0.label).tag($0) }
                }
                ColorPicker("Background", selection: Binding(get: { store.model.settings.stageBackground }, set: { store.model.settings.stageBackground = $0 }), supportsOpacity: false)
                Toggle("Show the tracked skeleton", isOn: $store.showSkeleton)
            }
            Section("Motion") {
                LabeledContent("Smoothing") {
                    Slider(value: $store.smoothing, in: 0...0.4)
                }
                LabeledContent("Fade when a part is lost") {
                    HStack {
                        Slider(value: $store.fadeSeconds, in: 0...1.5)
                        Text(String(format: "%.1f s", store.fadeSeconds)).font(.caption.monospaced()).frame(width: 36)
                    }
                }
                LabeledContent("Attract figure after") {
                    HStack {
                        Slider(value: $store.attractDelay, in: 0...120, step: 5)
                        Text(store.attractDelay == 0 ? "never" : "\(Int(store.attractDelay)) s").font(.caption.monospaced()).frame(width: 44)
                    }
                }
            }
            Section("Recording") {
                if store.recorder.isRecording {
                    Text(String(format: "Recording\u{2026} %.0f s, %d frames", store.recorder.duration, store.recorder.frameCount)).foregroundStyle(.red)
                } else if let url = store.recorder.lastRecording {
                    HStack {
                        Text("Saved \(url.lastPathComponent)").font(.caption).lineLimit(1)
                        Spacer()
                        Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.controlSize(.small)
                    }
                }
                if let error = store.recorder.lastError { Text(error).font(.caption).foregroundStyle(.red) }
                Text("V records the stage to an .mp4 in Downloads at the window's size.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
