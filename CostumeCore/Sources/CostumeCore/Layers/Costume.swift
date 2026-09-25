//
//  Costume.swift
//  CostumeCore
//
//  A parsed SVG turned into rig layers: each named top-level layer (or
//  named group anywhere) with its shapes in document space, bounding box,
//  art axis (from a `pivot` child or the box) and role.
//

import CoreGraphics
import Foundation

public struct CostumeLayer: @unchecked Sendable, Identifiable {
    public var id: Int
    public var name: LayerName
    public var shapes: [SVGShape]
    public var boundingBox: CGRect
    /// Explicit axis from a `pivot` child (start, end), in document space.
    public var pivot: (CGPoint, CGPoint)?
    public var label: String

    /// The art axis: the pivot, else the box's vertical (top→bottom) or horizontal (left→right) midline.
    public func axis(horizontal: Bool) -> (CGPoint, CGPoint) {
        if let pivot { return pivot }
        let b = boundingBox
        return horizontal
            ? (CGPoint(x: b.minX, y: b.midY), CGPoint(x: b.maxX, y: b.midY))
            : (CGPoint(x: b.midX, y: b.minY), CGPoint(x: b.midX, y: b.maxY))
    }
}

public struct Costume: @unchecked Sendable {
    public var name: String
    public var document: SVGDocument
    public var layers: [CostumeLayer]
    public var warnings: [String]
    /// Guides by name (`guide:torso` → its axis), never drawn.
    public var guides: [String: (CGPoint, CGPoint)]

    public init(name: String, document: SVGDocument) {
        self.name = name
        self.document = document
        var layers: [CostumeLayer] = []
        var guides: [String: (CGPoint, CGPoint)] = [:]
        var warnings = document.warnings
        var nextID = 0

        func endpoints(of node: SVGNode) -> (CGPoint, CGPoint)? {
            guard let path = node.allShapes.first?.path else { return nil }
            var points: [CGPoint] = []
            path.applyWithBlock { element in
                switch element.pointee.type {
                case .moveToPoint, .addLineToPoint: points.append(element.pointee.points[0])
                case .addQuadCurveToPoint: points.append(element.pointee.points[1])
                case .addCurveToPoint: points.append(element.pointee.points[2])
                default: break
                }
            }
            guard points.count >= 2 else { return nil }
            return (points[0], points[points.count - 1])
        }

        func visit(_ node: SVGNode) {
            if let label = node.label, let name = LayerName.parse(label) {
                switch name.role {
                case .guide(let guideName):
                    // Guides are usually hidden in the drawing; read them anyway.
                    let wasHidden = node.isHidden
                    node.isHidden = false
                    if let e = endpoints(of: node) { guides[guideName] = e } else { warnings.append("guide:\(guideName) needs a two-point line.") }
                    node.isHidden = wasHidden
                    return
                case .pivot:
                    return   // handled by its parent
                default:
                    if node.isHidden { return }
                    // Shapes of this layer, excluding pivot children; pivot from a child named pivot.
                    var pivot: (CGPoint, CGPoint)?
                    var shapes: [SVGShape] = []
                    func collect(_ n: SVGNode, opacity: CGFloat) {
                        if n.isHidden { return }
                        if let l = n.label, let child = LayerName.parse(l), child.role == .pivot {
                            if let e = endpoints(of: n) { pivot = e } else { warnings.append("pivot in \u{201C}\(label)\u{201D} needs a two-point line.") }
                            return
                        }
                        if let shape = n.shape {
                            var s = shape
                            s.style.opacity *= opacity
                            shapes.append(s)
                        }
                        for c in n.children { collect(c, opacity: opacity * n.opacity) }
                    }
                    collect(node, opacity: 1)
                    let box = shapes.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
                    if shapes.isEmpty { warnings.append("\u{201C}\(label)\u{201D} has no drawable shapes.") ; return }
                    layers.append(CostumeLayer(id: nextID, name: name, shapes: shapes, boundingBox: box, pivot: pivot, label: label))
                    nextID += 1
                    return
                }
            }
            if node.isHidden { return }
            // Not a rig layer: a group keeps looking inside for named children;
            // shapes (and groups without any named descendants) are scenery.
            if node.kind == .group, node.children.contains(where: { hasNamedDescendant($0) }) {
                for child in node.children { visit(child) }
            } else {
                let shapes = node.allShapes
                guard !shapes.isEmpty else { return }
                let box = shapes.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
                layers.append(CostumeLayer(id: nextID, name: LayerName(role: .scenery, flags: [], original: node.label ?? ""), shapes: shapes, boundingBox: box, pivot: nil, label: node.label ?? "scenery"))
                nextID += 1
            }
        }
        func hasNamedDescendant(_ node: SVGNode) -> Bool {
            if let label = node.label, LayerName.parse(label) != nil { return true }
            return node.children.contains { hasNamedDescendant($0) }
        }
        for child in document.root.children { visit(child) }
        self.layers = layers
        self.guides = guides
        self.warnings = warnings
    }

    public func layers(with role: LayerRole) -> [CostumeLayer] { layers.filter { $0.name.role == role } }

    /// What the costume can do, for the library and the inspector.
    public var summary: String {
        var parts: [String] = []
        let bones = layers.filter { if case .bone = $0.name.role { return true } else { return false } }.count
        if bones > 0 { parts.append("\(bones) body \(bones == 1 ? "part" : "parts")") }
        if layers.contains(where: { $0.name.role == .head }) { parts.append("head") }
        let faces = layers.filter { if case .face = $0.name.role { return true } else { return false } }.count
        if faces > 0 { parts.append("\(faces) face \(faces == 1 ? "part" : "parts")") }
        let hands = layers.filter { if case .hand = $0.name.role { return true } else { return false } }.count
        if hands > 0 { parts.append("\(hands) hand \(hands == 1 ? "part" : "parts")") }
        let scenery = layers.filter { $0.name.role == .scenery }.count
        if scenery > 0 { parts.append("\(scenery) scenery") }
        return parts.isEmpty ? "no rig layers" : parts.joined(separator: ", ")
    }
}
