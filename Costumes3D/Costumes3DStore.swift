//
//  Costumes3DStore.swift
//  TrackOSC 3D Costumes (macOS)
//
//  The app's state: the receiver model, the stage, the library, one
//  costume entity per tracked 3D body (same costume for everyone, or
//  cycling through the library), settings, and a 60 Hz tick that feeds
//  fresh /poses3d/arr bodies to the entities and fades them when gone.
//

import AppKit
import Costume3DCore
import Foundation
import Observation
import PoseioscShared
import RealityKit
import simd

enum Costume3DAssignment: String, CaseIterable, Identifiable {
    case same, cycle
    var id: String { rawValue }
    var label: String { self == .same ? "Everyone the same" : "Cycle through the library" }
}

@Observable @MainActor
final class Costumes3DStore {
    let model = ReceiverModel(app: .costumes3D)
    let library = Costume3DLibrary()
    let stage = Stage3D(showGnomon: true)

    var orbit = OrbitState()
    var assignment: Costume3DAssignment { didSet { UserDefaults.standard.set(assignment.rawValue, forKey: "assignment"); clearWearers() } }
    var smoothing: Double { didSet { UserDefaults.standard.set(smoothing, forKey: "smoothing"); for w in wearers { (w.costume as? RiggedCostumeEntity)?.smoothing = Float(smoothing) } } }
    var fadeSeconds: Double { didSet { UserDefaults.standard.set(fadeSeconds, forKey: "fadeSeconds") } }
    var showGnomon: Bool { didSet { UserDefaults.standard.set(showGnomon, forKey: "showGnomon"); applyGnomon() } }
    var mirror: Bool { didSet { UserDefaults.standard.set(mirror, forKey: "mirror"); stage.root.scale.x = mirror ? -1 : 1 } }

    private(set) var selectedID: String?
    private(set) var poseCount = 0
    private(set) var lastHeights: [Float] = []
    private(set) var currentWarnings: [String] = []
    private(set) var currentSummary = ""
    private(set) var isLoading = false
    private(set) var isReceiving3D = false

    private struct Wearer {
        var costume: any CostumeEntity
        var entryID: String
        var opacity: Float
        var lastSeen: Date
    }
    private var wearers: [Wearer] = []
    private var cycleIndex = 0
    private var tickTask: Task<Void, Never>?
    private var lastTick = Date()
    private var lastChangeCount = 0
    private var keyMonitor: Any?
    private var loadGeneration = 0

