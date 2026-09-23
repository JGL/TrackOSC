//
//  SpeakerStore.swift
//  TrackOSC Speaker (macOS)
//
//  Wires the receiver model to the narration engine and the synthesizer:
//  frames arrive on the service's stream, the engine decides, the
//  controller speaks. Settings changes are pushed into the engine's config.
//

import Foundation
import Observation
import PoseioscShared
import os

@Observable @MainActor
final class SpeakerStore {
    let model = ReceiverModel(app: .speaker)
    let settings = SpeakerSettings()
    let voices = VoiceCatalog()
    let speech: SpeechController

    /// The last utterance decided, spoken or not (shown while muted too).
    private(set) var lastUtterance: Utterance?
    private(set) var engineEventCount = 0

    private var engine = NarrationEngine()
    private let log = Logger(subsystem: "com.joelgethinlewis.TrackOSCSpeaker", category: "narration")
    private var transcriptHandle: FileHandle?

    /// Where the transcript file goes: this app's Application Support folder.
    static let transcriptURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("TrackOSC Speaker", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("transcript.txt")
    }()
    private var frameTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    init() {
        speech = SpeechController(settings: settings)
        pushConfig()

        let stream = model.service.frames()
        frameTask = Task { [weak self] in
            for await frame in stream {
                guard let self else { return }
                let now = ContinuousClock.now
                let utterances = engine.ingest(frame, at: now)
                deliver(utterances)
            }
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                pushConfig()
                let utterances = engine.tick(latest: model.latest, at: .now)
                deliver(utterances)
            }
        }
    }

    func speakTest() {
        speech.preview("This is TrackOSC Speaker. One person, nose 52 percent across, 31 percent down. Left hand raised.", voice: nil)
    }

    func summariseNow() {
        if let utterance = engine.summariseNow(latest: model.latest, at: .now) {
            deliver([utterance])
        } else {
            deliver([Utterance(text: "Nobody here.", category: .summary)])
        }
    }

    private func deliver(_ utterances: [Utterance]) {
        for utterance in utterances {
            lastUtterance = utterance
            engineEventCount += 1
            log.notice("\(utterance.category.rawValue, privacy: .public): \(utterance.text, privacy: .public)")
            speech.speak(utterance)
            if settings.saveTranscript { appendToTranscript(utterance) }
        }
    }

    private func appendToTranscript(_ utterance: Utterance) {
        if transcriptHandle == nil {
            let url = Self.transcriptURL
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            transcriptHandle = try? FileHandle(forWritingTo: url)
            try? transcriptHandle?.seekToEnd()
        }
        let time = utterance.createdAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
        let line = "\(time)\t\(utterance.category.rawValue)\t\(utterance.text)\n"
        try? transcriptHandle?.write(contentsOf: Data(line.utf8))
    }

    private func pushConfig() {
        engine.config = NarrationConfig(
            narratedKinds: settings.narratedKinds,
            announceEmpty: settings.announceEmpty,
            summaryInterval: .seconds(settings.summaryInterval),
            verbosity: settings.verbosity,
            textCooldown: .seconds(settings.textCooldown),
            coalesceWindow: .seconds(settings.coalesceWindow)
        )
    }
}
