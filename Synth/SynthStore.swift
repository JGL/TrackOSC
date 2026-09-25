//
//  SynthStore.swift
//  TrackOSC Synth (macOS)
//
//  The app's state: the receiver model and scene builder, the audio host,
//  MIDI out, the mappings that connect tracking to the instrument, the UI
//  mirror of every knob and pattern, presets, and a 60 Hz tick that reads
//  sources, applies mappings and drains the graph's triggers.
//

import AppKit
import AVFoundation
import Foundation
import Observation
import PoseioscShared
import SynthCore

@Observable @MainActor
final class SynthStore {
    let model = ReceiverModel(app: .synth)
    let builder = SceneBuilder()
    let host = AudioHost()
    let midi = SynthMIDI()

    // UI mirrors (the audio thread reads the bank and the graph's own copy).
    private(set) var values: [ParameterID: Float] = [:]
    var patterns: [StepPattern] = Array(repeating: StepPattern(), count: 8)
    private(set) var patternIndex = 0
    private(set) var isPlaying = false
    var conductorMode = false { didSet { host.events.push(.setConductor(conductorMode)) } }
    var continuous: [ContinuousMapping] = [] { didSet { scheduleSave() } }
    var events: [EventMapping] = [] { didSet { scheduleSave() } }
    var mappingsEnabled = true { didSet { UserDefaults.standard.set(mappingsEnabled, forKey: "mappingsEnabled") } }

    // Display-rate readouts.
    private(set) var peak: Float = 0
    private(set) var step = -1
    private(set) var lastDrumHits: [DrumVoiceKind: Date] = [:]
    private(set) var lastBassNote: Int?
    private(set) var readings = SourceReadings()
    private(set) var scene = TrackingScene.empty
    private(set) var mappedValues: [UUID: Float] = [:]
    private(set) var eventFlashes: [UUID: Date] = [:]
    private(set) var currentPresetName = "Acid theremin"
    private(set) var userPresets: [SynthPreset] = []
    private(set) var outputDevices: [OutputDevice] = []
    var selectedOutputDevice: AudioDeviceID? { didSet { applyOutputDevice() } }
    var liveInputNote = ""

    private var smoothers: [UUID: MappingSmoother] = [:]
    private var detectors: [UUID: EdgeDetector] = [:]
    private var lastCC: [UUID: Int] = [:]
    private var lastCode: String?
    private var lastPersonCount = 0
    private var lastStep = -1
    private var codeChangedAt: Date?
    private var tickTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var clockAccumulator: Double = 0
    private let start = Date()

    static let presetsFolder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("TrackOSC Synth/Presets", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    init() {
        for id in ParameterID.allCases { values[id] = id.defaultValue }
        mappingsEnabled = UserDefaults.standard.object(forKey: "mappingsEnabled") as? Bool ?? true
        builder.attractDelay = 0
        host.start()
        outputDevices = OutputDevices.all()
        selectedOutputDevice = OutputDevices.defaultDevice()
        loadUserPresets()
        if let saved = Self.loadState() {
            apply(saved, name: UserDefaults.standard.string(forKey: "presetName") ?? "Saved state")
        } else {
            apply(SynthPreset.builtIn[0], name: SynthPreset.builtIn[0].name)
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self else { return }
                tick()
            }
        }
    }

    // MARK: - Parameters and patterns

    func set(_ id: ParameterID, _ value: Float) {
        let clamped = min(max(value, id.range.lowerBound), id.range.upperBound)
        values[id] = clamped
        host.parameters.set(id, clamped)
        scheduleSave()
    }

    func value(_ id: ParameterID) -> Float { values[id] ?? id.defaultValue }

    func togglePlay() {
        isPlaying.toggle()
        if isPlaying { host.play() } else { host.stopSequencer() }
        midi.transport(playing: isPlaying)
    }

    func selectPattern(_ index: Int) {
        patternIndex = min(max(index, 0), patterns.count - 1)
        host.events.push(.selectPattern(patternIndex))
    }

    func toggleDrum(_ kind: DrumVoiceKind, step: Int) {
        patterns[patternIndex].toggleDrum(kind, at: step)
        host.events.push(.toggleDrumStep(kind, step))
        scheduleSave()
    }

    func setBassStep(_ step: Int, _ value: BassStep) {
        patterns[patternIndex].bass[step] = value
        host.events.push(.setBassStep(step, value))
        scheduleSave()
    }

    func clearPattern() {
        patterns[patternIndex] = StepPattern()
        host.events.push(.setPattern(patternIndex, patterns[patternIndex]))
        scheduleSave()
    }

