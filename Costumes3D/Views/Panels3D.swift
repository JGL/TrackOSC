//
//  Panels3D.swift
//  TrackOSC 3D Costumes (macOS)
//

import Costume3DCore
import SwiftUI

struct Library3DPanel: View {
    @Bindable var store: Costumes3DStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(get: { store.selectedID }, set: { id in
                if let id, let entry = store.library.entries.first(where: { $0.id == id }) { store.select(entry) }
            })) {
                Section("Built in") {
                    ForEach(store.library.bundled) { entry in row(entry) }
                }
                Section(store.library.folderURL?.lastPathComponent ?? "Your folder") {
                    if store.library.folderURL == nil {
                        Text("Choose a folder: rigged models (.usdz) and sub-folders of parts.").font(.caption).foregroundStyle(.secondary)
                    } else if store.library.user.isEmpty {
                        Text("No models in this folder yet.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(store.library.user) { entry in row(entry) }
                }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Button("Choose Folder\u{2026}") { store.library.chooseFolder() }
                if store.library.folderURL != nil {
                    Button("Reveal") { store.library.revealFolder() }
                    Button("Forget") { store.library.forgetFolder() }
                }
                Spacer()
                Link(destination: URL(string: "https://developer.apple.com/documentation/arkit/validating-a-model-for-motion-capture")!) {
                    Label("Apple's rig", systemImage: "figure.stand")
                }
                .help("Apple's motion-capture skeleton, with the Biped Robot sample to download")
            }
            .controlSize(.small)
            .padding(8)
            if let error = store.library.folderError {
                Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 8).padding(.bottom, 6)
            }
            VStack(alignment: .leading, spacing: 6) {
                Picker("People", selection: $store.assignment) {
                    ForEach(Costume3DAssignment.allCases) { Text($0.label).tag($0) }
                }
                Text("Keys: [ and ] change costume, 1\u{2013}9 pick one, M mirror, G gnomon, 0 reset view, R reload.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .padding(8)
        }
    }

    private func row(_ entry: Costume3DEntry) -> some View {
        HStack {
            Image(systemName: icon(entry.kind)).foregroundStyle(entry.id == store.selectedID ? Color.accentColor : .secondary)
            Text(entry.name)
            Spacer()
            if let index = store.library.entries.firstIndex(of: entry), index < 9 {
                Text("\(index + 1)").font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
        }
        .tag(entry.id)
    }

    private func icon(_ kind: Costume3DKind) -> String {
        switch kind {
        case .mannequin: "figure.stand"
        case .blocks: "cube"
        case .rigged: "figure.walk"
        case .parts: "folder"
        }
    }
}

struct RigPanel: View {
    @Bindable var store: Costumes3DStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let entry = store.selectedEntry {
                    Text(entry.name).font(.headline)
                    Text(store.isLoading ? "Loading\u{2026}" : store.currentSummary).font(.caption).foregroundStyle(.secondary)
                    if store.poseCount == 0 {
                        Text("Nothing is worn until a 3D body arrives.").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                if !store.currentWarnings.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(store.currentWarnings.enumerated()), id: \.offset) { _, warning in
                                Label(warning, systemImage: "exclamationmark.triangle").font(.caption)
                            }
                        }
                    } label: { Text("Warnings").foregroundStyle(.orange) }
                }
                GroupBox("Apple's motion-capture rig") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A rigged model needs these \(AppleRig.joints.count) joints in this hierarchy, T-posed, +Y up, facing +Z, the left hand along +X, each joint's +X down its bone. TrackOSC drives \(AppleRig.driven.count) of them from the 17-joint stream; the rest may be unskinned.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(AppleRig.driven.joined(separator: ", ")).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    }
                }
                GroupBox("Parts folders") {
                    Text("One model per bone, named " + PartBone.allCases.map(\.rawValue).joined(separator: ", ") + ". The longest axis is laid along the bone, top to bottom.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Button("Show the models README") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.url(forResource: "README", withExtension: "md") ?? Bundle.main.bundleURL])
                }
                .controlSize(.small)
            }
            .padding()
        }
    }
}

struct Display3DPanel: View {
    @Bindable var store: Costumes3DStore

    var body: some View {
        Form {
            Section("Stage") {
                Toggle("Mirror (like a mirror on the wall)", isOn: $store.mirror)
                Toggle("Axis gnomon and camera marker", isOn: $store.showGnomon)
                ColorPicker("Background", selection: Binding(get: { store.model.settings.stageBackground }, set: { store.model.settings.stageBackground = $0 }), supportsOpacity: false)
                Button("Reset View") { store.resetView() }
            }
            Section("Motion") {
                LabeledContent("Smoothing") {
                    HStack {
                        Slider(value: $store.smoothing, in: 0...0.5)
                        Text(String(format: "%.2f s", store.smoothing)).font(.caption.monospaced()).frame(width: 44)
                    }
                }
                LabeledContent("Fade when a body is lost") {
                    HStack {
                        Slider(value: $store.fadeSeconds, in: 0...2)
                        Text(String(format: "%.1f s", store.fadeSeconds)).font(.caption.monospaced()).frame(width: 36)
                    }
                }
            }
            Section {
                Text("Units are metres from /poses3d/arr: x right, y up, z Vision camera space, the camera marker at the origin. The floor settles under the lowest ankle.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
