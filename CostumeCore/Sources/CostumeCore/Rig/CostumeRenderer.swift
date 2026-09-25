//
//  CostumeRenderer.swift
//  CostumeCore
//
//  Draws placed layers into a CGContext: each layer's shapes under its
//  transform, fill then stroke, with the fade opacity.
//

import CoreGraphics
import Foundation

public enum CostumeRenderer {
    /// `base` maps document space to the stage for scenery (a fit of the viewBox); rig layers ignore it.
    /// With `includeScenery` false the scenery is left for `drawScenery`, so several people in one costume share it.
    public static func draw(costume: Costume, placements: [LayerPlacement], base: CGAffineTransform, includeScenery: Bool = true, in context: CGContext) {
        let byID = Dictionary(uniqueKeysWithValues: costume.layers.map { ($0.id, $0) })
        for placement in placements where placement.isVisible {
            guard let layer = byID[placement.layerID] else { continue }
            let isScenery = layer.name.role == .scenery
            if isScenery && !includeScenery { continue }
            context.saveGState()
            context.setAlpha(placement.opacity)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.concatenate(isScenery ? base : placement.transform)
            for shape in layer.shapes { draw(shape, in: context) }
            context.endTransparencyLayer()
            context.restoreGState()
        }
    }

    /// The costume's scenery layers alone, fitted to the stage.
    public static func drawScenery(costume: Costume, base: CGAffineTransform, in context: CGContext) {
        for layer in costume.layers where layer.name.role == .scenery {
            context.saveGState()
            context.concatenate(base)
            for shape in layer.shapes { draw(shape, in: context) }
            context.restoreGState()
        }
    }

    public static func draw(_ shape: SVGShape, in context: CGContext) {
        let style = shape.style
        if let fill = style.fill {
            context.setFillColor(fill.cgColor.copy(alpha: fill.alpha * style.fillOpacity * style.opacity) ?? fill.cgColor)
            context.addPath(shape.path)
            if style.fillRule == .evenOdd { context.fillPath(using: .evenOdd) } else { context.fillPath() }
        }
        if let stroke = style.stroke, style.strokeWidth > 0 {
            context.setStrokeColor(stroke.cgColor.copy(alpha: stroke.alpha * style.strokeOpacity * style.opacity) ?? stroke.cgColor)
            context.setLineWidth(style.strokeWidth)
            context.setLineCap(style.lineCap)
            context.setLineJoin(style.lineJoin)
            context.addPath(shape.path)
            context.strokePath()
        }
    }

    /// Fit the document's viewBox into a rect, keeping aspect, centred.
    public static func fit(viewBox: CGRect, into rect: CGRect) -> CGAffineTransform {
        guard viewBox.width > 0, viewBox.height > 0 else { return .identity }
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let w = viewBox.width * scale, h = viewBox.height * scale
        let ox = rect.minX + (rect.width - w) / 2, oy = rect.minY + (rect.height - h) / 2
        return CGAffineTransform(translationX: -viewBox.minX, y: -viewBox.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: ox, y: oy))
    }
}
