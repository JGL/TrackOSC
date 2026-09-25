//
//  SVGModel.swift
//  CostumeCore
//
//  The parsed document: a tree of groups and shapes, every shape's path
//  already in document (user) space with its style resolved. Only what a
//  costume needs; the rest is skipped with a warning.
//

import CoreGraphics
import Foundation

public struct SVGColor: Sendable, Equatable {
    public var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    public static let black = SVGColor(red: 0, green: 0, blue: 0)
}

public enum SVGFillRule: Sendable, Equatable { case nonZero, evenOdd }

public struct SVGStyle: Sendable, Equatable {
    /// nil = none (not painted). Unset fill defaults to black, as in SVG.
    public var fill: SVGColor? = .black
    public var stroke: SVGColor? = nil
    public var strokeWidth: CGFloat = 1
    public var opacity: CGFloat = 1
    public var fillOpacity: CGFloat = 1
    public var strokeOpacity: CGFloat = 1
    public var fillRule: SVGFillRule = .nonZero
    public var lineCap: CGLineCap = .butt
    public var lineJoin: CGLineJoin = .miter
    public var isHidden = false
    public init() {}
}

/// A drawable: one path in document space with its resolved style.
public struct SVGShape: @unchecked Sendable {
    public var path: CGPath
    public var style: SVGStyle
    public var id: String?
    /// The resolved layer label (see LayerName) if the element had one.
    public var label: String?
    public init(path: CGPath, style: SVGStyle, id: String? = nil, label: String? = nil) {
        self.path = path; self.style = style; self.id = id; self.label = label
    }
}

/// A group (`<g>`) or a lone shape, keeping the document's nesting so
/// layer names can be resolved on groups and their pivots found inside.
public final class SVGNode: @unchecked Sendable {
    public enum Kind: Sendable { case group, shape }
    public let kind: Kind
    public var id: String?
    /// inkscape:label → data-name → serif:id → id, with Illustrator escapes undone.
    public var label: String?
    public var shape: SVGShape?
    public var children: [SVGNode] = []
    public var isHidden = false
    /// Group opacity (multiplied into descendants when drawn).
    public var opacity: CGFloat = 1

    init(kind: Kind) { self.kind = kind }

    /// Every shape below this node, in document order.
    public var allShapes: [SVGShape] {
        var out: [SVGShape] = []
        func walk(_ node: SVGNode, opacity: CGFloat) {
            if node.isHidden { return }
            if let shape = node.shape {
                var s = shape
                s.style.opacity *= opacity
                out.append(s)
            }
            for child in node.children { walk(child, opacity: opacity * node.opacity) }
        }
        walk(self, opacity: 1)
        return out
    }

    public var boundingBox: CGRect {
        allShapes.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
    }
}

public struct SVGDocument: @unchecked Sendable {
    public var width: CGFloat
    public var height: CGFloat
    public var viewBox: CGRect
    public var root: SVGNode
    public var warnings: [String]

    /// Top-level layers: the root's children (Illustrator layers and Inkscape layers are top-level groups).
    public var layers: [SVGNode] { root.children }
}
