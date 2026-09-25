//
//  SVGStyle+Parsing.swift
//  CostumeCore
//
//  Colours (keywords, #hex, rgb()), presentation attributes, `style=""`
//  and the simple class/element/id rules Illustrator and Inkscape put in
//  a `<style>` block. Gradients, patterns and url() paints are skipped.
//

import CoreGraphics
import Foundation

enum SVGColorParser {
    static let keywords: [String: (Int, Int, Int)] = [
        "black": (0, 0, 0), "white": (255, 255, 255), "red": (255, 0, 0), "lime": (0, 255, 0), "blue": (0, 0, 255),
        "yellow": (255, 255, 0), "cyan": (0, 255, 255), "aqua": (0, 255, 255), "magenta": (255, 0, 255), "fuchsia": (255, 0, 255),
        "gray": (128, 128, 128), "grey": (128, 128, 128), "silver": (192, 192, 192), "maroon": (128, 0, 0), "olive": (128, 128, 0),
        "green": (0, 128, 0), "purple": (128, 0, 128), "teal": (0, 128, 128), "navy": (0, 0, 128), "orange": (255, 165, 0),
        "pink": (255, 192, 203), "brown": (165, 42, 42), "gold": (255, 215, 0), "tan": (210, 180, 140), "beige": (245, 245, 220),
        "ivory": (255, 255, 240), "khaki": (240, 230, 140), "coral": (255, 127, 80), "salmon": (250, 128, 114), "tomato": (255, 99, 71),
        "crimson": (220, 20, 60), "indigo": (75, 0, 130), "violet": (238, 130, 238), "orchid": (218, 112, 214), "plum": (221, 160, 221),
        "lavender": (230, 230, 250), "turquoise": (64, 224, 208), "skyblue": (135, 206, 235), "steelblue": (70, 130, 180),
        "royalblue": (65, 105, 225), "dodgerblue": (30, 144, 255), "deepskyblue": (0, 191, 255), "lightblue": (173, 216, 230),
        "darkblue": (0, 0, 139), "midnightblue": (25, 25, 112), "darkgreen": (0, 100, 0), "forestgreen": (34, 139, 34),
        "seagreen": (46, 139, 87), "limegreen": (50, 205, 50), "springgreen": (0, 255, 127), "yellowgreen": (154, 205, 50),
        "olivedrab": (107, 142, 35), "darkred": (139, 0, 0), "firebrick": (178, 34, 34), "orangered": (255, 69, 0),
        "darkorange": (255, 140, 0), "chocolate": (210, 105, 30), "sienna": (160, 82, 45), "peru": (205, 133, 63),
        "sandybrown": (244, 164, 96), "wheat": (245, 222, 179), "lightgray": (211, 211, 211), "lightgrey": (211, 211, 211),
        "darkgray": (169, 169, 169), "darkgrey": (169, 169, 169), "dimgray": (105, 105, 105), "dimgrey": (105, 105, 105),
        "slategray": (112, 128, 144), "slategrey": (112, 128, 144), "whitesmoke": (245, 245, 245), "snow": (255, 250, 250),
        "hotpink": (255, 105, 180), "deeppink": (255, 20, 147), "lightpink": (255, 182, 193), "peachpuff": (255, 218, 185),
        "mistyrose": (255, 228, 225), "lightyellow": (255, 255, 224), "lemonchiffon": (255, 250, 205), "aquamarine": (127, 255, 212),
        "mediumpurple": (147, 112, 219), "rebeccapurple": (102, 51, 153), "darkviolet": (148, 0, 211), "cadetblue": (95, 158, 160),
        "powderblue": (176, 224, 230), "mintcream": (245, 255, 250), "honeydew": (240, 255, 240), "darkslategray": (47, 79, 79),
        "darkslategrey": (47, 79, 79), "lightgreen": (144, 238, 144), "palegreen": (152, 251, 152), "goldenrod": (218, 165, 32),
        "darkgoldenrod": (184, 134, 11), "burlywood": (222, 184, 135), "rosybrown": (188, 143, 143), "saddlebrown": (139, 69, 19),
        "lightcoral": (240, 128, 128), "indianred": (205, 92, 92), "darkkhaki": (189, 183, 107), "thistle": (216, 191, 216),
    ]