    func randomisePattern() {
        var p = StepPattern()
        let notes = [36, 36, 36, 39, 41, 43, 46, 48]
        for s in 0..<StepPattern.steps {
            if Bool.random() || s % 4 == 0 {
                p.bass[s] = BassStep(note: notes.randomElement()!, gate: true, accent: Float.random(in: 0...1) < 0.25, slide: Float.random(in: 0...1) < 0.2)
            }
            if s % 4 == 0 { p.setDrum(.kick, at: s, 2) }
            if s % 8 == 4 { p.setDrum(.snare, at: s, 1) }
            if s % 2 == 0 || Float.random(in: 0...1) < 0.3 { p.setDrum(.closedHat, at: s, s % 4 == 2 ? 2 : 1) }
            if Float.random(in: 0...1) < 0.12 { p.setDrum(.openHat, at: s, 1) }
            if Float.random(in: 0...1) < 0.08 { p.setDrum([.lowTom, .highTom, .clap, .cowbell].randomElement()!, at: s, 1) }
        }
        patterns[patternIndex] = p
        host.events.push(.setPattern(patternIndex, p))
        scheduleSave()
    }

    /// Audition a drum from the UI.
    func hit(_ kind: DrumVoiceKind) { host.trigger(kind) }
    func playBass(_ note: Int) { host.bassNote(note, accent: true); Task { try? await Task.sleep(for: .milliseconds(250)); host.events.push(.bassNoteOff) } }

    // MARK: - Mappings

    func addContinuous() {
        continuous.append(ContinuousMapping(source: .noseX, target: .parameter(.bassCutoff), outputRange: 150...5000))
    }

    func addEvent() {
        events.append(EventMapping(source: .anyHandRaised, target: .drum(.clap)))
    }

    func remove(continuousID id: UUID) { continuous.removeAll { $0.id == id }; smoothers[id] = nil }
    func remove(eventID id: UUID) { events.removeAll { $0.id == id }; detectors[id] = nil }

    // MARK: - Presets

    var allPresets: [SynthPreset] { SynthPreset.builtIn + userPresets }

    func apply(_ preset: SynthPreset, name: String? = nil) {
        currentPresetName = name ?? preset.name
        for (id, value) in preset.parameterValues { values[id] = value; host.parameters.set(id, value) }
        patterns = preset.patterns.count == 8 ? preset.patterns : Array(repeating: StepPattern(), count: 8)
        for (index, pattern) in patterns.enumerated() { host.events.push(.setPattern(index, pattern)) }
        selectPattern(preset.patternIndex)
        continuous = preset.continuous
        events = preset.events
        conductorMode = preset.conductor
        smoothers.removeAll()
        detectors.removeAll()
        UserDefaults.standard.set(currentPresetName, forKey: "presetName")
        scheduleSave()
    }

    func currentPreset(named name: String) -> SynthPreset {
        SynthPreset(name: name, parameters: values, patterns: patterns, patternIndex: patternIndex,
                    continuous: continuous, events: events, conductor: conductorMode)
    }

    func saveUserPreset(named name: String) {
        let preset = currentPreset(named: name)
        let url = Self.presetsFolder.appendingPathComponent(Self.fileName(for: name) + ".json")
        if let data = try? JSONEncoder().encode(preset) { try? data.write(to: url) }
        currentPresetName = name
        UserDefaults.standard.set(name, forKey: "presetName")
        loadUserPresets()
    }

    func deleteUserPreset(named name: String) {
        try? FileManager.default.removeItem(at: Self.presetsFolder.appendingPathComponent(Self.fileName(for: name) + ".json"))
        loadUserPresets()
    }

