//
//  CostumeLibrary.swift
//  TrackOSC Costumes (macOS)
//
//  The costumes on offer: the bundled ones and every .svg in a folder the
//  user picks (remembered as a security-scoped bookmark), reloaded when a
//  file changes so a drawing app can be kept open beside the stage.
//

import AppKit
import CostumeCore
import Foundation
import Observation

struct CostumeEntry: Identifiable, Hashable {
    let id: String        // path
    let name: String
    let url: URL
    let isBundled: Bool
}

@Observable @MainActor
final class CostumeLibrary {
    private(set) var entries: [CostumeEntry] = []
    private(set) var folderURL: URL?
    private(set) var folderError: String?
    /// Bumped whenever a file in the folder changes, so the store reloads the current costume.
    private(set) var changeCount = 0

    private static let bookmarkKey = "costumesFolderBookmark"
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedDescriptor: Int32 = -1
    private var rescanTask: Task<Void, Never>?

    init() {
        restoreFolder()
        rescan()
    }

    var bundled: [CostumeEntry] { entries.filter(\.isBundled) }
    var user: [CostumeEntry] { entries.filter { !$0.isBundled } }

    // MARK: - Folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose a folder of SVG costumes. The app reloads a costume when you save it."
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        guard let data = try? chosen.bookmarkData(options: .withSecurityScope) else { folderError = "Could not remember that folder."; return }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        stopWatching()
        folderURL?.stopAccessingSecurityScopedResource()
        _ = chosen.startAccessingSecurityScopedResource()
        folderURL = chosen
        folderError = nil
        rescan()
        watch()
    }

    func forgetFolder() {
        stopWatching()
        folderURL?.stopAccessingSecurityScopedResource()
        folderURL = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        rescan()
    }

    func revealFolder() {
        if let folderURL { NSWorkspace.shared.activateFileViewerSelecting([folderURL]) }
    }

    private func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale),
              resolved.startAccessingSecurityScopedResource() else {
            folderError = "The costumes folder could not be opened again; choose it once more."
            return
        }
        if stale, let fresh = try? resolved.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        folderURL = resolved
        watch()
    }

    // MARK: - Scanning

    func rescan() {
        var found: [CostumeEntry] = []
        if let bundledFolder = Bundle.main.url(forResource: "Costumes", withExtension: nil) ?? Bundle.main.resourceURL {
            let urls = (try? FileManager.default.contentsOfDirectory(at: bundledFolder, includingPropertiesForKeys: nil)) ?? []
            for url in urls.filter({ $0.pathExtension.lowercased() == "svg" }).sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                found.append(CostumeEntry(id: url.path, name: url.deletingPathExtension().lastPathComponent, url: url, isBundled: true))
            }
        }
        if let folderURL {
            let urls = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
            for url in urls.filter({ $0.pathExtension.lowercased() == "svg" }).sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                found.append(CostumeEntry(id: url.path, name: url.deletingPathExtension().lastPathComponent, url: url, isBundled: false))
            }
        }
        entries = found
    }

    func load(_ entry: CostumeEntry) -> Costume? {
        guard let document = try? SVGParser.parse(contentsOf: entry.url) else { return nil }
        return Costume(name: entry.name, document: document)
    }

    func loadError(_ entry: CostumeEntry) -> String? {
        do { _ = try SVGParser.parse(contentsOf: entry.url); return nil } catch { return error.localizedDescription }
    }

    // MARK: - Watching

    private func watch() {
        guard let folderURL else { return }
        watchedDescriptor = open(folderURL.path, O_EVTONLY)
        guard watchedDescriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: watchedDescriptor, eventMask: [.write, .rename, .delete, .attrib, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // Coalesce the burst of events a save produces.
            rescanTask?.cancel()
            rescanTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                rescan()
                changeCount += 1
            }
        }
        source.setCancelHandler { [descriptor = watchedDescriptor] in close(descriptor) }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
        watchedDescriptor = -1
    }
}
