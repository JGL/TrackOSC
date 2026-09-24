//
//  MetalRenderer.swift
//  TrackOSC (VisualCore)
//
//  Full-screen fragment modes over a scene uniform block, rendered into a
//  ping-pong pair of rgba16Float textures (so modes can read the previous
//  frame) and presented through a post pass. Also renders offscreen for
//  screenshots and the --snapshot-dir check.
//

import AppKit
import Foundation
import Metal
import MetalKit
import simd

/// Everything a frame needs besides the scene.
struct RenderInputs {
    var fragment: String
    var params: [Float]          // packed, VC_MAX_PARAMS long
    var palette: Palette
    var fitMode: FitMode
    var vignette: Float
    var grain: Float
    var gamma: Float
    var usesFeedback: Bool
}

@MainActor
final class MetalRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var presentPipeline: MTLRenderPipelineState?
    private var textures: [MTLTexture] = []
    private var textureIndex = 0
    private var uniformBuffers: [MTLBuffer] = []
    private var personBuffers: [MTLBuffer] = []
    private var handBuffers: [MTLBuffer] = []
    private var faceBuffers: [MTLBuffer] = []
    private var bufferIndex = 0
    private let inflight = DispatchSemaphore(value: 3)
    private var frame: Int32 = 0
    private(set) var lastError: String?
    private var lastFragment = ""
    private var feedbackValid = false

    static let offscreenFormat = MTLPixelFormat.rgba16Float

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        self.device = device
        self.queue = queue
        self.library = library
        for _ in 0..<3 {
            uniformBuffers.append(device.makeBuffer(length: MemoryLayout<SceneUniforms>.stride, options: .storageModeShared)!)
            personBuffers.append(device.makeBuffer(length: MemoryLayout<GPUPerson>.stride * Int(VC_MAX_PERSONS), options: .storageModeShared)!)
            handBuffers.append(device.makeBuffer(length: MemoryLayout<GPUHand>.stride * Int(VC_MAX_HANDS), options: .storageModeShared)!)
            faceBuffers.append(device.makeBuffer(length: MemoryLayout<GPUFace>.stride * Int(VC_MAX_FACES), options: .storageModeShared)!)
        }
    }

    /// Every fragment function the library exposes (for validating catalogues).
    var availableFragments: Set<String> { Set(library.functionNames) }

    // MARK: - Pipelines

    private func pipeline(for fragment: String) -> MTLRenderPipelineState? {
        if let cached = pipelines[fragment] { return cached }
        guard let vertex = library.makeFunction(name: "vc_fullscreen_vertex"),
              let function = library.makeFunction(name: fragment) else {
            lastError = "Shader \(fragment) not found"
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = function
        descriptor.colorAttachments[0].pixelFormat = Self.offscreenFormat
        do {
            let state = try device.makeRenderPipelineState(descriptor: descriptor)
            pipelines[fragment] = state
            return state
        } catch {
            lastError = "Pipeline \(fragment): \(error.localizedDescription)"
            return nil
        }
    }

    private func present(for format: MTLPixelFormat) -> MTLRenderPipelineState? {
        if let presentPipeline, presentPipeline.label == "present-\(format.rawValue)" { return presentPipeline }
        guard let vertex = library.makeFunction(name: "vc_fullscreen_vertex"),
              let function = library.makeFunction(name: "vc_present") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "present-\(format.rawValue)"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = function
        descriptor.colorAttachments[0].pixelFormat = format
        presentPipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        return presentPipeline
    }

    private func ensureTextures(width: Int, height: Int) {
        if let first = textures.first, first.width == width, first.height == height { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.offscreenFormat, width: max(width, 1), height: max(height, 1), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        textures = (0..<2).compactMap { _ in device.makeTexture(descriptor: descriptor) }
        feedbackValid = false
    }

    // MARK: - Drawing

    /// Draw one frame into the view's drawable.
    func draw(scene: TrackingScene, inputs: RenderInputs, in view: MTKView) {
        guard let drawable = view.currentDrawable, let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer() else { return }
        let width = Int(view.drawableSize.width), height = Int(view.drawableSize.height)
        guard width > 0, height > 0 else { return }
        inflight.wait()
        commandBuffer.addCompletedHandler { [inflight] _ in inflight.signal() }
        encode(scene: scene, inputs: inputs, width: width, height: height, commandBuffer: commandBuffer)
        if let presentPipeline = present(for: view.colorPixelFormat),
           let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) {
            encoder.setRenderPipelineState(presentPipeline)
            encoder.setFragmentBuffer(uniformBuffers[bufferIndex], offset: 0, index: 0)
            encoder.setFragmentTexture(textures[textureIndex], index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        advance()
    }

    /// Render offscreen and return the image (for screenshots and checks).
    func snapshot(scene: TrackingScene, inputs: RenderInputs, width: Int, height: Int, warmupFrames: Int = 0) -> CGImage? {
        for _ in 0..<warmupFrames {
            guard let commandBuffer = queue.makeCommandBuffer() else { return nil }
            encode(scene: scene, inputs: inputs, width: width, height: height, commandBuffer: commandBuffer)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            advance()
        }
        guard let commandBuffer = queue.makeCommandBuffer() else { return nil }
        encode(scene: scene, inputs: inputs, width: width, height: height, commandBuffer: commandBuffer)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor), let presentPipeline = present(for: .bgra8Unorm) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.setRenderPipelineState(presentPipeline)
        encoder.setFragmentBuffer(uniformBuffers[bufferIndex], offset: 0, index: 0)
        encoder.setFragmentTexture(textures[textureIndex], index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        advance()

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: colorSpace, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private func advance() {
        bufferIndex = (bufferIndex + 1) % uniformBuffers.count
        textureIndex = (textureIndex + 1) % 2
        frame &+= 1
    }

    /// Runs the mode into the current offscreen texture, reading the other.
    private func encode(scene: TrackingScene, inputs: RenderInputs, width: Int, height: Int, commandBuffer: MTLCommandBuffer) {
        ensureTextures(width: width, height: height)
        if inputs.fragment != lastFragment {
            lastFragment = inputs.fragment
            feedbackValid = false
        }
        pack(scene: scene, inputs: inputs, width: width, height: height)
        guard let pipeline = pipeline(for: inputs.fragment), textures.count == 2 else { return }
        let target = textures[textureIndex]
        let previous = textures[(textureIndex + 1) % 2]
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBuffer(uniformBuffers[bufferIndex], offset: 0, index: 0)
        encoder.setFragmentBuffer(personBuffers[bufferIndex], offset: 0, index: 1)
        encoder.setFragmentBuffer(handBuffers[bufferIndex], offset: 0, index: 2)
        encoder.setFragmentBuffer(faceBuffers[bufferIndex], offset: 0, index: 3)
        encoder.setFragmentTexture(previous, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        feedbackValid = true
    }

    // MARK: - Packing

    private func pack(scene: TrackingScene, inputs: RenderInputs, width: Int, height: Int) {
        var u = SceneUniforms()
        u.resolution = SIMD2<Float>(Float(width), Float(height))
        let viewAspect = Float(width) / Float(max(height, 1))
        u.aspect = viewAspect
        // Where the sender's frame lands in uv space.
        let frameAspect = max(scene.frameAspect, 0.01)
        var size = SIMD2<Float>(1, 1)
        switch inputs.fitMode {
        case .fit:
            if frameAspect > viewAspect { size.y = viewAspect / frameAspect } else { size.x = frameAspect / viewAspect }
        case .fill:
            if frameAspect > viewAspect { size.x = frameAspect / viewAspect } else { size.y = viewAspect / frameAspect }
        }
        u.sceneSize = size
        u.sceneOrigin = (SIMD2<Float>(1, 1) - size) / 2
        u.time = scene.time
        u.dt = scene.deltaTime
        u.presence = scene.presence
        u.activity = scene.activity
        u.isAttract = scene.isAttract ? 1 : 0
        u.personCount = Int32(min(scene.persons.count, Int(VC_MAX_PERSONS)))
        u.handCount = Int32(min(scene.hands.count, Int(VC_MAX_HANDS)))
        u.faceCount = Int32(min(scene.faces.count, Int(VC_MAX_FACES)))
        u.frame = frame
        withUnsafeMutableBytes(of: &u.params) { raw in
            let floats = raw.bindMemory(to: Float.self)
            for (i, v) in inputs.params.prefix(Int(VC_MAX_PARAMS)).enumerated() { floats[i] = v }
        }
        withUnsafeMutableBytes(of: &u.palette) { raw in
            let colours = raw.bindMemory(to: SIMD4<Float>.self)
            for (i, stop) in inputs.palette.stops.prefix(Int(VC_MAX_PALETTE)).enumerated() {
                colours[i] = SIMD4<Float>(stop.r, stop.g, stop.b, 1)
            }
        }
        u.paletteCount = Int32(min(inputs.palette.stops.count, Int(VC_MAX_PALETTE)))
        u.vignette = inputs.vignette
        u.grain = inputs.grain
        u.gamma = inputs.gamma
        u.feedbackAvailable = (inputs.usesFeedback && feedbackValid) ? 1 : 0
        u.seed = Float(frame % 1000) / 1000
        uniformBuffers[bufferIndex].contents().copyMemory(from: &u, byteCount: MemoryLayout<SceneUniforms>.stride)

        let persons = personBuffers[bufferIndex].contents().bindMemory(to: GPUPerson.self, capacity: Int(VC_MAX_PERSONS))
        for (i, person) in scene.persons.prefix(Int(VC_MAX_PERSONS)).enumerated() {
            var gpu = GPUPerson()
            withUnsafeMutableBytes(of: &gpu.joints) { raw in
                let p = raw.bindMemory(to: SIMD2<Float>.self)
                for j in 0..<min(person.joints.count, Int(VC_BODY_JOINTS)) { p[j] = person.joints[j] }
            }
            withUnsafeMutableBytes(of: &gpu.visible) { raw in
                let p = raw.bindMemory(to: Float.self)
                for j in 0..<min(person.visible.count, Int(VC_BODY_JOINTS)) { p[j] = person.visible[j] ? 1 : 0 }
            }
            withUnsafeMutableBytes(of: &gpu.velocities) { raw in
                let p = raw.bindMemory(to: SIMD2<Float>.self)
                for j in 0..<min(person.velocities.count, Int(VC_BODY_JOINTS)) { p[j] = person.velocities[j] }
            }
            gpu.centroid = person.centroid
            gpu.boxMin = person.boundingBox.min
            gpu.boxMax = person.boundingBox.max
            gpu.id = Float(person.id)
            gpu.age = person.age
            gpu.confidence = person.confidence
            gpu.speed = person.speed
            persons[i] = gpu
        }
        let hands = handBuffers[bufferIndex].contents().bindMemory(to: GPUHand.self, capacity: Int(VC_MAX_HANDS))
        for (i, hand) in scene.hands.prefix(Int(VC_MAX_HANDS)).enumerated() {
            var gpu = GPUHand()
            withUnsafeMutableBytes(of: &gpu.joints) { raw in
                let p = raw.bindMemory(to: SIMD2<Float>.self)
                for j in 0..<min(hand.joints.count, Int(VC_HAND_JOINTS)) { p[j] = hand.joints[j] }
            }
            withUnsafeMutableBytes(of: &gpu.visible) { raw in
                let p = raw.bindMemory(to: Float.self)
                for j in 0..<min(hand.visible.count, Int(VC_HAND_JOINTS)) { p[j] = hand.visible[j] ? 1 : 0 }
            }
            gpu.centre = hand.centre
            gpu.openness = hand.openness
            gpu.isLeft = hand.isLeft.map { $0 ? 1 : 0 } ?? -1
            gpu.person = Float(hand.personID ?? -1)
            hands[i] = gpu
        }
        let faces = faceBuffers[bufferIndex].contents().bindMemory(to: GPUFace.self, capacity: Int(VC_MAX_FACES))
        for (i, face) in scene.faces.prefix(Int(VC_MAX_FACES)).enumerated() {
            var gpu = GPUFace()
            gpu.centre = face.centre
            gpu.size = face.size
            gpu.yaw = face.yawDegrees
            gpu.pitch = face.pitchDegrees
            gpu.roll = face.rollDegrees
            gpu.mouth = face.mouthOpenness
            gpu.person = Float(face.personID ?? -1)
            faces[i] = gpu
        }
    }
}
