//
//  CostumesStore.swift
//  TrackOSC Costumes (macOS)
//
//  The app's state: the receiver model and scene builder, the library,
//  the chosen costume (or one per person), a rig per tracked person, the
//  display settings, keyboard shortcuts, recording, and a 60 Hz tick that
//  solves every rig into a StageFrame the stage and the recorder both draw.
//

import AppKit
import CostumeCore
import Foundation
import Observation
import PoseioscShared
import simd

enum CostumeAssignment: String, CaseIterable, Identifiable {
    /// Everyone wears the chosen costume.
    case same
    /// Each new person gets the next costume in the library.
    case cycle
    var id: String { rawValue }
    var label: String { self == .same ? "Everyone the same" : "Cycle through the library" }
}

enum StageFit: String, CaseIterable, Identifiable {
    case fit, fill
    var id: String { rawValue }
    var label: String { self == .fit ? "Fit (letterbox)" : "Fill (crop)" }
}

/// Everything needed to draw one frame, computed on the main actor and drawn anywhere.
struct StageFrame: @unchecked Sendable {
    struct Wearer {
        var costume: Costume
        var placements: [LayerPlacement]
    }
    var wearers: [Wearer] = []
    /// Costumes whose scenery to draw (once each), with the base transform.
    var scenery: [(Costume, CGAffineTransform)] = []
    var size = CGSize(width: 1280, height: 720)
    var frameRect = CGRect.zero
    var isAttract = false
    var skeleton: [[CGPoint]] = []   // debug lines
}

@Observable @MainActor
final class CostumesStore {
    let model = ReceiverModel(app: .costumes)
    let builder = SceneBuilder()
    let library = CostumeLibrary()
    let recorder = CanvasRecorder()

    // Settings (UserDefaults).
    var mirror: Bool { didSet { UserDefaults.standard.set(mirror, forKey: "mirror"); builder.mirror = mirror } }
    var fit: StageFit { didSet { UserDefaults.standard.set(fit.rawValue, forKey: "fit") } }
    var assignment: CostumeAssignment { didSet { UserDefaults.standard.set(assignment.rawValue, forKey: "assignment"); assignments.removeAll() } }
    var smoothing: Float { didSet { UserDefaults.standard.set(smoothing, forKey: "smoothing"); builder.smoothing = smoothing } }
    var fadeSeconds: Double { didSet { UserDefaults.standard.set(fadeSeconds, forKey: "fadeSeconds") } }
    var attractDelay: Double { didSet { UserDefaults.standard.set(attractDelay, forKey: "attractDelay"); builder.attractDelay = Float(attractDelay) } }
    var showSkeleton: Bool { didSet { UserDefaults.standard.set(showSkeleton, forKey: "showSkeleton") } }

    private(set) var selectedID: String?
    private(set) var costume: Costume?
    private(set) var loadError: String?
    private(set) var frame = StageFrame()
    private(set) var scene = TrackingScene.empty
    /// Which layers were placed this frame (for the inspector's live dots).
    private(set) var liveLayers: Set<Int> = []
    private(set) var isFacingAway = false
    var viewSize = CGSize(width: 1280, height: 720)
    var backingScale: CGFloat = 2

    private var rigs: [Int: Rig] = [:]
    private var assignments: [Int: String] = [:]
    private var loaded: [String: Costume] = [:]
    private var cycleIndex = 0
    private var keyMonitor: Any?
    private var tickTask: Task<Void, Never>?
    private var lastChangeCount = 0

