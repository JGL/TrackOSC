//
//  SpriteLayer.swift
//  TrackOSC (VisualCore)
//
//  What an app hands the renderer each frame on top of the mode's
//  background: sprites, line vertices, an optional glyph atlas, and how
//  to blend them. Buffers are triple-buffered so the CPU writes one while
//  the GPU reads another.
//

import Foundation
import Metal

enum SpriteBlend {
    case additive
    case normal
}

struct SpriteBatch {
    var sprites: MTLBuffer
    var spriteCount: Int
    var lines: MTLBuffer?
    var lineVertexCount: Int = 0
    var atlas: MTLTexture?
    var blend: SpriteBlend = .additive
}

/// Triple-buffered sprite and line storage an app writes into per frame.
final class SpriteBuffers {
    let spriteCapacity: Int
    let lineCapacity: Int
    private var spriteBuffers: [MTLBuffer] = []
    private var lineBuffers: [MTLBuffer] = []
    private var index = 0

    init(device: MTLDevice, spriteCapacity: Int, lineCapacity: Int = 4096) {
        self.spriteCapacity = spriteCapacity
        self.lineCapacity = lineCapacity
        for _ in 0..<3 {
            spriteBuffers.append(device.makeBuffer(length: MemoryLayout<GPUSprite>.stride * spriteCapacity, options: .storageModeShared)!)
            lineBuffers.append(device.makeBuffer(length: MemoryLayout<GPULineVertex>.stride * lineCapacity, options: .storageModeShared)!)
        }
    }

    /// Advance to the next buffer pair and hand back writable views of them.
    func next() -> (sprites: UnsafeMutablePointer<GPUSprite>, lines: UnsafeMutablePointer<GPULineVertex>, spriteBuffer: MTLBuffer, lineBuffer: MTLBuffer) {
        index = (index + 1) % 3
        return (spriteBuffers[index].contents().bindMemory(to: GPUSprite.self, capacity: spriteCapacity),
                lineBuffers[index].contents().bindMemory(to: GPULineVertex.self, capacity: lineCapacity),
                spriteBuffers[index], lineBuffers[index])
    }
}

extension GPUSprite {
    static func dot(at position: SIMD2<Float>, size: Float, color: SIMD4<Float>, softness: Float = 0.6) -> GPUSprite {
        var s = GPUSprite()
        s.position = position
        s.size = SIMD2<Float>(size, size)
        s.color = color
        s.kind = 0
        s.softness = softness
        return s
    }

    static func ring(at position: SIMD2<Float>, size: Float, color: SIMD4<Float>) -> GPUSprite {
        var s = GPUSprite()
        s.position = position
        s.size = SIMD2<Float>(size, size)
        s.color = color
        s.kind = 2
        return s
    }
}

/// The screen's extent in scene uv: 0…1 is the sender's frame; in fit mode
/// the screen is wider (or taller) than that.
struct SceneViewport: Sendable {
    var min = SIMD2<Float>(0, 0)
    var max = SIMD2<Float>(1, 1)

    init() {}

    init(frameAspect: Float, viewWidth: Float, viewHeight: Float, fit: FitMode) {
        let viewAspect = viewWidth / Swift.max(viewHeight, 1)
        let frame = Swift.max(frameAspect, 0.01)
        var size = SIMD2<Float>(1, 1)
        switch fit {
        case .fit:
            if frame > viewAspect { size.y = viewAspect / frame } else { size.x = frame / viewAspect }
        case .fill:
            if frame > viewAspect { size.x = frame / viewAspect } else { size.y = viewAspect / frame }
        }
        // The frame occupies `size` of the screen, centred; invert that.
        let origin = (SIMD2<Float>(1, 1) - size) / 2
        min = -origin / size
        max = (SIMD2<Float>(1, 1) - origin) / size
    }

    var width: Float { max.x - min.x }
    var height: Float { max.y - min.y }
    func random() -> SIMD2<Float> { SIMD2(Float.random(in: min.x...max.x), Float.random(in: min.y...max.y)) }
    func contains(_ p: SIMD2<Float>, margin: Float = 0) -> Bool {
        p.x >= min.x - margin && p.x <= max.x + margin && p.y >= min.y - margin && p.y <= max.y + margin
    }
    func wrap(_ p: SIMD2<Float>) -> SIMD2<Float> {
        var q = p
        if q.x < min.x { q.x += width } else if q.x > max.x { q.x -= width }
        if q.y < min.y { q.y += height } else if q.y > max.y { q.y -= height }
        return q
    }
}
