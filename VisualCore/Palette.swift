//
//  Palette.swift
//  TrackOSC (VisualCore)
//
//  Named colour ramps: up to eight stops, interpolated on the GPU and,
//  for swatches, here. Twelve curated ones ship; any can be edited.
//

import Foundation
import SwiftUI

struct RGB: Codable, Equatable, Hashable, Sendable {
    var r: Float, g: Float, b: Float

    init(_ r: Float, _ g: Float, _ b: Float) { self.r = r; self.g = g; self.b = b }
    init(hex: UInt32) {
        r = Float((hex >> 16) & 0xFF) / 255
        g = Float((hex >> 8) & 0xFF) / 255
        b = Float(hex & 0xFF) / 255
    }

    var color: Color { Color(red: Double(r), green: Double(g), blue: Double(b)) }

    @MainActor
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        r = Float(ns.redComponent); g = Float(ns.greenComponent); b = Float(ns.blueComponent)
    }

    func mixed(with other: RGB, _ t: Float) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }
}

struct Palette: Codable, Equatable, Hashable, Identifiable, Sendable {
    var name: String
    var stops: [RGB]

    var id: String { name }
    static let maxStops = 8

    init(_ name: String, _ hexes: [UInt32]) {
        self.name = name
        self.stops = hexes.prefix(Self.maxStops).map(RGB.init(hex:))
    }

    init(name: String, stops: [RGB]) {
        self.name = name
        self.stops = Array(stops.prefix(Self.maxStops))
    }

    /// Colour at 0…1 along the ramp (looping, like the shader).
    func color(at t: Float) -> RGB {
        guard stops.count > 1 else { return stops.first ?? RGB(1, 1, 1) }
        let x = (t - floorf(t)) * Float(stops.count)
        let i = Int(x) % stops.count
        let j = (i + 1) % stops.count
        return stops[i].mixed(with: stops[j], x - floorf(x))
    }

    static let curated: [Palette] = [
        Palette("Sunset", [0xFF5E62, 0xFF9966, 0xFFD166, 0x8E44AD, 0x2C3E50]),
        Palette("Ocean", [0x03045E, 0x0077B6, 0x00B4D8, 0x90E0EF, 0xCAF0F8]),
        Palette("Neon", [0xFF00FF, 0x00FFFF, 0xFFFF00, 0xFF0080, 0x00FF80]),
        Palette("Pastel", [0xFFB3BA, 0xFFDFBA, 0xFFFFBA, 0xBAFFC9, 0xBAE1FF]),
        Palette("Ember", [0x1A0000, 0x7A1E00, 0xE85D04, 0xFAA307, 0xFFE8A3]),
        Palette("Forest", [0x0B2E13, 0x1B5E20, 0x43A047, 0xA5D6A7, 0xF1F8E9]),
        Palette("Mono", [0x000000, 0x404040, 0x808080, 0xC0C0C0, 0xFFFFFF]),
        Palette("Candy", [0xFF6FB5, 0xFFC1E3, 0xB5EAD7, 0xC7CEEA, 0xFFDAC1]),
        Palette("Aurora", [0x001219, 0x005F73, 0x0A9396, 0x94D2BD, 0xE9D8A6, 0xEE9B00]),
        Palette("Ice", [0x0D1B2A, 0x1B263B, 0x415A77, 0x778DA9, 0xE0E1DD]),
        Palette("Lava", [0x000000, 0x3D0000, 0xB00000, 0xFF4500, 0xFFD700]),
        Palette("Rainbow", [0xFF0000, 0xFF8800, 0xFFFF00, 0x00CC00, 0x0066FF, 0x8800FF]),
    ]

    static var `default`: Palette { curated[0] }
}
