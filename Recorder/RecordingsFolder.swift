//
//  RecordingsFolder.swift
//  TrackOSC Recorder (macOS)
//
//  Where recordings go: Downloads/TrackOSC Recordings by default, or a
//  folder the user picks, kept across launches as a security-scoped
//  bookmark (the app is sandboxed).
//

import AppKit
import Foundation
import Observation
import PoseioscShared

@Observable @MainActor
final class RecordingsFolder {
    private(set) var url: URL
    private(set) var isCustom = false
    var lastRecording: URL?

    private var scopedURL: URL?
    private static let bookmarkKey = "recordingsFolderBookmark"

    init() {
        url = Self.defaultFolder
        if let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale),
               resolved.startAccessingSecurityScopedResource() {
                scopedURL = resolved
                url = resolved
                isCustom = true
                if stale, let fresh = try? resolved.bookmarkData(options: .withSecurityScope) {
                    UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
                }
            }
        }
    }

    static var defaultFolder: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return downloads.appendingPathComponent("TrackOSC Recordings", isDirectory: true)
    }

    /// A new, unique file URL inside the folder (creating the folder if needed).
    func newRecordingURL(now: Date = .now) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let base = "TrackOSC \(formatter.string(from: now))"
        var candidate = url.appendingPathComponent(base).appendingPathExtension(RecordingFormat.fileExtension)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.appendingPathComponent("\(base) \(n)").appendingPathExtension(RecordingFormat.fileExtension)
            n += 1
        }
        return candidate
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose where TrackOSC Recorder saves recordings."
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        guard let data = try? chosen.bookmarkData(options: .withSecurityScope) else { return }
        scopedURL?.stopAccessingSecurityScopedResource()
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        _ = chosen.startAccessingSecurityScopedResource()
        scopedURL = chosen
        url = chosen
        isCustom = true
    }

    func useDefault() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        url = Self.defaultFolder
        isCustom = false
    }

    func reveal(_ target: URL? = nil) {
        if let target {
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } else {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        }
    }
}
