//
//  SpeechController.swift
//  TrackOSC Speaker (macOS)
//
//  One AVSpeechSynthesizer, our own queue in front of it (AVSpeech's own
//  queue cannot be reordered or capped), and every utterance option
//  applied from the settings at the moment it is spoken.
//

import AVFoundation
import Foundation
import Observation
import os

@Observable @MainActor
final class SpeechController: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    private(set) var isPaused = false
    private(set) var current: Utterance?
    /// The range of `current.text` being spoken right now (for highlighting).
    private(set) var spokenRange: Range<String.Index>?
    private(set) var queued: [Utterance] = []
    private(set) var spoken: [Utterance] = []
    private(set) var spokenCount = 0
    private(set) var droppedCount = 0
    static let transcriptCap = 200

    private let synthesizer = AVSpeechSynthesizer()
    private var inFlight: [ObjectIdentifier: Utterance] = [:]
    private var settings: SpeakerSettings
    /// An utterance waiting for the interrupted one to report its cancel.
    /// Speaking straight after stopSpeaking(at:) can stall the synthesizer.
    private var pendingAfterStop: Utterance?
    private var stopFallback: Task<Void, Never>?
    private let log = Logger(subsystem: "com.joelgethinlewis.TrackOSCSpeaker", category: "speech")

    init(settings: SpeakerSettings) {
        self.settings = settings
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Speaking

    /// Offer an utterance under the queue policy. Summaries never interrupt
    /// events; events may interrupt anything when the policy is latest-wins.
    func speak(_ utterance: Utterance) {
        guard !settings.isMuted else { return }
        switch settings.queuePolicy {
        case .latestWins:
            if let current, current.category == .event, utterance.category == .summary {
                // Let the event finish; the summary can follow.
                queued = [utterance]
                return
            }
            queued.removeAll()
            if synthesizer.isSpeaking {
                droppedCount += current == nil ? 0 : 1
                interrupt(then: utterance)
            } else {
                start(utterance)
            }
        case .queue:
            if synthesizer.isSpeaking {
                queued.append(utterance)
                while queued.count > max(1, settings.queueLimit) {
                    queued.removeFirst()
                    droppedCount += 1
                }
            } else {
                start(utterance)
            }
        }
    }

    func stopAll() {
        queued.removeAll()
        pendingAfterStop = nil
        stopFallback?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        current = nil
        isSpeaking = false
        isPaused = false
    }

    func pause() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.pauseSpeaking(at: settings.stopBoundary.avBoundary)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    /// Speak regardless of mute and policy, interrupting: for previews.
    func preview(_ text: String, voice: AVSpeechSynthesisVoice?) {
        queued.removeAll()
        previewVoice = voice
        let utterance = Utterance(text: text, category: .test)
        if synthesizer.isSpeaking {
            interrupt(then: utterance, boundary: .immediate)
        } else {
            start(utterance)
        }
    }

    private var previewVoice: AVSpeechSynthesisVoice?

    /// Stop what is being said and speak `next` once the cancel is reported
    /// (or after a short fallback, should the report never come).
    private func interrupt(then next: Utterance, boundary: AVSpeechBoundary? = nil) {
        pendingAfterStop = next
        synthesizer.stopSpeaking(at: boundary ?? settings.stopBoundary.avBoundary)
        stopFallback?.cancel()
        stopFallback = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled, let pending = pendingAfterStop else { return }
            log.notice("cancel report did not arrive; speaking anyway")
            pendingAfterStop = nil
            start(pending)
        }
    }

    private func start(_ utterance: Utterance) {
        let voice = utterance.category == .test ? previewVoice : nil
        let av = makeUtterance(utterance, voiceOverride: voice)
        inFlight[ObjectIdentifier(av)] = utterance
        current = utterance
        spokenRange = nil
        log.notice("speak \(utterance.category.rawValue, privacy: .public): \(utterance.text, privacy: .public)")
        synthesizer.speak(av)
    }

    private func makeUtterance(_ utterance: Utterance, voiceOverride: AVSpeechSynthesisVoice?) -> AVSpeechUtterance {
        let av: AVSpeechUtterance
        if settings.useSSML, let ssml = AVSpeechUtterance(ssmlRepresentation: "<speak>\(Self.escapeSSML(utterance.text))</speak>") {
            av = ssml
        } else {
            av = AVSpeechUtterance(string: utterance.text)
        }
        av.voice = voiceOverride ?? settings.voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
        av.rate = min(max(settings.rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        av.pitchMultiplier = min(max(settings.pitchMultiplier, 0.5), 2)
        av.volume = min(max(settings.volume, 0), 1)
        av.preUtteranceDelay = max(0, settings.preUtteranceDelay)
        av.postUtteranceDelay = max(0, settings.postUtteranceDelay)
        av.prefersAssistiveTechnologySettings = settings.prefersAssistiveTechnologySettings
        return av
    }

    private static func escapeSSML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - AVSpeechSynthesizerDelegate (arrives on an arbitrary thread)

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in
            isSpeaking = true
            isPaused = false
            if let u = inFlight[key] { current = u }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let u = inFlight[key], u.id == current?.id, let range = Range(characterRange, in: u.text) else { return }
            spokenRange = range
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance), cancelled: false)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance), cancelled: true)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in isPaused = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in isPaused = false }
    }

    private nonisolated func finished(_ key: ObjectIdentifier, cancelled: Bool) {
        Task { @MainActor in
            if let u = inFlight.removeValue(forKey: key) {
                log.notice("\(cancelled ? "cancelled" : "finished", privacy: .public): \(u.text, privacy: .public)")
                if !cancelled, u.category != .test {
                    spoken.insert(u, at: 0)
                    if spoken.count > Self.transcriptCap { spoken.removeLast() }
                    spokenCount += 1
                }
                if current?.id == u.id {
                    current = nil
                    spokenRange = nil
                }
            }
            isSpeaking = self.synthesizer.isSpeaking
            if let pending = pendingAfterStop {
                pendingAfterStop = nil
                stopFallback?.cancel()
                start(pending)
            } else if !isSpeaking, !queued.isEmpty {
                start(queued.removeFirst())
            }
        }
    }
}
