//
//  Parameters.swift
//  TrackOSC (VisualCore)
//
//  Typed, ranged parameters a visual mode exposes. Values live in a
//  dictionary keyed by parameter id so presets stay readable JSON.
//

import Foundation

struct ParameterSpec: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let range: ClosedRange<Float>
    let defaultValue: Float
    /// Shown after the value in the inspector ("×", "s", "%").
    var unit: String = ""

    init(_ id: String, _ name: String, _ range: ClosedRange<Float>, default defaultValue: Float, unit: String = "") {
        self.id = id
        self.name = name
        self.range = range
        self.defaultValue = defaultValue
        self.unit = unit
    }
}

typealias ParameterValues = [String: Float]

extension Array where Element == ParameterSpec {
    var defaults: ParameterValues {
        Dictionary(uniqueKeysWithValues: map { ($0.id, $0.defaultValue) })
    }

    /// Random values within each range (not too extreme: the middle 90 %).
    func randomised() -> ParameterValues {
        Dictionary(uniqueKeysWithValues: map { spec in
            let span = spec.range.upperBound - spec.range.lowerBound
            return (spec.id, spec.range.lowerBound + span * Float.random(in: 0.05...0.95))
        })
    }

    /// Values in spec order, clamped, padded to `count` with zeros (the GPU array).
    func packed(_ values: ParameterValues, count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        for (i, spec) in prefix(count).enumerated() {
            let v = values[spec.id] ?? spec.defaultValue
            out[i] = Swift.min(Swift.max(v, spec.range.lowerBound), spec.range.upperBound)
        }
        return out
    }
}
