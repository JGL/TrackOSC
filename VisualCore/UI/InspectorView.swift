//
//  InspectorView.swift
//  TrackOSC (VisualCore)
//
//  The controls column every visual app shares: Look (mode, parameters,
//  palette), Display, Presets and Status.
//

import AppKit
import SwiftUI

struct InspectorView: View {
    @Bindable var store: VisualStore

    var body: some View {
        TabView {
            Tab("Look", systemImage: "paintpalette") {
                ScrollView { LookPanel(store: store).padding() }
            }
            Tab("Display", systemImage: "display") {
                ScrollView { DisplayPanel(store: store).padding() }
            }
            Tab("Presets", systemImage: "square.grid.3x3") {
                ScrollView { PresetsPanel(store: store).padding() }
            }
            Tab("Status", systemImage: "waveform.path.ecg") {
                VStack(spacing: 0) {
                    FrameStatsRow(store: store)
                    Divider()
                    ReceiverStatusView(model: store.model)
                }
            }
        }
    }
}

struct LookPanel: View {
    @Bindable var store: VisualStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mode").font(.headline)
                Spacer()
                Button { store.previousMode() } label: { Image(systemName: "chevron.left") }
                Button { store.nextMode() } label: { Image(systemName: "chevron.right") }
                Button("Randomise") { store.randomise() }
            }
            Picker("Mode", selection: Binding(get: { store.modeIndex }, set: { store.selectMode($0) })) {
                ForEach(Array(store.modes.enumerated()), id: \.offset) { index, mode in
                    Text(mode.name).tag(index)
                }
            }
            .labelsHidden()
            Text(store.mode.blurb)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            HStack {
                Text("Parameters").font(.headline)
                Spacer()
                Button("Reset") { store.resetParameters() }.controlSize(.small)
            }
            ForEach(store.mode.parameters) { spec in
                let binding = Binding<Float>(
                    get: { store.params[store.mode.id]?[spec.id] ?? spec.defaultValue },
                    set: { store.params[store.mode.id, default: [:]][spec.id] = $0 }
                )
                HStack {
                    Text(spec.name).frame(width: 110, alignment: .leading)
                    Slider(value: binding, in: spec.range)
                    Text(Self.format(binding.wrappedValue) + spec.unit)
                        .font(.system(.callout, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)
                }
            }

            Divider()
            PalettePanel(store: store)

            Divider()
            Text("Keys: ←/→ mode · Space randomise · R reset · 1–9 presets (⇧ saves) · S screenshot · H controls · F full screen")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func format(_ v: Float) -> String {
        abs(v) >= 10 ? String(format: "%.1f", v) : String(format: "%.3f", v)
    }
}

struct PalettePanel: View {
    @Bindable var store: VisualStore
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Palette").font(.headline)
                Spacer()
                Toggle("Edit", isOn: $editing).toggleStyle(.button).controlSize(.small)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                ForEach(Palette.curated) { palette in
                    Button {
                        store.palette = palette
                    } label: {
                        VStack(spacing: 3) {
                            PaletteStrip(palette: palette).frame(height: 18)
                            Text(palette.name).font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .background(store.palette.name == palette.name ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 6))
                }
            }
            PaletteStrip(palette: store.palette).frame(height: 24)
            if editing {
                TextField("Name", text: $store.palette.name).textFieldStyle(.roundedBorder)
                ForEach(store.palette.stops.indices, id: \.self) { index in
                    HStack {
                        ColorPicker("Stop \(index + 1)", selection: Binding(
                            get: { store.palette.stops[index].color },
                            set: { store.palette.stops[index] = RGB($0) }
                        ), supportsOpacity: false)
                        Spacer()
                        Button { store.palette.stops.remove(at: index) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .disabled(store.palette.stops.count <= 2)
                    }
                }
                Button("Add stop") {
                    store.palette.stops.append(store.palette.stops.last ?? RGB(1, 1, 1))
                }
                .disabled(store.palette.stops.count >= Palette.maxStops)
            }
        }
    }
}

struct PaletteStrip: View {
    let palette: Palette

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { i in
                    palette.color(at: Float(i) / 24).color
                        .frame(width: geometry.size.width / 24)
                }
            }
            .clipShape(.rect(cornerRadius: 4))
        }
    }
}

struct DisplayPanel: View {
    @Bindable var store: VisualStore

