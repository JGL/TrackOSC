//
//  StageRecorder.swift
//  TrackOSC (VisualCore)
//
//  Records the rendered frames to an H.264 .mp4 in Downloads. The renderer
//  draws each frame's post pass a second time into a Metal texture backed
//  by a CVPixelBuffer from the writer's pool, so nothing is read back
//  through the CPU; the command buffer's completion appends the frame.
//

import AVFoundation
import CoreVideo
import Foundation
import Metal
import Observation

/// One frame in flight: the pixel buffer the GPU renders into, its Metal
/// view and its timestamp. CVPixelBuffer is not marked Sendable, but the
/// buffer is only ever touched by the GPU and then by the writer's queue,
/// one after the other, so passing the handle across is safe.
final class RecorderFrame: @unchecked Sendable {
    let texture: MTLTexture
    let pixelBuffer: CVPixelBuffer
    let time: CMTime

    init(texture: MTLTexture, pixelBuffer: CVPixelBuffer, time: CMTime) {
        self.texture = texture
        self.pixelBuffer = pixelBuffer
        self.time = time
    }
}

/// The part that runs off the main actor: the writer and the GPU frames.
final class RecorderSink: @unchecked Sendable {
    let url: URL
    let width: Int
    let height: Int
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var textureCache: CVMetalTextureCache?
    private let queue = DispatchQueue(label: "trackosc.recorder", qos: .userInitiated)
    private let lock = NSLock()
    private var started = false
    private var finished = false
    private(set) var frameCount = 0
    private(set) var droppedCount = 0
    private let startTime = CACurrentMediaTime()

    init(url: URL, width: Int, height: Int, device: MTLDevice) throws {
        self.url = url
        // H.264 wants even dimensions.
        self.width = width - width % 2
        self.height = height - height % 2
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let bitsPerSecond = max(4_000_000, self.width * self.height * 7)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: self.width,
            AVVideoHeightKey: self.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitsPerSecond,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: self.width,
            kCVPixelBufferHeightKey as String: self.height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { throw RecorderError.cannotAddInput }
        writer.add(input)
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        guard writer.startWriting() else { throw writer.error ?? RecorderError.cannotStart }
        writer.startSession(atSourceTime: .zero)
        started = true
    }

    /// A pixel buffer from the pool with a Metal texture view of it, or nil
    /// when the writer is busy (the frame is dropped, never queued).
    func dequeueFrame() -> RecorderFrame? {
        lock.lock()
        defer { lock.unlock() }
        guard started, !finished, input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool, let cache = textureCache else {
            droppedCount += 1
            return nil
        }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let pixelBuffer else { droppedCount += 1; return nil }
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { droppedCount += 1; return nil }
        let seconds = CACurrentMediaTime() - startTime
        return RecorderFrame(texture: texture, pixelBuffer: pixelBuffer, time: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    /// Called from the command buffer's completion handler once the GPU has
    /// finished with the frame.
    func append(_ frame: RecorderFrame) {
        queue.async { [self] in
            lock.lock()
            defer { lock.unlock() }
            guard started, !finished, input.isReadyForMoreMediaData else { droppedCount += 1; return }
            if adaptor.append(frame.pixelBuffer, withPresentationTime: frame.time) { frameCount += 1 } else { droppedCount += 1 }
        }
    }

    private func markFinished() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    func finish() async -> URL? {
        markFinished()
        // Let queued appends land first.
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }

    var duration: TimeInterval { CACurrentMediaTime() - startTime }
}

enum RecorderError: LocalizedError {
    case cannotAddInput, cannotStart, noDevice
    var errorDescription: String? {
        switch self {
        case .cannotAddInput: "The video writer refused the input"
        case .cannotStart: "The video writer could not start"
        case .noDevice: "No Metal device"
        }
    }
}

@Observable @MainActor
final class StageRecorder {
    private(set) var sink: RecorderSink?
    private(set) var lastRecording: URL?
    private(set) var lastError: String?
    var isRecording: Bool { sink != nil }
    var duration: TimeInterval { sink?.duration ?? 0 }
    var frameCount: Int { sink?.frameCount ?? 0 }

    func start(appName: String, width: Int, height: Int, device: MTLDevice) {
        guard sink == nil else { return }
        lastError = nil
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let url = downloads.appendingPathComponent("\(appName) \(formatter.string(from: .now)).mp4")
        do {
            sink = try RecorderSink(url: url, width: width, height: height, device: device)
        } catch {
            lastError = "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard let sink else { return }
        self.sink = nil
        Task { [weak self] in
            let url = await sink.finish()
            await MainActor.run {
                self?.lastRecording = url
                if url == nil { self?.lastError = "Recording failed to finish" }
            }
        }
    }

    func toggle(appName: String, width: Int, height: Int, device: MTLDevice) {
        if isRecording { stop() } else { start(appName: appName, width: width, height: height, device: device) }
    }
}
