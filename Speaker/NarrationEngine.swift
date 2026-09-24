//
//  NarrationEngine.swift
//  TrackOSC Speaker (macOS)
//
//  Decides what to say. Pure logic over presence events and the latest
//  frames: event sentences (appear, leave, counts, recognised text, codes),
//  coalesced within a short window, plus a periodic summary at one of three
//  verbosities. Nothing here touches the synthesizer.
//

import Foundation
import PoseioscShared

struct Utterance: Identifiable, Equatable, Sendable {
    enum Category: String, Sendable { case event, summary, test }
    let id: UUID
    var text: String
    var category: Category
    var createdAt: Date

    init(text: String, category: Category, createdAt: Date = .now) {
        id = UUID()
        self.text = text
        self.category = category
        self.createdAt = createdAt
    }
}

struct NarrationConfig: Sendable {
    var narratedKinds: Set<FrameKind> = SpeakerSettings.defaultNarratedKinds
    var announceEmpty = true
    var summaryInterval: Duration = .seconds(15)
    var verbosity: Verbosity = .normal
    var textCooldown: Duration = .seconds(30)
    var coalesceWindow: Duration = .milliseconds(250)
}

struct NarrationEngine: Sendable {
    var config = NarrationConfig()
    private var presence = PresenceTracker()
    private var pendingSentences: [String] = []
    private var pendingSince: ContinuousClock.Instant?
    private var lastSummary: ContinuousClock.Instant?
    private var lastSpokenText: [String: ContinuousClock.Instant] = [:]
    private var lastSpokenPayload: [String: ContinuousClock.Instant] = [:]
    private var lastAnimalLabels: Set<String> = []
    private var saidEmpty = false
    private var everSawSomething = false

    /// Feed a decoded frame. Returns utterances that are ready to be spoken.
    mutating func ingest(_ frame: ReceivedFrame, at now: ContinuousClock.Instant) -> [Utterance] {
        guard let kind = frame.kind else { return [] }
        var out: [Utterance] = []

        for event in presence.observe(kind: kind, count: frame.decoded.detectionCount, at: now) {
            if let sentence = sentence(for: event, frame: frame.decoded) {
                queue(sentence, at: now)
            }
        }

        // Text, codes and animal names are only read once their kind has
        // been confirmed present, so "a person appeared" comes first.
        if config.narratedKinds.contains(kind), presence.count(of: kind) > 0 {
            switch frame.decoded {
            case .texts(let f):
                for detection in f.detections {
                    let text = Self.normalise(detection.label)
                    guard text.count >= 2 else { continue }
                    if let last = lastSpokenText[text], now - last < config.textCooldown { continue }
                    lastSpokenText[text] = now
                    queue("I can read: \(text).", at: now)
                }
            case .barcodes(let f):
                for detection in f.detections {
                    let key = detection.symbology + "|" + detection.payload
                    if let last = lastSpokenPayload[key], now - last < config.textCooldown { continue }
                    lastSpokenPayload[key] = now
                    queue("\(Self.spoken(symbology: detection.symbology)): \(Self.spokenPayload(detection.payload)).", at: now)
                }
            case .animals(let f):
                let labels = Set(f.detections.map { $0.label.lowercased() }.filter { !$0.isEmpty })
                for label in labels.subtracting(lastAnimalLabels).sorted() {
                    queue("A \(label) is here.", at: now)
                }
                if !labels.isEmpty { lastAnimalLabels = labels }
            default:
                break
            }
        }

        out += flushPending(at: now, force: false)
        return out
    }

