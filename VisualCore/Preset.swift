//
//  Preset.swift
//  TrackOSC (VisualCore)
//
//  Nine numbered slots per app, saved as JSON in Application Support.
//

import Foundation

struct VisualPreset: Codable, Equatable, Sendable {
    var name: String
    var mode: String
    var params: ParameterValues
    var palette: Palette
}

@MainActor
final class PresetStore {
    static let slotCount = 9
    private(set) var slots: [VisualPreset?]
    private let url: URL

    init(appFolder: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent(appFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("presets.json")
        if let data = try? Data(contentsOf: url), let loaded = try? JSONDecoder().decode([VisualPreset?].self, from: data), loaded.count == Self.slotCount {
            slots = loaded
        } else {
            slots = Array(repeating: nil, count: Self.slotCount)
        }
    }

    func save(_ preset: VisualPreset, in slot: Int) {
        guard slots.indices.contains(slot) else { return }
        slots[slot] = preset
        persist()
    }

    func clear(_ slot: Int) {
        guard slots.indices.contains(slot) else { return }
        slots[slot] = nil
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(slots) { try? data.write(to: url, options: .atomic) }
    }
}
