//
//  SVGPath.swift
//  CostumeCore
//
//  The full path data grammar: M L H V C S Q T A Z, absolute and
//  relative, implicit repeats, arcs converted to cubic Béziers.
//

import CoreGraphics
import Foundation

enum SVGPath {
    static func parse(_ d: String) -> CGPath? {
        let path = CGMutablePath()
        let scanner = Scanner(string: d)
        scanner.charactersToBeSkipped = .whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?      // for S/T reflection
        var lastCommand: Character = " "
        var command: Character = " "

        func number() -> CGFloat? {
            // Path data allows "1.5.5" and "1-2"; Scanner handles the sign, and dots split as separate scans.
            if let d = scanner.scanDouble() { return CGFloat(d) }
            return nil
        }
        func flag() -> Bool? {
            // Arc flags may be written without separators ("00" or "01").
            guard let c = scanner.scanCharacter() else { return nil }
            if c == "0" { return false }
            if c == "1" { return true }
            return nil
        }

        while !scanner.isAtEnd {
            let position = scanner.currentIndex
            if let c = scanner.scanCharacter(), c.isLetter {
                command = c
            } else {
                scanner.currentIndex = position
                // Implicit repeat: M becomes L, m becomes l.
                if command == "M" { command = "L" } else if command == "m" { command = "l" }
                if command == " " { return nil }
            }
            let relative = command.isLowercase
            let base = relative ? current : .zero
            switch command.uppercased() {
            case "M":
                guard let x = number(), let y = number() else { return path.isEmpty ? nil : path }
                current = CGPoint(x: base.x + x, y: base.y + y)
                start = current
                path.move(to: current)
                lastControl = nil
            case "L":
                guard let x = number(), let y = number() else { return path }
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addLine(to: current)
                lastControl = nil
            case "H":
                guard let x = number() else { return path }
                current = CGPoint(x: (relative ? current.x : 0) + x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "V":
                guard let y = number() else { return path }
                current = CGPoint(x: current.x, y: (relative ? current.y : 0) + y)
                path.addLine(to: current)
                lastControl = nil
            case "C":
                guard let x1 = number(), let y1 = number(), let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return path }
                let c1 = CGPoint(x: base.x + x1, y: base.y + y1), c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastControl = c2
            case "S":
                guard let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return path }
                let c1: CGPoint
                if let lc = lastControl, "CcSs".contains(lastCommand) {
                    c1 = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                } else { c1 = current }
                let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastControl = c2
            case "Q":
                guard let x1 = number(), let y1 = number(), let x = number(), let y = number() else { return path }
                let c = CGPoint(x: base.x + x1, y: base.y + y1)
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addQuadCurve(to: current, control: c)
                lastControl = c
            case "T":
                guard let x = number(), let y = number() else { return path }
                let c: CGPoint
                if let lc = lastControl, "QqTt".contains(lastCommand) {
                    c = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                } else { c = current }
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addQuadCurve(to: current, control: c)
                lastControl = c
            case "A":
                guard let rx = number(), let ry = number(), let rotation = number(), let large = flag(), let sweep = flag(), let x = number(), let y = number() else { return path }
                let end = CGPoint(x: base.x + x, y: base.y + y)
                addArc(to: path, from: current, to: end, rx: rx, ry: ry, rotationDegrees: rotation, largeArc: large, sweep: sweep)
                current = end
                lastControl = nil
            case "Z":
                path.closeSubpath()
                current = start
                lastControl = nil
            default:
                return path.isEmpty ? nil : path
            }
            lastCommand = command
        }
        return path.isEmpty ? nil : path
    }

    /// SVG arc (endpoint parameterisation) → centre parameterisation → cubic segments.
    static func addArc(to path: CGMutablePath, from p1: CGPoint, to p2: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat, rotationDegrees: CGFloat, largeArc: Bool, sweep: Bool) {
        if p1 == p2 { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 { path.addLine(to: p2); return }
        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p1.x - p2.x) / 2, dy = (p1.y - p2.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        // Scale radii up if the arc cannot fit.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den == 0 ? 0 : sqrt(max(0, num / den))
        if largeArc == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        // Split into segments of at most 90°.
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        var t1 = theta1
        for _ in 0..<segments {
            let t2 = t1 + step
            let alpha = sin(step) * (sqrt(4 + 3 * tan(step / 2) * tan(step / 2)) - 1) / 3
            func point(_ t: CGFloat) -> CGPoint {
                let ex = rx * cos(t), ey = ry * sin(t)
                return CGPoint(x: cosPhi * ex - sinPhi * ey + cx, y: sinPhi * ex + cosPhi * ey + cy)
            }
            func derivative(_ t: CGFloat) -> CGPoint {
                let ex = -rx * sin(t), ey = ry * cos(t)
                return CGPoint(x: cosPhi * ex - sinPhi * ey, y: sinPhi * ex + cosPhi * ey)
            }
            let pStart = point(t1), pEnd = point(t2)
            let dStart = derivative(t1), dEnd = derivative(t2)
            let c1 = CGPoint(x: pStart.x + alpha * dStart.x, y: pStart.y + alpha * dStart.y)
            let c2 = CGPoint(x: pEnd.x - alpha * dEnd.x, y: pEnd.y - alpha * dEnd.y)
            path.addCurve(to: pEnd, control1: c1, control2: c2)
            t1 = t2
        }
    }
}