    /// nil for "none", unknown, url() paints and currentColor; .some(color) otherwise.
    /// Returns .none (Optional) for "none"; the outer optional is nil when unparsable.
    static func parse(_ raw: String) -> SVGColor?? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text == "none" || text == "transparent" { return .some(nil) }
        if text.hasPrefix("url(") || text == "currentcolor" || text == "inherit" { return nil }
        if text.hasPrefix("#") {
            let hex = String(text.dropFirst())
            func channel(_ s: Substring) -> CGFloat? { UInt8(s, radix: 16).map { CGFloat($0) / 255 } }
            switch hex.count {
            case 3, 4:
                let chars = Array(hex)
                let parts = chars.map { c -> CGFloat? in UInt8(String([c, c]), radix: 16).map { CGFloat($0) / 255 } }
                guard parts.allSatisfy({ $0 != nil }) else { return nil }
                return .some(SVGColor(red: parts[0]!, green: parts[1]!, blue: parts[2]!, alpha: hex.count == 4 ? parts[3]! : 1))
            case 6, 8:
                let i = hex.startIndex
                guard let r = channel(hex[i..<hex.index(i, offsetBy: 2)]),
                      let g = channel(hex[hex.index(i, offsetBy: 2)..<hex.index(i, offsetBy: 4)]),
                      let b = channel(hex[hex.index(i, offsetBy: 4)..<hex.index(i, offsetBy: 6)]) else { return nil }
                let a = hex.count == 8 ? (channel(hex[hex.index(i, offsetBy: 6)..<hex.index(i, offsetBy: 8)]) ?? 1) : 1
                return .some(SVGColor(red: r, green: g, blue: b, alpha: a))
            default:
                return nil
            }
        }
        if text.hasPrefix("rgb") {
            guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")") else { return nil }
            let parts = text[text.index(after: open)..<close].split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map { String($0) }
            guard parts.count >= 3 else { return nil }
            func channel(_ s: String) -> CGFloat? {
                if s.hasSuffix("%") { return Double(s.dropLast()).map { CGFloat($0) / 100 } }
                return Double(s).map { CGFloat($0) / 255 }
            }
            guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
            var a: CGFloat = 1
            if parts.count >= 4 {
                let s = parts[3]
                a = s.hasSuffix("%") ? CGFloat(Double(s.dropLast()) ?? 100) / 100 : CGFloat(Double(s) ?? 1)
            }
            return .some(SVGColor(red: r, green: g, blue: b, alpha: a))
        }
        if let k = keywords[text] {
            return .some(SVGColor(red: CGFloat(k.0) / 255, green: CGFloat(k.1) / 255, blue: CGFloat(k.2) / 255))
        }
        return nil
    }
}

/// `<style>` rules: `.cls-1{fill:#f00}`, `path{...}`, `#id{...}`, comma lists.
struct SVGStyleSheet {
    struct Rule { let selector: String; let declarations: [String: String] }
    var rules: [Rule] = []

    init(css: String) {
        var text = css
        // Strip comments.
        while let open = text.range(of: "/*"), let close = text.range(of: "*/", range: open.upperBound..<text.endIndex) {
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            let selectors = rest[rest.startIndex..<open].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let declarations = SVGStyleSheet.declarations(String(rest[rest.index(after: open)..<close]))
            for selector in selectors where !selector.isEmpty {
                rules.append(Rule(selector: selector, declarations: declarations))
            }
            rest = rest[rest.index(after: close)...]
        }
    }

    static func declarations(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for part in text.split(separator: ";") {
            let pair = part.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            out[pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = pair[1].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    /// Declarations that apply to an element, in cascade order (element, class, id).
    func declarations(element: String, classes: [String], id: String?) -> [String: String] {
        var out: [String: String] = [:]
        for rule in rules {
            let s = rule.selector
            let matches: Bool
            if s.hasPrefix(".") { matches = classes.contains(String(s.dropFirst())) }
            else if s.hasPrefix("#") { matches = id == String(s.dropFirst()) }
            else if s == "*" { matches = true }
            else if s.contains(".") {
                // element.class
                let parts = s.split(separator: ".", maxSplits: 1)
                matches = parts.count == 2 && parts[0] == element && classes.contains(String(parts[1]))
            } else { matches = s == element }
            if matches { out.merge(rule.declarations) { _, new in new } }
        }
        return out
    }
}

extension SVGStyle {
    /// Apply a property/value pair (presentation attribute or CSS declaration).
    mutating func apply(_ property: String, _ value: String, warnings: inout [String]) {
        switch property {
        case "fill":
            if let c = SVGColorParser.parse(value) { fill = c } else { warnings.append("Unsupported fill \u{201C}\(value)\u{201D} (gradients and patterns are not supported); drawn black.") }
        case "stroke":
            if let c = SVGColorParser.parse(value) { stroke = c } else { warnings.append("Unsupported stroke \u{201C}\(value)\u{201D}.") }
        case "stroke-width":
            if let v = Double(value.replacingOccurrences(of: "px", with: "")) { strokeWidth = CGFloat(v) }
        case "opacity":
            if let v = Double(value) { opacity = CGFloat(v) }
        case "fill-opacity":
            if let v = Double(value) { fillOpacity = CGFloat(v) }
        case "stroke-opacity":
            if let v = Double(value) { strokeOpacity = CGFloat(v) }
        case "fill-rule":
            fillRule = value == "evenodd" ? .evenOdd : .nonZero
        case "stroke-linecap":
            lineCap = value == "round" ? .round : value == "square" ? .square : .butt
        case "stroke-linejoin":
            lineJoin = value == "round" ? .round : value == "bevel" ? .bevel : .miter
        case "display":
            if value == "none" { isHidden = true }
        case "visibility":
            if value == "hidden" || value == "collapse" { isHidden = true }
        default:
            break
        }
    }
}
