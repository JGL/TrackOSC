//
//  CanvasRecorder.swift
//  TrackOSC Costumes (macOS)
//
//  Records a CoreGraphics-drawn stage to an H.264 .mp4 in Downloads: each
//  frame is drawn again into a pixel buffer from the writer's pool, on a
//  background queue so the stage never waits.
//

import AVFoundation
import CoreGraphics
import Foundation
import Observation
import Synchronization

@Observable @MainActor
final class CanvasRecorder {
    private(set) var isRecording = false
    private(set) var lastRecording: URL?
    private(set) var lastError: String?
    private(set) var frameCount = 0
    private(set) var startedAt: Date?

    private var box: WriterBox?
    private var width = 0
    private var height = 0
    private let pending = Counter()
    private let queue = DispatchQueue(label: "costumes.recorder")

    var duration: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    func start(appName: String, width: Int, height: Int) {
        guard !isRecording else { return }
        lastError = nil
        let w = max(16, width - width % 2), h = max(16, height - height % 2)
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let url = downloads.appendingPathComponent("\(appName) \(formatter.string(from: .now)).mp4")
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: w,
                AVVideoHeightKey: h,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: w * h * 8, AVVideoExpectedSourceFrameRateKey: 60],
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? NSError(domain: "CanvasRecorder", code: 1) }
            writer.startSession(atSourceTime: .zero)
            box = WriterBox(writer: writer, input: input, adaptor: adaptor)
            self.width = w
            self.height = h
            frameCount = 0
            startedAt = Date()
            isRecording = true
        } catch {
            lastError = "Could not start recording: \(error.localizedDescription)"
        }
    }

    /// Draw a frame with `draw` into a pool buffer (on the recorder's queue) and append it.
    func capture(draw: @escaping @Sendable (CGContext, CGSize) -> Void) {
        guard isRecording, let box, let startedAt, pending.value.load(ordering: .relaxed) < 3, box.input.isReadyForMoreMediaData else { return }
        let time = CMTime(seconds: Date().timeIntervalSince(startedAt), preferredTimescale: 600)
        let w = width, h = height
        pending.value.add(1, ordering: .relaxed)
        frameCount += 1
        let pending = self.pending
        queue.async {
            defer { pending.value.subtract(1, ordering: .relaxed) }
            guard let pool = box.adaptor.pixelBufferPool else { return }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { return }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer),
               let context = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                // CG's origin is bottom-left; flip so the stage's y-down drawing lands the right way up.
                context.translateBy(x: 0, y: CGFloat(h))
                context.scaleBy(x: 1, y: -1)
                draw(context, CGSize(width: w, height: h))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            box.adaptor.append(buffer, withPresentationTime: time)
        }
    }

    func stop() {
        guard isRecording, let box else { return }
        isRecording = false
        self.box = nil
        queue.async { [weak self] in
            box.input.markAsFinished()
            box.writer.finishWriting {
                let ok = box.writer.status == .completed
                let url = box.writer.outputURL
                let message = box.writer.error?.localizedDescription ?? "unknown"
                Task { @MainActor in
                    self?.lastRecording = ok ? url : nil
                    if !ok { self?.lastError = "Recording failed to finish: \(message)" }
                    self?.startedAt = nil
                }
            }
        }
    }
}

/// Frames handed to the queue but not yet appended.
private final class Counter: @unchecked Sendable {
    let value = Atomic<Int>(0)
}

private final class WriterBox: @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    init(writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor) {
        self.writer = writer; self.input = input; self.adaptor = adaptor
    }
}