    var body: some View {
        @Bindable var display = store.display
        VStack(alignment: .leading, spacing: 12) {
            Text("Scene").font(.headline)
            Toggle("Mirror (selfie style)", isOn: $display.mirror).toggleStyle(.checkbox)
            Picker("Frame", selection: $display.fitMode) {
                ForEach(FitMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            labelled("Smoothing", String(format: "%.2f s", display.smoothing)) { Slider(value: $display.smoothing, in: 0...0.5) }
            labelled("Attract after", display.attractDelay == 0 ? "off" : "\(Int(display.attractDelay)) s") { Slider(value: $display.attractDelay, in: 0...120, step: 5) }
            Text("With no one tracked for that long, a synthetic figure wanders so the screen never looks dead.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            labelled("Auto-shuffle", display.autoShuffle == 0 ? "off" : "\(Int(display.autoShuffle)) s") { Slider(value: $display.autoShuffle, in: 0...300, step: 10) }

            Divider()
            Text("Render").font(.headline)
            labelled("Resolution", "\(Int(display.renderScale * 100))%") { Slider(value: $display.renderScale, in: 0.25...1, step: 0.05) }
            labelled("Vignette", String(format: "%.2f", display.vignette)) { Slider(value: $display.vignette, in: 0...1) }
            labelled("Grain", String(format: "%.2f", display.grain)) { Slider(value: $display.grain, in: 0...0.3) }
            labelled("Gamma", String(format: "%.2f", display.gamma)) { Slider(value: $display.gamma, in: 0.5...2) }
            Toggle("Show the mode name when it changes", isOn: $display.showModeName).toggleStyle(.checkbox)
            ColorPicker("Background (empty areas, full screen)", selection: Binding(
                get: { store.model.settings.stageBackground },
                set: { store.model.settings.stageBackground = $0 }
            ), supportsOpacity: false)
        }
    }

    private func labelled<Content: View>(_ label: String, _ value: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).frame(width: 100, alignment: .leading)
            content()
            Text(value).font(.system(.callout, design: .monospaced)).frame(width: 56, alignment: .trailing)
        }
    }
}

struct PresetsPanel: View {
    @Bindable var store: VisualStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presets").font(.headline)
            Text("Nine slots: keys 1–9 load, ⇧1–9 save the current mode, parameters and palette.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(0..<PresetStore.slotCount, id: \.self) { slot in
                HStack {
                    Text("\(slot + 1)").font(.system(.body, design: .monospaced)).frame(width: 20)
                    if let preset = store.presets.slots[slot] {
                        Text(preset.name).lineLimit(1)
                        Spacer()
                        Button("Load") { store.loadPreset(slot) }.controlSize(.small)
                        Button("Save") { store.savePreset(slot) }.controlSize(.small)
                        Button { store.presets.clear(slot) } label: { Image(systemName: "trash") }.controlSize(.small)
                    } else {
                        Text("empty").foregroundStyle(.tertiary)
                        Spacer()
                        Button("Save") { store.savePreset(slot) }.controlSize(.small)
                    }
                }
            }
            Divider()
            HStack {
                Button("Screenshot") { store.screenshot() }
                if let url = store.lastScreenshot {
                    Text(url.lastPathComponent).font(.footnote).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Text("Screenshots go to Downloads at the window's resolution.")
                .font(.footnote).foregroundStyle(.secondary)
            Divider()
            RecordingRow(store: store)
        }
    }
}

struct FrameStatsRow: View {
    let store: VisualStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            HStack {
                Text(String(format: "%.0f fps · %.1f ms CPU", store.stats.fps, store.stats.frameMilliseconds))
                Spacer()
                let scene = store.builder.scene
                Text("\(scene.persons.count) people · \(scene.hands.count) hands · \(scene.faces.count) faces" + (scene.isAttract ? " · attract" : ""))
            }
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(10)
        }
    }
}

struct RecordingRow: View {
    let store: VisualStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button(store.recorder.isRecording ? "Stop Recording" : "Record Video") { store.toggleRecording() }
                    if store.recorder.isRecording {
                        Circle().fill(.red).frame(width: 9, height: 9)
                        Text(String(format: "%.0f s · %d frames", store.recorder.duration, store.recorder.frameCount))
                            .font(.system(.callout, design: .monospaced))
                    }
                }
                if let url = store.recorder.lastRecording, !store.recorder.isRecording {
                    HStack {
                        Text(url.lastPathComponent).font(.footnote).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.controlSize(.small)
                    }
                }
                if let error = store.recorder.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                Text("H.264 .mp4 at the window's resolution, 60 fps, to Downloads – ready to post. Key: V.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
