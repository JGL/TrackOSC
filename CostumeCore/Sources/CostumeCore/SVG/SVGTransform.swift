//
//  SVGTransform.swift
//  CostumeCore
//
//  `transform` attribute lists: matrix, translate, scale, rotate, skewX,
//  skewY, composed left to right as SVG specifies.
//

import CoreGraphics
import Foundation

enum SVGTransform {
    static func parse(_ text: String) -> CGAffineTransform {
        var result = CGAffineTransform.identity
        let scanner = Scanner(string: text)
        scanner.charactersToBeSkipped = .whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        while !scanner.isAtEnd {
            guard let name = scanner.scanCharacters(from: .letters) else { break }
            guard scanner.scanString("(") != nil else { break }
            var numbers: [CGFloat] = []
            while let n = scanner.scanDouble() { numbers.append(CGFloat(n)) }
            _ = scanner.scanString(")")
            let t: CGAffineTransform
            switch name {
            case "matrix" where numbers.count == 6:
                t = CGAffineTransform(a: numbers[0], b: numbers[1], c: numbers[2], d: numbers[3], tx: numbers[4], ty: numbers[5])
            case "translate" where !numbers.isEmpty:
                t = CGAffineTransform(translationX: numbers[0], y: numbers.count > 1 ? numbers[1] : 0)
            case "scale" where !numbers.isEmpty:
                t = CGAffineTransform(scaleX: numbers[0], y: numbers.count > 1 ? numbers[1] : numbers[0])
            case "rotate" where !numbers.isEmpty:
                let angle = numbers[0] * .pi / 180
                if numbers.count >= 3 {
                    t = CGAffineTransform(translationX: numbers[1], y: numbers[2]).rotated(by: angle).translatedBy(x: -numbers[1], y: -numbers[2])
                } else {
                    t = CGAffineTransform(rotationAngle: angle)
                }
            case "skewX" where !numbers.isEmpty:
                t = CGAffineTransform(a: 1, b: 0, c: tan(numbers[0] * .pi / 180), d: 1, tx: 0, ty: 0)
            case "skewY" where !numbers.isEmpty:
                t = CGAffineTransform(a: 1, b: tan(numbers[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
            default:
                continue
            }
            // SVG applies the list left to right: later transforms are nested inside earlier ones.
            result = t.concatenating(result)
        }
        return result
    }
}