    /// Call at display rate: releases stale kinds, flushes coalesced
    /// sentences, and produces the periodic summary.
    mutating func tick(latest: [FrameKind: TimestampedFrame], at now: ContinuousClock.Instant, wallClock: Date = .now) -> [Utterance] {
        var out: [Utterance] = []
        for event in presence.tick(at: now) {
            if event.kind == .animals, event.change == .left { lastAnimalLabels = [] }
            if let sentence = sentence(for: event, frame: nil) {
                queue(sentence, at: now)
            }
        }
        out += flushPending(at: now, force: false)

        let anyPresent = config.narratedKinds.contains { presence.count(of: $0) > 0 }
        if anyPresent {
            everSawSomething = true
            saidEmpty = false
            if lastSummary == nil {
                // The appearance sentence has just been said; the first
                // summary comes a full interval later.
                lastSummary = now
            } else if config.summaryInterval > .zero, now - lastSummary! >= config.summaryInterval {
                lastSummary = now
                if let text = summary(latest: latest, wallClock: wallClock) {
                    out.append(Utterance(text: text, category: .summary))
                }
            }
        } else {
            lastSummary = nil
            // Wait for any coalescing "left" sentence to go out first.
            if config.announceEmpty, everSawSomething, !saidEmpty, pendingSince == nil {
                saidEmpty = true
                out.append(Utterance(text: "Nobody here.", category: .summary))
            }
        }
        return out
    }

    /// The summary on demand.
    mutating func summariseNow(latest: [FrameKind: TimestampedFrame], at now: ContinuousClock.Instant) -> Utterance? {
        lastSummary = now
        guard let text = summary(latest: latest, wallClock: .now) else { return nil }
        return Utterance(text: text, category: .summary)
    }

    // MARK: - Sentences

    private mutating func queue(_ sentence: String, at now: ContinuousClock.Instant) {
        pendingSentences.append(sentence)
        if pendingSince == nil { pendingSince = now }
    }

    private mutating func flushPending(at now: ContinuousClock.Instant, force: Bool) -> [Utterance] {
        guard let since = pendingSince, force || now - since >= config.coalesceWindow else { return [] }
        let text = pendingSentences.joined(separator: " ")
        pendingSentences = []
        pendingSince = nil
        return text.isEmpty ? [] : [Utterance(text: text, category: .event)]
    }

    private func sentence(for event: PresenceEvent, frame: DecodedFrame?) -> String? {
        guard config.narratedKinds.contains(event.kind) else { return nil }
        let noun = Self.noun(for: event.kind)
        switch event.change {
        case .appeared:
            return event.count == 1 ? "\(noun.a) appeared." : "\(Self.number(event.count)) \(noun.plural) appeared."
        case .left:
            return event.previousCount == 1 ? "\(noun.the) left." : "\(noun.thePlural) left."
        case .countChanged:
            return "\(Self.number(event.count)) \(event.count == 1 ? noun.singular : noun.plural) now."
        }
    }

    private struct Noun {
        var a: String, the: String, singular: String, plural: String, thePlural: String
    }

    private static func noun(for kind: FrameKind) -> Noun {
        switch kind {
        case .poses, .poses3D, .humans:
            Noun(a: "A person", the: "The person", singular: "person", plural: "people", thePlural: "Everyone")
        case .hands:
            Noun(a: "A hand", the: "The hand", singular: "hand", plural: "hands", thePlural: "The hands")
        case .faces, .faceBoxes, .faceContours:
            Noun(a: "A face", the: "The face", singular: "face", plural: "faces", thePlural: "The faces")
        case .texts:
            Noun(a: "Some text", the: "The text", singular: "text", plural: "pieces of text", thePlural: "The text")
        case .animals, .animalPoses:
            Noun(a: "An animal", the: "The animal", singular: "animal", plural: "animals", thePlural: "The animals")
        case .barcodes:
            Noun(a: "A code", the: "The code", singular: "code", plural: "codes", thePlural: "The codes")
        case .contours:
            Noun(a: "An outline", the: "The outline", singular: "outline", plural: "outlines", thePlural: "The outlines")
        case .horizon:
            Noun(a: "The horizon", the: "The horizon", singular: "horizon", plural: "horizons", thePlural: "The horizon")
        case .rectangles:
            Noun(a: "A rectangle", the: "The rectangle", singular: "rectangle", plural: "rectangles", thePlural: "The rectangles")
        }
    }

