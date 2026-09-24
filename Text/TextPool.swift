//
//  TextPool.swift
//  TrackOSC Text
//
//  The words on offer: recognised text and code payloads from the stream
//  (deduplicated, kept for a while after they vanish), plus the user's own
//  text. Every mode draws its letters from here.
//

import Foundation

struct PoolEntry: Identifiable, Equatable {
    enum Source { case recognised, code, user }
    let id: String
    var text: String
    var source: Source
    var firstSeen: Float
    var lastSeen: Float
    var centre: SIMD2<Float>?
    var size: SIMD2<Float>?
}

@MainActor
final class TextPool {
    /// Seconds a recognised text survives after it was last seen.
    var timeToLive: Float = 30
    var userText: String = "TRACKOSC" {
        didSet { rebuildUser() }
    }
    private(set) var entries: [PoolEntry] = []

    init() { rebuildUser() }

    private func rebuildUser() {
        entries.removeAll { $0.source == .user }
        let words = userText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init).filter { !$0.isEmpty }
        for (i, word) in words.enumerated() {
            entries.append(PoolEntry(id: "user-\(i)-\(word)", text: word, source: .user, firstSeen: 0, lastSeen: .infinity, centre: nil, size: nil))
        }
    }

    func update(scene: TrackingScene) {
        for text in scene.texts {
            let key = (text.isCode ? "code:" : "text:") + text.text.uppercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if let index = entries.firstIndex(where: { $0.id == key }) {
                entries[index].lastSeen = scene.time
                entries[index].centre = text.centre
                entries[index].size = text.size
            } else {
                entries.append(PoolEntry(id: key, text: text.text, source: text.isCode ? .code : .recognised,
                                         firstSeen: scene.time, lastSeen: scene.time, centre: text.centre, size: text.size))
            }
        }
        entries.removeAll { $0.source != .user && scene.time - $0.lastSeen > timeToLive }
    }

    /// Words to draw: recognised and code text first (newest first), then the user's.
    func words(at time: Float) -> [PoolEntry] {
        let live = entries.filter { $0.source != .user }.sorted { $0.lastSeen > $1.lastSeen }
        let user = entries.filter { $0.source == .user }
        return live + user
    }

    /// Entries seen in the last half second, with a position.
    func fresh(at time: Float) -> [PoolEntry] {
        entries.filter { $0.source != .user && time - $0.lastSeen < 0.5 && $0.centre != nil }
    }

    /// Every letter of every word, as (character, word index).
    func letters(at time: Float, limit: Int) -> [(Character, Int)] {
        var out: [(Character, Int)] = []
        for (w, entry) in words(at: time).enumerated() {
            for character in entry.text where !character.isWhitespace {
                out.append((character, w))
                if out.count >= limit { return out }
            }
        }
        return out
    }
}