    init() {
        mirror = UserDefaults.standard.object(forKey: "mirror") as? Bool ?? true
        fit = StageFit(rawValue: UserDefaults.standard.string(forKey: "fit") ?? "") ?? .fit
        assignment = CostumeAssignment(rawValue: UserDefaults.standard.string(forKey: "assignment") ?? "") ?? .same
        smoothing = UserDefaults.standard.object(forKey: "smoothing") as? Float ?? 0.08
        fadeSeconds = UserDefaults.standard.object(forKey: "fadeSeconds") as? Double ?? 0.3
        attractDelay = UserDefaults.standard.object(forKey: "attractDelay") as? Double ?? 20
        showSkeleton = UserDefaults.standard.bool(forKey: "showSkeleton")
        builder.mirror = mirror
        builder.smoothing = smoothing
        builder.attractDelay = Float(attractDelay)
        let stored = UserDefaults.standard.string(forKey: "costume")
        if let entry = library.entries.first(where: { $0.id == stored }) ?? library.entries.first { select(entry) }
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

    var selectedEntry: CostumeEntry? { library.entries.first { $0.id == selectedID } }

    func select(_ entry: CostumeEntry) {
        selectedID = entry.id
        UserDefaults.standard.set(entry.id, forKey: "costume")
        reload()
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

    func reload() {
        loaded.removeAll()
        rigs.removeAll()
        guard let entry = selectedEntry else { costume = nil; return }
        if let c = library.load(entry) {
            costume = c
            loaded[entry.id] = c
            loadError = nil
        } else {
            costume = nil
            loadError = library.loadError(entry) ?? "Could not read the costume."
        }
    }

    private func costume(for entry: CostumeEntry) -> Costume? {
        if let c = loaded[entry.id] { return c }
        guard let c = library.load(entry) else { return nil }
        loaded[entry.id] = c
        return c
    }

    private func costume(forPerson id: Int) -> Costume? {
        switch assignment {
        case .same:
            return costume
        case .cycle:
            if let assigned = assignments[id], let entry = library.entries.first(where: { $0.id == assigned }) { return costume(for: entry) }
            guard !library.entries.isEmpty else { return nil }
            let entry = library.entries[cycleIndex % library.entries.count]
            cycleIndex += 1
            assignments[id] = entry.id
            return costume(for: entry)
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
        } else {
            recorder.start(appName: TrackOSCApp.costumes.displayName, width: Int(viewSize.width * backingScale), height: Int(viewSize.height * backingScale))
        }
    }

    // MARK: - Tick

    private func tick() {
        if library.changeCount != lastChangeCount {
            lastChangeCount = library.changeCount
            reload()
            if selectedEntry == nil, let first = library.entries.first { select(first) }
        }
        scene = builder.update(latest: model.latest)
        let size = viewSize
        let aspect = CGFloat(max(scene.frameAspect, 0.05))
        var rect: CGRect
        if fit == .fit {
            var w = size.width, h = w / aspect
            if h > size.height { h = size.height; w = h * aspect }
            rect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
        } else {
            var w = size.width, h = w / aspect
            if h < size.height { h = size.height; w = h * aspect }
            rect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
        }
        func px(_ p: ScenePoint) -> CGPoint { CGPoint(x: rect.minX + CGFloat(p.x) * rect.width, y: rect.minY + CGFloat(p.y) * rect.height) }

        var next = StageFrame()
        next.size = size
        next.frameRect = rect
        next.isAttract = scene.isAttract
        var live: Set<Int> = []
        var seenIDs: Set<Int> = []
        var sceneryDone: Set<String> = []
        let dt = CGFloat(scene.deltaTime)

        func wear(id: Int, input: RigInput) {
            guard let c = costume(forPerson: id) else { return }
            var rig = rigs[id] ?? Rig()
            rig.mirrored = mirror
            rig.fadeSeconds = CGFloat(fadeSeconds)
            let placements = rig.solve(costume: c, input: input, deltaTime: dt)
            rigs[id] = rig
            seenIDs.insert(id)
            if id == scene.persons.sorted(by: { $0.id < $1.id }).first?.id { isFacingAway = rig.isFacingAway }
            for p in placements where p.isVisible { live.insert(p.layerID) }
            next.wearers.append(StageFrame.Wearer(costume: c, placements: placements))
            if !sceneryDone.contains(c.name) {
                sceneryDone.insert(c.name)
                next.scenery.append((c, CostumeRenderer.fit(viewBox: c.document.viewBox, into: CGRect(origin: .zero, size: size))))
            }
        }

        func rigHand(_ h: SceneHand) -> RigHand { RigHand(joints: h.joints.map(px), visible: h.visible, isLeft: h.isLeft) }
        func rigFace(_ f: SceneFace) -> RigFace {
            RigFace(landmarks: f.landmarks.count >= 76 ? f.landmarks.map(px) : [], rollDegrees: CGFloat(f.rollDegrees), mouthOpenness: CGFloat(f.mouthOpenness))
        }

        let persons = scene.persons.sorted { $0.id < $1.id }
        for person in persons {
            let input = RigInput(body: person.joints.map(px), bodyVisible: person.visible, hands: person.hands.map(rigHand), face: person.face.map(rigFace))
            wear(id: person.id, input: input)
            if showSkeleton {
                for (a, b) in Skeleton.body17Edges where person.visible[a] && person.visible[b] {
                    next.skeleton.append([px(person.joints[a]), px(person.joints[b])])
                }
                if let face = person.face, face.landmarks.count >= 76 {
                    for p in face.landmarks { let q = px(p); next.skeleton.append([q, CGPoint(x: q.x + 1.5, y: q.y + 1.5)]) }
                }
                for hand in person.hands {
                    for (a, b) in Skeleton.hand21Edges where hand.visible[a] && hand.visible[b] {
                        next.skeleton.append([px(hand.joints[a]), px(hand.joints[b])])
                    }
                }
            }
        }
        if persons.isEmpty {
            // Nobody's body, but maybe hands or a face on their own: dress those.
            let noBody = [CGPoint](repeating: .zero, count: 17), none = [Bool](repeating: false, count: 17)
            let unattachedHands = scene.hands.filter { $0.personID == nil }
            let unattachedFaces = scene.faces.filter { $0.personID == nil }
            if !unattachedHands.isEmpty || !unattachedFaces.isEmpty {
                wear(id: -1, input: RigInput(body: noBody, bodyVisible: none, hands: unattachedHands.map(rigHand), face: unattachedFaces.first.map(rigFace)))
            }
        }
        // Costumes with only scenery still show it.
        if next.scenery.isEmpty, let costume, costume.layers.contains(where: { $0.name.role == .scenery }) {
            next.scenery.append((costume, CostumeRenderer.fit(viewBox: costume.document.viewBox, into: CGRect(origin: .zero, size: size))))
        }
        for id in rigs.keys where !seenIDs.contains(id) { rigs[id] = nil; assignments[id] = nil }
        if !persons.isEmpty { liveLayers = live } else if scene.hands.isEmpty && scene.faces.isEmpty { liveLayers = [] } else { liveLayers = live }
        frame = next

        if recorder.isRecording {
            let snapshot = next
            let scale = backingScale
            let background = NSColor(model.settings.stageBackground).cgColor
            recorder.capture { context, pixelSize in
                context.setFillColor(background)
                context.fill(CGRect(origin: .zero, size: pixelSize))
                context.scaleBy(x: scale, y: scale)
                Self.draw(snapshot, in: context)
            }
        }
    }

    /// Draw a frame into a y-down CoreGraphics context (the Canvas's, or the recorder's flipped one).
    nonisolated static func draw(_ frame: StageFrame, in context: CGContext) {
        for (costume, base) in frame.scenery {
            CostumeRenderer.drawScenery(costume: costume, base: base, in: context)
        }
        for wearer in frame.wearers {
            CostumeRenderer.draw(costume: wearer.costume, placements: wearer.placements, base: .identity, includeScenery: false, in: context)
        }
        if !frame.skeleton.isEmpty {
            context.saveGState()
            context.setStrokeColor(CGColor(srgbRed: 0, green: 1, blue: 0.6, alpha: 0.7))
            context.setLineWidth(2)
            for line in frame.skeleton where line.count == 2 {
                context.move(to: line[0]); context.addLine(to: line[1])
            }
            context.strokePath()
            context.restoreGState()
        }
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
            case "k": showSkeleton.toggle()
            case "v": toggleRecording()
            case "r": reload()
            case "1", "2", "3", "4", "5", "6", "7", "8", "9": select(index: Int(chars)! - 1)
            default: return event
            }
            return nil
        }
    }
}
