//
//  CostumeEntities.swift
//  TrackOSC 3D Costumes (macOS)
//
//  The three kinds of wearer as RealityKit entities: a rigged model whose
//  joints the FK solver drives, a folder of parts hung on bones, and the
//  built-in primitive costumes (mannequin capsules, blocks) that use the
//  same parts maths without any files.
//

import AppKit
import Costume3DCore
import Foundation
import RealityKit
import simd

@MainActor
protocol CostumeEntity: AnyObject {
    var root: Entity { get }
    var warnings: [String] { get }
    var summary: String { get }
    /// Apply a body (or hold the last one when nil). `deltaTime` in seconds.
    func update(live: Live3D?, deltaTime: Float)
    func setOpacity(_ opacity: Float)
}

extension CostumeEntity {
    func setOpacity(_ opacity: Float) {
        root.components.set(OpacityComponent(opacity: opacity))
    }
}

// MARK: - Rigged

@MainActor
final class RiggedCostumeEntity: CostumeEntity {
    let root = Entity()
    private(set) var warnings: [String] = []
    private(set) var summary = "loading\u{2026}"
    private var model: ModelEntity?
    private var rest: RestPose?
    private var solver = FKSolver()
    private var hipsIndex: Int?
    private var restHipsWorld = SIMD3<Float>.zero
    var smoothing: Float = 0.06 { didSet { solver.smoothing = smoothing } }

    init() {}

    /// Load a model file and find its skinned mesh.
    func load(url: URL) async {
        do {
            let loaded = try await Entity(contentsOf: url)
            guard let skinned = Self.findSkinned(in: loaded) else {
                // No skeleton: show it whole at the hips, scaled to the person's height.
                root.addChild(loaded)
                model = nil
                warnings = ["This model has no skeleton, so it is shown whole at the hips. Rig it on Apple's motion-capture skeleton to make it move (see the README)."]
                summary = "no skeleton"
                return
            }
            root.addChild(loaded)
            model = skinned
            let paths = skinned.jointNames
            let transforms = skinned.jointTransforms
            var parents: [Int] = []
            let index = Dictionary(uniqueKeysWithValues: paths.enumerated().map { ($1, $0) })
            for path in paths {
                let parentPath = path.split(separator: "/").dropLast().joined(separator: "/")
                parents.append(index[parentPath] ?? -1)
            }
            let rest = RestPose(paths: paths, parents: parents, localRotations: transforms.map(\.rotation), localTranslations: transforms.map(\.translation))
            self.rest = rest
            hipsIndex = rest.index(of: "hips_joint")
            if let hipsIndex { restHipsWorld = rest.worldTransforms().positions[hipsIndex] }
            let (missingDriven, missingOther) = AppleRig.validate(jointPaths: paths)
            var warnings: [String] = []
            if hipsIndex == nil { warnings.append("No hips_joint: the model cannot be placed. Name the joints after Apple's motion-capture skeleton.") }
            if !missingDriven.isEmpty { warnings.append("Not driven (missing): " + missingDriven.joined(separator: ", ")) }
            if !missingOther.isEmpty { warnings.append("\(missingOther.count) optional joint\(missingOther.count == 1 ? "" : "s") missing (fingers, face, toes): fine unless you need them.") }
            self.warnings = warnings
            summary = "\(paths.count) joints, \(AppleRig.driven.count - missingDriven.count) driven"
        } catch {
            warnings = ["Could not load: \(error.localizedDescription)"]
            summary = "failed to load"
        }
    }

    private static func findSkinned(in entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
        for child in entity.children { if let found = findSkinned(in: child) { return found } }
        return nil
    }

    func update(live: Live3D?, deltaTime: Float) {
        guard let model, let rest, let hipsIndex else {
            // Whole model: at the root joint, scaled by height.
            if let live {
                let scale = live.bodyHeight > 0.5 ? live.bodyHeight / 1.7 : 1
                root.scale = SIMD3<Float>(repeating: scale)
                root.position = live.joints[Body3D.root] - SIMD3<Float>(0, 0.92 * scale, 0)
            }
            return
        }
        guard let result = solver.solve(rest: rest, live: live, deltaTime: deltaTime) else { return }
        var transforms = model.jointTransforms
        guard transforms.count == result.localRotations.count else { return }
        for i in 0..<transforms.count { transforms[i].rotation = result.localRotations[i] }
        model.jointTransforms = transforms
        root.scale = SIMD3<Float>(repeating: result.scale)
        _ = hipsIndex
        root.position = result.hipsPosition - restHipsWorld * result.scale
    }
}

// MARK: - Parts (files)

@MainActor
final class PartsCostumeEntity: CostumeEntity {
    let root = Entity()
    private(set) var warnings: [String] = []
    private(set) var summary = "loading\u{2026}"
    private struct Part {
        let bone: PartBone
        let holder: Entity
        let axis: (start: SIMD3<Float>, end: SIMD3<Float>)
    }
    private var parts: [Part] = []
    private var previous: Live3D?

    init() {}