    init() {
        assignment = Costume3DAssignment(rawValue: UserDefaults.standard.string(forKey: "assignment") ?? "") ?? .same
        smoothing = UserDefaults.standard.object(forKey: "smoothing") as? Double ?? 0.06
        fadeSeconds = UserDefaults.standard.object(forKey: "fadeSeconds") as? Double ?? 0.4
        showGnomon = UserDefaults.standard.object(forKey: "showGnomon") as? Bool ?? true
        mirror = UserDefaults.standard.bool(forKey: "mirror")
        stage.root.scale.x = mirror ? -1 : 1
        applyGnomon()
        let stored = UserDefaults.standard.string(forKey: "costume")
        selectedID = library.entries.first { $0.id == stored }?.id ?? library.entries.first?.id
        installKeyMonitor()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self else { return }
                tick()
            }
        }
    }

    // MARK: - Selection

    var selectedEntry: Costume3DEntry? { library.entries.first { $0.id == selectedID } }

    func select(_ entry: Costume3DEntry) {
        selectedID = entry.id
        UserDefaults.standard.set(entry.id, forKey: "costume")
        clearWearers()
    }

    func select(index: Int) {
        guard library.entries.indices.contains(index) else { return }
        select(library.entries[index])
    }

    func nextCostume(_ step: Int = 1) {
        guard !library.entries.isEmpty else { return }
        let current = library.entries.firstIndex { $0.id == selectedID } ?? 0
        select(library.entries[(current + step + library.entries.count) % library.entries.count])
    }

    func reload() { clearWearers() }

    func resetView() { orbit = OrbitState() }

    private func clearWearers() {
        for w in wearers { w.costume.root.removeFromParent() }
        wearers.removeAll()
        cycleIndex = 0
        loadGeneration += 1
        currentWarnings = []
        currentSummary = ""
    }

    private func applyGnomon() {
        // The gnomon and camera marker are the root's ModelEntity children other than the floor.
        for child in stage.root.children where child is ModelEntity { child.isEnabled = showGnomon }
    }

    // MARK: - Costume entities

    private func makeCostume(for entry: Costume3DEntry) -> any CostumeEntity {
        switch entry.kind {
        case .mannequin:
            return PrimitiveCostumeEntity(style: .mannequin)
        case .blocks:
            return PrimitiveCostumeEntity(style: .blocks)
        case .rigged(let url):
            let rigged = RiggedCostumeEntity()
            rigged.smoothing = Float(smoothing)
            let generation = loadGeneration
            isLoading = true
            Task { [weak self] in
                await rigged.load(url: url)
                guard let self, generation == loadGeneration else { return }
                isLoading = false
                refreshWarnings()
            }
            return rigged
        case .parts(let folder):
            let parts = PartsCostumeEntity()
            let generation = loadGeneration
            isLoading = true
            Task { [weak self] in
                await parts.load(folder: folder)
                guard let self, generation == loadGeneration else { return }
                isLoading = false
                refreshWarnings()
            }
            return parts
        }
    }

    private func entry(forWearer index: Int) -> Costume3DEntry? {
        switch assignment {
        case .same:
            return selectedEntry
        case .cycle:
            guard !library.entries.isEmpty else { return nil }
            let e = library.entries[cycleIndex % library.entries.count]
            cycleIndex += 1
            return e
        }
    }

    private func refreshWarnings() {
        guard let first = wearers.first else { currentWarnings = []; currentSummary = ""; return }
        currentWarnings = first.costume.warnings
        currentSummary = first.costume.summary
    }

    // MARK: - Tick

    private func tick() {
        let now = Date()
        let dt = Float(min(0.1, now.timeIntervalSince(lastTick)))
        lastTick = now
        if library.changeCount != lastChangeCount {
            lastChangeCount = library.changeCount
            if selectedEntry == nil { selectedID = library.entries.first?.id }
            clearWearers()
        }
        var poses: [Pose3DDetection] = []
        if case .poses3D(let decoded)? = model.fresh(.poses3D, at: now) { poses = decoded.detections }
        isReceiving3D = !poses.isEmpty
        poseCount = poses.count
        lastHeights = poses.map(\.bodyHeight)

        // One wearer per pose, by index; extra wearers fade out and are removed.
        while wearers.count < poses.count {
            guard let entry = entry(forWearer: wearers.count) else { break }
            let costume = makeCostume(for: entry)
            stage.root.addChild(costume.root)
            costume.setOpacity(0)
            wearers.append(Wearer(costume: costume, entryID: entry.id, opacity: 0, lastSeen: now))
            if wearers.count == 1 { refreshWarnings() }
        }
        var lowest: Float?
        for i in wearers.indices {
            if i < poses.count {
                let joints = poses[i].joints.map { Stage3D.scenePosition(x: $0.x, y: $0.y, z: $0.z) }
                let live = Live3D(joints: joints, bodyHeight: poses[i].bodyHeight)
                wearers[i].costume.update(live: live, deltaTime: dt)
                wearers[i].lastSeen = now
                wearers[i].opacity = min(1, wearers[i].opacity + (fadeSeconds > 0 ? dt / Float(fadeSeconds) : 1))
                let ankleY = min(joints[Body3D.leftAnkle].y, joints[Body3D.rightAnkle].y)
                lowest = min(lowest ?? ankleY, ankleY)
            } else {
                wearers[i].costume.update(live: nil, deltaTime: dt)
                wearers[i].opacity = max(0, wearers[i].opacity - (fadeSeconds > 0 ? dt / Float(fadeSeconds) : 1))
            }
            wearers[i].costume.setOpacity(wearers[i].opacity)
        }
        // Drop wearers that have faded out and are beyond the pose count.
        var i = wearers.count - 1
        while i >= poses.count && i >= 0 {
            if wearers[i].opacity <= 0 {
                wearers[i].costume.root.removeFromParent()
                wearers.remove(at: i)
            }
            i -= 1
        }
        stage.settleFloor(under: lowest)
    }

    // MARK: - Keys

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else { return event }
            switch chars {
            case "[": nextCostume(-1)
            case "]": nextCostume(1)
            case "m": mirror.toggle()
            case "g": showGnomon.toggle()
            case "r": reload()
            case "0": resetView()
            case "1", "2", "3", "4", "5", "6", "7", "8", "9": select(index: Int(chars)! - 1)
            default: return event
            }
            return nil
        }
    }
}
