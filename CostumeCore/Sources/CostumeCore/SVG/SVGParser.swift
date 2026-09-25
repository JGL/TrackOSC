//
//  SVGParser.swift
//  CostumeCore
//
//  XMLParser-based reader for the subset costumes use: svg, g, path,
//  rect, circle, ellipse, line, polyline, polygon, style. Transforms are
//  baked into document space; styles cascade from presentation
//  attributes, <style> rules and style="" in that order. Unsupported
//  elements are skipped with a warning naming them.
//

import CoreGraphics
import Foundation

public enum SVGParseError: Error, LocalizedError {
    case notSVG
    case xml(String)
    public var errorDescription: String? {
        switch self {
        case .notSVG: "The file is not an SVG document."
        case .xml(let message): "The SVG could not be read: \(message)"
        }
    }
}

public enum SVGParser {
    public static func parse(data: Data) throws -> SVGDocument {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        if !parser.parse(), let error = parser.parserError, delegate.document == nil {
            throw SVGParseError.xml(error.localizedDescription)
        }
        guard let doc = delegate.finish() else { throw SVGParseError.notSVG }
        return doc
    }

    public static func parse(contentsOf url: URL) throws -> SVGDocument {
        try parse(data: Data(contentsOf: url))
    }

    /// Length with an optional unit; only the number is used (px, pt, mm all treated as user units).
    static func length(_ text: String?) -> CGFloat? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let numeric = trimmed.prefix { "0123456789.-+eE".contains($0) }
        return Double(numeric).map { CGFloat($0) }
    }

    /// Illustrator escapes in ids: _x3A_ → ":", _x2E_ → ".", _x20_ → " "; trailing _N_ copies removed.
    static func unescapeIllustrator(_ id: String) -> String {
        var s = id
        // Generic _xHH_ escapes.
        while let range = s.range(of: #"_x([0-9A-Fa-f]{2})_"#, options: .regularExpression) {
            let hex = s[range].dropFirst(2).dropLast()
            if let code = UInt8(hex, radix: 16) {
                s.replaceSubrange(range, with: String(Character(Unicode.Scalar(code))))
            } else { break }
        }
        if let range = s.range(of: #"_\d+_$"#, options: .regularExpression) { s.removeSubrange(range) }
        return s
    }

    static let unsupported: Set<String> = ["use", "linearGradient", "radialGradient", "pattern", "clipPath", "mask", "filter", "text", "tspan", "image", "symbol", "marker", "foreignObject", "switch"]
    static let ignored: Set<String> = ["title", "desc", "metadata", "namedview", "sodipodi:namedview"]

    final class Delegate: NSObject, XMLParserDelegate {
        private struct Frame {
            var node: SVGNode
            var transform: CGAffineTransform
            var style: SVGStyle
            var element: String
        }

        private(set) var document: SVGDocument?
        private var stack: [Frame] = []
        private var root: SVGNode?
        private var width: CGFloat = 0, height: CGFloat = 0, viewBox = CGRect.zero
        private var skipDepth = 0
        /// Inside <defs>: nothing is drawn, nothing warns, but <style> still counts.
        private var defsDepth = 0
        private var inStyle = false
        private var cssText = ""
        private var pendingCSS: [String] = []
        private var styleSheet = SVGStyleSheet(css: "")
        private var warnings: [String] = []
        private var warned: Set<String> = []
        private var sawSVG = false

        func finish() -> SVGDocument? {
            guard sawSVG, let root else { return nil }
            if viewBox.isEmpty { viewBox = CGRect(x: 0, y: 0, width: width > 0 ? width : max(1, root.boundingBox.maxX), height: height > 0 ? height : max(1, root.boundingBox.maxY)) }
            if width <= 0 { width = viewBox.width }
            if height <= 0 { height = viewBox.height }
            return SVGDocument(width: width, height: height, viewBox: viewBox, root: root, warnings: warnings)
        }

        private func warnOnce(_ message: String) {
            guard !warned.contains(message) else { return }
            warned.insert(message)
            warnings.append(message)
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
            if name == "style" { inStyle = true; cssText = ""; return }
            if skipDepth > 0 { skipDepth += 1; return }
            if name == "defs" { defsDepth += 1; return }
            if defsDepth > 0 { return }
            if SVGParser.ignored.contains(elementName) || SVGParser.ignored.contains(name) { skipDepth = 1; return }
            if SVGParser.unsupported.contains(name) {
                warnOnce("<\(name)> is not supported and was skipped (flatten or expand it in your drawing app).")
                skipDepth = 1
                return
            }
            let parentTransform = stack.last?.transform ?? .identity
            let parentStyle = stack.last?.style ?? SVGStyle()
            let transform = attributes["transform"].map { SVGTransform.parse($0).concatenating(parentTransform) } ?? parentTransform

            var style = parentStyle
            style.opacity = 1   // opacity does not inherit; group opacity is kept on the node
            let classes = (attributes["class"] ?? "").split(separator: " ").map(String.init)
            let id = attributes["id"]
            for (key, value) in attributes where key != "style" && key != "transform" && key != "class" && key != "id" {
                style.apply(key, value, warnings: &warnings)
            }
            for (key, value) in styleSheet.declarations(element: name, classes: classes, id: id) {
                style.apply(key, value, warnings: &warnings)
            }
            if let inline = attributes["style"] {
                for (key, value) in SVGStyleSheet.declarations(inline) { style.apply(key, value, warnings: &warnings) }
            }
            let opacity = style.opacity
            let hidden = style.isHidden
            style.isHidden = false

            let label = attributes["inkscape:label"] ?? attributes["data-name"] ?? attributes["serif:id"] ?? id.map(SVGParser.unescapeIllustrator)

            switch name {
            case "svg":
                sawSVG = true
                width = SVGParser.length(attributes["width"]) ?? 0
                height = SVGParser.length(attributes["height"]) ?? 0
                if let vb = attributes["viewBox"] {
                    let n = vb.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
                    if n.count == 4 { viewBox = CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) }
                }
                let node = SVGNode(kind: .group)
                root = node
                stack.append(Frame(node: node, transform: .identity, style: style, element: name))
            case "g", "a":
                let node = SVGNode(kind: .group)
                node.id = id
                node.label = label
                node.opacity = opacity
                node.isHidden = hidden
                stack.last?.node.children.append(node)
                stack.append(Frame(node: node, transform: transform, style: style, element: name))
            default:
                if let path = shapePath(name, attributes) {
                    let node = SVGNode(kind: .shape)
                    node.id = id
                    node.label = label
                    node.isHidden = hidden
                    var shapeStyle = style
                    shapeStyle.opacity = opacity
                    // Stroke width scales with the transform (approximately, by its mean scale).
                    let scale = sqrt(abs(transform.a * transform.d - transform.b * transform.c))
                    shapeStyle.strokeWidth *= scale
                    var transformed = transform
                    let baked = path.copy(using: &transformed) ?? path
                    node.shape = SVGShape(path: baked, style: shapeStyle, id: id, label: label)
                    stack.last?.node.children.append(node)
                    stack.append(Frame(node: node, transform: transform, style: style, element: name))
                } else {
                    // Unknown element: keep walking its children (e.g. a namespaced wrapper).
                    let node = SVGNode(kind: .group)
                    node.label = label
                    stack.last?.node.children.append(node)
                    stack.append(Frame(node: node, transform: transform, style: style, element: name))
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inStyle { cssText += string }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if inStyle, let s = String(data: CDATABlock, encoding: .utf8) { cssText += s }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
            if name == "style" {
                inStyle = false
                pendingCSS.append(cssText)
                styleSheet = SVGStyleSheet(css: pendingCSS.joined(separator: "\n"))
                return
            }
            if skipDepth > 0 { skipDepth -= 1; return }
            if name == "defs" { defsDepth -= 1; return }
            if defsDepth > 0 { return }
            if !stack.isEmpty { stack.removeLast() }
        }

        private func shapePath(_ name: String, _ a: [String: String]) -> CGPath? {
            func n(_ key: String, _ fallback: CGFloat = 0) -> CGFloat { SVGParser.length(a[key]) ?? fallback }
            switch name {
            case "path":
                return a["d"].flatMap(SVGPath.parse)
            case "rect":
                let rect = CGRect(x: n("x"), y: n("y"), width: n("width"), height: n("height"))
                guard rect.width > 0, rect.height > 0 else { return nil }
                var rx = n("rx", -1), ry = n("ry", -1)
                if rx < 0 && ry < 0 { return CGPath(rect: rect, transform: nil) }
                if rx < 0 { rx = ry }
                if ry < 0 { ry = rx }
                return CGPath(roundedRect: rect, cornerWidth: min(rx, rect.width / 2), cornerHeight: min(ry, rect.height / 2), transform: nil)
            case "circle":
                let r = n("r")
                guard r > 0 else { return nil }
                return CGPath(ellipseIn: CGRect(x: n("cx") - r, y: n("cy") - r, width: 2 * r, height: 2 * r), transform: nil)
            case "ellipse":
                let rx = n("rx"), ry = n("ry")
                guard rx > 0, ry > 0 else { return nil }
                return CGPath(ellipseIn: CGRect(x: n("cx") - rx, y: n("cy") - ry, width: 2 * rx, height: 2 * ry), transform: nil)
            case "line":
                let p = CGMutablePath()
                p.move(to: CGPoint(x: n("x1"), y: n("y1")))
                p.addLine(to: CGPoint(x: n("x2"), y: n("y2")))
                return p
            case "polyline", "polygon":
                let numbers = (a["points"] ?? "").split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" }).compactMap { Double($0) }
                guard numbers.count >= 4 else { return nil }
                let p = CGMutablePath()
                p.move(to: CGPoint(x: numbers[0], y: numbers[1]))
                var i = 2
                while i + 1 < numbers.count { p.addLine(to: CGPoint(x: numbers[i], y: numbers[i + 1])); i += 2 }
                if name == "polygon" { p.closeSubpath() }
                return p
            default:
                return nil
            }
        }
    }
}