    func load(folder: URL) async {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var loaded: [Part] = []
        var unmatched: [String] = []
        for url in urls where Costume3DLibrary.modelExtensions.contains(url.pathExtension.lowercased()) {
            let name = url.deletingPathExtension().lastPathComponent
            guard let bone = PartBone.match(fileName: name) else { unmatched.append(name); continue }
            do {
                let entity = try await Entity(contentsOf: url)
                let bounds = entity.visualBounds(relativeTo: entity)
                let holder = Entity()
                holder.addChild(entity)
                root.addChild(holder)
                loaded.append(Part(bone: bone, holder: holder, axis: PartsMath.axis(ofBounds: bounds.min, bounds.max)))
            } catch {
                warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        parts = loaded
        if !unmatched.isEmpty { warnings.append("Not a bone name, skipped: " + unmatched.joined(separator: ", ")) }
        let missing = PartBone.allCases.filter { bone in !loaded.contains { $0.bone == bone } }
        if loaded.isEmpty { warnings.append("No part files matched a bone name (torso, head, forearm-left…).") }
        summary = "\(loaded.count) part\(loaded.count == 1 ? "" : "s")" + (missing.isEmpty ? "" : ", \(missing.count) bones bare")
    }

    func update(live: Live3D?, deltaTime: Float) {
        guard let live = live ?? previous else { return }
        previous = live
        for part in parts {
            guard let segment = part.bone.segment(in: live) else { continue }
            let placement = PartsMath.place(artAxis: part.axis, on: segment)
            part.holder.position = placement.position
            part.holder.orientation = placement.rotation
            part.holder.scale = SIMD3<Float>(repeating: placement.scale)
        }
    }
}

// MARK: - Primitives (mannequin, blocks)

@MainActor
final class PrimitiveCostumeEntity: CostumeEntity {
    enum Style { case mannequin, blocks }
    let root = Entity()
    let warnings: [String] = []
    let summary: String
    private let style: Style
    private var bones: [(a: Int, b: Int, entity: ModelEntity, radius: Float)] = []
    private var joints: [ModelEntity] = []
    private var head: ModelEntity
    private var previous: Live3D?

    init(style: Style) {
        self.style = style
        summary = style == .mannequin ? "capsules on every bone" : "a box on every bone"
        let colour = style == .mannequin ? NSColor(calibratedRed: 0.85, green: 0.82, blue: 0.75, alpha: 1) : NSColor(calibratedRed: 0.35, green: 0.6, blue: 0.9, alpha: 1)
        let material = SimpleMaterial(color: colour, roughness: 0.6, isMetallic: false)
        let radii: [Float] = [0.09, 0.09, 0.05, 0.06, 0.055, 0.04, 0.035, 0.055, 0.04, 0.035, 0.075, 0.055, 0.045, 0.075, 0.055, 0.045]
        for (i, (a, b)) in Body3D.edges.enumerated() {
            let r = radii[i]
            let mesh: MeshResource = style == .mannequin ? .generateCylinder(height: 1, radius: r) : .generateBox(size: SIMD3<Float>(r * 1.8, 1, r * 1.8))
            let entity = ModelEntity(mesh: mesh, materials: [material])
            root.addChild(entity)
            bones.append((a, b, entity, r))
        }
        if style == .mannequin {
            for _ in 0..<17 {
                let joint = ModelEntity(mesh: .generateSphere(radius: 0.05), materials: [material])
                root.addChild(joint)
                joints.append(joint)
            }
        }
        head = ModelEntity(mesh: style == .mannequin ? .generateSphere(radius: 0.11) : .generateBox(size: SIMD3<Float>(0.2, 0.24, 0.2)), materials: [material])
        root.addChild(head)
    }

    func update(live: Live3D?, deltaTime: Float) {
        guard let live = live ?? previous, live.joints.count >= 17 else { return }
        previous = live
        for bone in bones {
            let a = live.joints[bone.a], b = live.joints[bone.b]
            let delta = b - a
            let length = simd_length(delta)
            guard length > 1e-4 else { bone.entity.isEnabled = false; continue }
            bone.entity.isEnabled = true
            bone.entity.position = (a + b) / 2
            bone.entity.scale = SIMD3<Float>(1, length, 1)
            let up = SIMD3<Float>(0, 1, 0)
            let direction = delta / length
            bone.entity.orientation = simd_dot(up, direction) < -0.9999 ? simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0)) : simd_quatf(from: up, to: direction)
        }
        for (i, joint) in joints.enumerated() {
            joint.position = live.joints[i]
            joint.scale = SIMD3<Float>(repeating: i == Body3D.root || i == Body3D.centerShoulder ? 1.6 : (i >= 11 ? 1.2 : 0.9))
        }
        let centre = (live.joints[Body3D.centerHead] + live.joints[Body3D.topHead]) / 2
        head.position = centre
        let neck = live.joints[Body3D.topHead] - live.joints[Body3D.centerHead]
        if simd_length(neck) > 1e-4 {
            head.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(neck))
        }
    }
}