    private func summary(latest: [FrameKind: TimestampedFrame], wallClock: Date) -> String? {
        var parts: [String] = []

        // Counts, in a fixed order, only for kinds that are narrated and present.
        var counts: [String] = []
        for kind in [FrameKind.poses, .hands, .faces, .animals, .texts, .barcodes] where config.narratedKinds.contains(kind) {
            let n = presence.count(of: kind)
            guard n > 0 else { continue }
            let noun = Self.noun(for: kind)
            counts.append("\(Self.number(n).lowercased()) \(n == 1 ? noun.singular : noun.plural)")
        }
        guard !counts.isEmpty else { return nil }
        parts.append(Self.capitalised(Self.list(counts)) + ".")
        if config.verbosity == .terse { return parts.joined(separator: " ") }

        // Where the first person is and what their hands are doing.
        if config.narratedKinds.contains(.poses), case .poses(let f)? = latest[.poses]?.decoded, let pose = f.detections.first {
            if let nose = FrameMetrics.nose(of: pose, in: (f.width, f.height)) {
                parts.append("Nose \(FrameMetrics.percent(nose.x)) percent across, \(FrameMetrics.percent(nose.y)) percent down.")
            }
            let raised = FrameMetrics.raisedHands(of: pose)
            switch (raised.left, raised.right) {
            case (true, true): parts.append("Both hands raised.")
            case (true, false): parts.append("Left hand raised.")
            case (false, true): parts.append("Right hand raised.")
            default: break
            }
        }
        guard config.verbosity == .detailed else { return parts.joined(separator: " ") }

        if case .faceBoxes(let f)? = latest[.faceBoxes]?.decoded, let face = f.detections.first {
            switch FrameMetrics.turn(of: face) {
            case .left: parts.append("Looking to their left.")
            case .right: parts.append("Looking to their right.")
            case .straight: break
            }
            switch FrameMetrics.tilt(of: face) {
            case .up: parts.append("Head tilted up.")
            case .down: parts.append("Head tilted down.")
            case .level: break
            }
        }
        if case .faces(let f)? = latest[.faces]?.decoded, let face = f.detections.first,
           let openness = FaceLandmarks.mouthOpenness(face.points), openness > 0.35 {
            parts.append("Mouth open.")
        }
        if case .poses3D(let f)? = latest[.poses3D]?.decoded, let pose = f.detections.first {
            if let distance = FrameMetrics.distance(of: pose) {
                parts.append(String(format: "%.1f metres away.", distance))
            }
            if pose.bodyHeight > 0.5 {
                parts.append(String(format: "About %.2f metres tall.", pose.bodyHeight))
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Words

    static func number(_ n: Int) -> String {
        let words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve"]
        return n < words.count ? words[n] : String(n)
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }

    static func capitalised(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    /// Collapses whitespace and trims so the same text read twice matches.
    static func normalise(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func spoken(symbology: String) -> String {
        switch symbology.lowercased() {
        case "qr": "QR code"
        case "ean13", "ean-13": "EAN 13 barcode"
        case "ean8", "ean-8": "EAN 8 barcode"
        case "upce", "upc-e": "UPC E barcode"
        case "code128": "Code 128 barcode"
        case "code39": "Code 39 barcode"
        case "code93": "Code 93 barcode"
        case "pdf417": "PDF 417 code"
        case "aztec": "Aztec code"
        case "datamatrix": "Data Matrix code"
        case "itf14": "ITF 14 barcode"
        default: symbology.isEmpty ? "A code" : "\(symbology) code"
        }
    }

    /// URLs are read as their host and path words, not letter by letter.
    static func spokenPayload(_ payload: String) -> String {
        let trimmed = normalise(payload)
        if let url = URL(string: trimmed), let host = url.host, url.scheme?.hasPrefix("http") == true {
            let path = url.path.split(separator: "/").joined(separator: ", ")
            return path.isEmpty ? host : "\(host), \(path)"
        }
        return trimmed.count > 80 ? String(trimmed.prefix(80)) + ", and more" : trimmed
    }
}
