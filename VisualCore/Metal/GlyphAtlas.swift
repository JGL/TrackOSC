//
//  GlyphAtlas.swift
//  TrackOSC (VisualCore)
//
//  Every character the text app may need, rendered once with Core Text
//  into one alpha texture; letters are then sprites with a uv rect.
//

import AppKit
import CoreText
import Foundation
import Metal

struct Glyph: Sendable {
    /// Atlas rect u0 v0 u1 v1.
    let uv: SIMD4<Float>
    /// Glyph box size in points at the atlas font size.
    let size: SIMD2<Float>
    /// Horizontal advance in points at the atlas font size.
    let advance: Float
}

@MainActor
final class GlyphAtlas {
    let texture: MTLTexture
    let fontSize: CGFloat
    private(set) var glyphs: [Character: Glyph] = [:]
    let fontName: String

    static let defaultCharacters: String = {
        let ascii = (32...126).compactMap { UnicodeScalar($0).map(Character.init) }
        let extra = "£€–\u{2014}…‘’“”•°àáâäãåæçèéêëìíîïñòóôöõøùúûüýÿÀÁÂÄÃÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÖÕØÙÚÛÜÝ"
        return String(ascii) + extra
    }()

    init?(device: MTLDevice, fontName: String = "Helvetica-Bold", fontSize: CGFloat = 96, characters: String = GlyphAtlas.defaultCharacters) {
        self.fontName = fontName
        self.fontSize = fontSize
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.boldSystemFont(ofSize: fontSize)
        let cell = Int(fontSize * 1.4)
        let unique = Array(Set(characters.map { $0 })).sorted()
        let columns = 16
        let rows = (unique.count + columns - 1) / columns
        let width = columns * cell, height = max(rows, 1) * cell
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Draw with the origin at the top-left so memory rows, drawing rows
        // and texture rows all agree (no flips anywhere).
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(gray: 1, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        for (i, character) in unique.enumerated() {
            let column = i % columns, row = i / columns
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(character), attributes: attributes))
            let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
            // Centre the glyph's ink in its cell. With the flipped CTM, text
            // is drawn upside down unless we flip it back per glyph.
            let cellX = CGFloat(column * cell), cellY = CGFloat(row * cell)
            let inkX = cellX + (CGFloat(cell) - bounds.width) / 2
            let inkTop = cellY + (CGFloat(cell) - bounds.height) / 2
            context.saveGState()
            context.translateBy(x: inkX - bounds.minX, y: inkTop + bounds.height + bounds.minY)
            context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
            let margin: CGFloat = 4
            let x0 = inkX - margin, y0 = inkTop - margin
            let w = bounds.width + margin * 2, h = bounds.height + margin * 2
            let uv = SIMD4<Float>(Float(x0 / CGFloat(width)), Float(y0 / CGFloat(height)),
                                  Float((x0 + w) / CGFloat(width)), Float((y0 + h) / CGFloat(height)))
            glyphs[character] = Glyph(uv: uv, size: SIMD2<Float>(Float(w), Float(h)), advance: Float(advance))
        }
        guard let data = context.data else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: context.bytesPerRow)
        self.texture = texture
    }

    func glyph(for character: Character) -> Glyph? {
        glyphs[character] ?? glyphs[Character(character.uppercased())] ?? glyphs["?"]
    }

    /// Total advance of a string at the atlas size.
    func width(of text: String) -> Float {
        text.reduce(0) { $0 + (glyph(for: $1)?.advance ?? 0) }
    }
}

extension GPUSprite {
    /// A glyph sprite `height` pixels tall at `position` (its centre).
    static func glyph(_ glyph: Glyph, at position: SIMD2<Float>, height: Float, color: SIMD4<Float>, rotation: Float = 0, atlasFontSize: Float) -> GPUSprite {
        var s = GPUSprite()
        s.position = position
        let scale = height / atlasFontSize
        s.size = glyph.size * scale
        s.color = color
        s.uv = glyph.uv
        s.rotation = rotation
        s.kind = 1
        return s
    }
}