    func exportPreset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = Self.fileName(for: currentPresetName) + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let data = try? JSONEncoder().encode(currentPreset(named: currentPresetName)) { try? data.write(to: url) }
    }

    func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url), let preset = try? JSONDecoder().decode(SynthPreset.self, from: data) else { return }
        apply(preset)
        saveUserPreset(named: preset.name)
    }

    private func loadUserPresets() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.presetsFolder, includingPropertiesForKeys: nil)) ?? []
        userPresets = urls.filter { $0.pathExtension == "json" }.compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(SynthPreset.self, from: $0) }
        }.sorted { $0.name < $1.name }
    }

    private static func fileName(for name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
    }

    // MARK: - State persistence

    private static var stateURL: URL {
        presetsFolder.deletingLastPathComponent().appendingPathComponent("state.json")
    }

    private static func loadState() -> SynthPreset? {
        (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(SynthPreset.self, from: $0) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(currentPreset(named: currentPresetName)) { try? data.write(to: Self.stateURL) }
        }
    }

    // MARK: - Output device

    func refreshOutputDevices() { outputDevices = OutputDevices.all() }

    private func applyOutputDevice() {
        guard let id = selectedOutputDevice else { return }
        host.stop()
        _ = OutputDevices.select(id, on: host.engine)
        host.start()
        // The graph was rebuilt: push the instrument back into it.
        for (pid, value) in values { host.parameters.set(pid, value) }
        for (index, pattern) in patterns.enumerated() { host.events.push(.setPattern(index, pattern)) }
        host.events.push(.selectPattern(patternIndex))
        host.events.push(.setConductor(conductorMode))
        if isPlaying { host.play() }
    }

    // MARK: - Tick

    private func tick() {
        scene = builder.update(latest: model.latest)
        let now = Date()
        let time = Float(now.timeIntervalSince(start))
        let dt: Float = 1 / 60

        // Meters from the audio thread.
        peak = host.meters.peak
        let s = host.meters.step
        if s != lastStep {
            lastStep = s
            step = s
            if s >= 0 { fireEvents(.beat, velocity: 1) }
        }
        let hits = host.meters.takeDrumHits()
        if hits != 0 {
            for kind in DrumVoiceKind.allCases where hits & (1 << UInt64(kind.rawValue)) != 0 { lastDrumHits[kind] = now }
        }
        while let trigger = host.triggers.pop() {
            if case .bassOn(let note, _) = trigger.kind { lastBassNote = note }
            midi.send(trigger)
        }
        if isPlaying, midi.sendsClock {
            // 24 clocks per quarter note.
            clockAccumulator += Double(dt) * Double(value(.tempo)) / 60 * 24
            while clockAccumulator >= 1 { clockAccumulator -= 1; midi.clockTick() }
        }

        // Sources: the first person unless a mapping asks for another; read per person index on demand.
        var readingsByPerson: [Int: SourceReadings] = [:]
        func readingsFor(_ person: Int) -> SourceReadings {
            if let r = readingsByPerson[person] { return r }
            let r = SynthSources.read(scene: scene, latest: model.latest, person: person, staleInterval: builder.staleInterval)
            readingsByPerson[person] = r
            return r
        }
        readings = readingsFor(0)
        guard mappingsEnabled else { return }

        for mapping in continuous where mapping.isEnabled {
            guard let raw = readingsFor(mapping.person).continuous[mapping.source] else { continue }
            var smoother = smoothers[mapping.id] ?? MappingSmoother()
            let target = mapping.map(raw)
            let smoothed = smoother.next(target: target, smoothing: mapping.smoothing, dt: dt)
            smoothers[mapping.id] = smoother
            mappedValues[mapping.id] = smoothed
            switch mapping.target {
            case .parameter(let id):
                let clamped = min(max(smoothed, id.range.lowerBound), id.range.upperBound)
                values[id] = clamped
                host.parameters.set(id, clamped)
            case .midiCC(let channel, let controller):
                let cc = Int(min(max(smoothed, 0), 127))
                if lastCC[mapping.id] != cc {
                    lastCC[mapping.id] = cc
                    midi.controlChange(channel: channel, controller: controller, value: cc)
                }
            }
        }

        // Event sources that are edges of a value.
        for mapping in events where mapping.isEnabled {
            let r = readingsFor(mapping.person)
            switch mapping.source {
            case .barcodeChanged, .personEntered, .personLeft, .beat:
                continue
            default:
                guard let raw = r.event[mapping.source] else { continue }
                var detector = detectors[mapping.id] ?? EdgeDetector(threshold: 0.5, hysteresis: 0.08, refractory: mapping.source == .hit ? 0.15 : 0.3)
                let fired = detector.update(raw, time: time)
                detectors[mapping.id] = detector
                if fired { fire(mapping, now: now) }
            }
        }
        // Event sources that are events by nature.
        if let code = readings.code, code != lastCode {
            if lastCode != nil { fireEvents(.barcodeChanged, velocity: 1) }
            lastCode = code
        }
        let count = readings.personCount
        if count > lastPersonCount { fireEvents(.personEntered, velocity: 1) }
        if count < lastPersonCount { fireEvents(.personLeft, velocity: 1) }
        lastPersonCount = count
    }

    private func fireEvents(_ source: EventSource, velocity: Float) {
        guard mappingsEnabled else { return }
        for mapping in events where mapping.isEnabled && mapping.source == source { fire(mapping, now: Date()) }
    }

    private func fire(_ mapping: EventMapping, now: Date) {
        eventFlashes[mapping.id] = now
        switch mapping.target {
        case .drum(let kind):
            host.trigger(kind, velocity: mapping.velocity)
        case .bassNote(let note):
            host.bassNote(note, accent: mapping.velocity > 0.8)
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                self?.host.events.push(.bassNoteOff)
            }
        case .midiNote(let channel, let note):
            midi.note(channel: channel, note: note, velocity: mapping.velocity)
        case .selectPattern(let index):
            selectPattern(index)
        case .toggleStep(let kind, let step):
            toggleDrum(kind, step: step)
        case .advanceStep:
            if !isPlaying { togglePlay() }
            host.events.push(.advanceStep)
        case .playStop:
            togglePlay()
        }
    }
}
