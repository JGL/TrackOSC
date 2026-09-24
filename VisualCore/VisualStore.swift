//
//  VisualStore.swift
//  TrackOSC (VisualCore)
//
//  The state of a visual app: the receiver model, the scene builder, the
//  mode catalogue with per-mode parameters, palette, presets, display
//  settings, keyboard shortcuts, screenshots and frame statistics.
//

import AppKit
import Foundation
import MetalKit
import Observation
import PoseioscShared

@Observable @MainActor
final class VisualStore {
    let app: TrackOSCApp
    let model: ReceiverModel
    let builder = SceneBuilder()
    let display = DisplaySettings()
    let presets: PresetStore
    let renderer: MetalRenderer?
    let modes: [VisualMode]

    /// Always a valid index into `modes` (set through `selectMode`).
    private(set) var modeIndex: Int
    var mode: VisualMode { modes[modeIndex] }

    func selectMode(_ index: Int) {
        let clamped = min(max(index, 0), modes.count - 1)
        guard clamped != modeIndex else { return }
        modeIndex = clamped
        UserDefaults.standard.set(modes[clamped].id, forKey: "mode")
        modeChangedAt = Date()
    }
    /// Parameter values per mode id.
    var params: [String: ParameterValues] = [:] {
        didSet { scheduleSave() }
    }
    var palette: Palette {
        didSet { if let data = try? JSONEncoder().encode(palette) { UserDefaults.standard.set(data, forKey: "palette") } }
    }
    private(set) var stats = FrameStats()
    private(set) var lastScreenshot: URL?
    private(set) var modeChangedAt = Date.distantPast
    var rendererError: String? { renderer?.lastError }

    private var keyMonitor: Any?
    private var saveTask: Task<Void, Never>?
    private var lastShuffle = Date()

    init(app: TrackOSCApp, modes: [VisualMode]) {
        self.app = app
        self.modes = modes
        model = ReceiverModel(app: app)
        presets = PresetStore(appFolder: app.displayName)
        renderer = MetalRenderer()
        let storedMode = UserDefaults.standard.string(forKey: "mode")
        modeIndex = modes.firstIndex { $0.id == storedMode } ?? 0
        if let data = UserDefaults.standard.data(forKey: "palette"), let stored = try? JSONDecoder().decode(Palette.self, from: data) {
            palette = stored
        } else {
            palette = .default
        }
        if let data = UserDefaults.standard.data(forKey: "params"), let stored = try? JSONDecoder().decode([String: ParameterValues].self, from: data) {
            params = stored
        }
        for mode in modes where params[mode.id] == nil {
            params[mode.id] = mode.parameters.defaults
        }
        builder.mirror = display.mirror
        builder.smoothing = display.smoothing
        builder.attractDelay = display.attractDelay
        installKeyMonitor()
    }

    // MARK: - Per frame

    func currentInputs(for mode: VisualMode) -> RenderInputs {
        RenderInputs(
            fragment: mode.fragment,
            params: mode.parameters.packed(params[mode.id] ?? [:], count: Int(VC_MAX_PARAMS)),
            palette: palette,
            fitMode: display.fitMode,
            vignette: display.vignette,
            grain: display.grain,
            gamma: display.gamma,
            usesFeedback: mode.usesFeedback
        )
    }

    func renderFrame(in view: MTKView) {
        guard let renderer else { return }
        let started = CACurrentMediaTime()
        builder.mirror = display.mirror
        builder.smoothing = display.smoothing
        builder.attractDelay = display.attractDelay
        let scene = builder.update(latest: model.latest)
        let scale = CGFloat(min(max(display.renderScale, 0.25), 1))
        let wanted = CGSize(width: view.bounds.width * view.window!.backingScaleFactor * scale,
                            height: view.bounds.height * view.window!.backingScaleFactor * scale)
        if abs(view.drawableSize.width - wanted.width) > 1 || abs(view.drawableSize.height - wanted.height) > 1 {
            view.drawableSize = wanted
        }
        if display.autoShuffle > 0, Date().timeIntervalSince(lastShuffle) > Double(display.autoShuffle) {
            lastShuffle = Date()
            nextMode()
        }
        renderer.draw(scene: scene, inputs: currentInputs(for: mode), in: view)
        stats.record(cpuSeconds: CACurrentMediaTime() - started, at: CACurrentMediaTime())
    }

    // MARK: - Actions

    func nextMode() { selectMode((modeIndex + 1) % modes.count) }
    func previousMode() { selectMode((modeIndex - 1 + modes.count) % modes.count) }

    func randomise() {
        params[mode.id] = mode.parameters.randomised()
        palette = Palette.curated.randomElement() ?? .default
    }

    func resetParameters() {
        params[mode.id] = mode.parameters.defaults
    }

    func loadPreset(_ slot: Int) {
        guard let preset = presets.slots[safe: slot] ?? nil else { return }
        if let index = modes.firstIndex(where: { $0.id == preset.mode }) { selectMode(index) }
        params[preset.mode] = preset.params
        palette = preset.palette
    }

    func savePreset(_ slot: Int, name: String? = nil) {
        presets.save(VisualPreset(name: name ?? "\(mode.name) \(slot + 1)", mode: mode.id, params: params[mode.id] ?? [:], palette: palette), in: slot)
    }

    /// Renders the current mode at the window's size and writes a PNG to Downloads.
    func screenshot() {
        guard let renderer else { return }
        let scene = builder.scene
        let window = NSApp.keyWindow
        let size = window?.contentView?.bounds.size ?? CGSize(width: 1920, height: 1080)
        let scale = window?.backingScaleFactor ?? 2
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard width > 0, height > 0, let image = renderer.snapshot(scene: scene, inputs: currentInputs(for: mode), width: width, height: height) else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let url = downloads.appendingPathComponent("\(app.displayName) \(mode.name) \(formatter.string(from: .now)).png")
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
            lastScreenshot = url
        }
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Leave typing alone.
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView || responder is NSTextField { return event }
            if event.modifierFlags.contains(.command) { return event }
            let shift = event.modifierFlags.contains(.shift)
            switch event.keyCode {
            case 49: randomise()                       // space
            case 123: previousMode()                   // ←
            case 124: nextMode()                       // →
            case 15: resetParameters()                 // R
            case 1: screenshot()                       // S
            case 4, 48: model.fullScreen.toggleGUI()   // H, Tab
            case 3: model.fullScreen.toggleFullScreen()// F
            case 18...25, 29:                          // 1–9 (key codes for 1…9 are 18,19,20,21,23,22,26,28,25)
                let digits: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
                guard let slot = digits[event.keyCode] else { return event }
                if shift { savePreset(slot) } else { loadPreset(slot) }
            default: return event
            }
            return nil
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled, let data = try? JSONEncoder().encode(params) else { return }
            UserDefaults.standard.set(data, forKey: "params")
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
