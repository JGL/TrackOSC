//
//  Costume3DLibrary.swift
//  TrackOSC 3D Costumes (macOS)
//
//  What can be worn: the built-in mannequin and blocks, the bundled Blocky
//  rig, and the user's folder (model files = rigged costumes, sub-folders
//  = parts sets), remembered as a bookmark and watched for changes.
//

import AppKit
import Foundation
import Observation

enum Costume3DKind: Hashable {
    case mannequin
    case blocks
    case rigged(URL)
    case parts(URL)
}

struct Costume3DEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: Costume3DKind
    let isBundled: Bool
}

@Observable @MainActor
final class Costume3DLibrary {
    private(set) var entries: [Costume3DEntry] = []
    private(set) var folderURL: URL?
    private(set) var folderError: String?
    private(set) var changeCount = 0

    static let modelExtensions: Set<String> = ["usdz", "usd", "usda", "usdc", "reality"]
    private static let bookmarkKey = "modelsFolderBookmark"
    private var watcher: DispatchSourceFileSystemObject?
    private var rescanTask: Task<Void, Never>?

    init() {
        restoreFolder()
        rescan()
    }

    var bundled: [Costume3DEntry] { entries.filter(\.isBundled) }
    var user: [Costume3DEntry] { entries.filter { !$0.isBundled } }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use Folder"
        panel.message = "Choose a folder of rigged models (.usdz) and parts sub-folders."
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
            folderError = "The models folder could not be opened again; choose it once more."
            return
        }
        if stale, let fresh = try? resolved.bookmarkData(options: .withSecurityScope) { UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey) }
        folderURL = resolved
        watch()
    }

    func rescan() {
        var found: [Costume3DEntry] = [
            Costume3DEntry(id: "mannequin", name: "Mannequin", kind: .mannequin, isBundled: true),
            Costume3DEntry(id: "blocks", name: "Blocks", kind: .blocks, isBundled: true),
        ]
        if let blocky = Bundle.main.url(forResource: "Blocky", withExtension: "usda") {
            found.append(Costume3DEntry(id: blocky.path, name: "Blocky (rigged)", kind: .rigged(blocky), isBundled: true))
        }
        if let folderURL {
            let urls = ((try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for url in urls {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    let inside = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                    if inside.contains(where: { Self.modelExtensions.contains($0.pathExtension.lowercased()) }) {
                        found.append(Costume3DEntry(id: url.path, name: url.lastPathComponent + " (parts)", kind: .parts(url), isBundled: false))
                    }
                } else if Self.modelExtensions.contains(url.pathExtension.lowercased()) {
                    found.append(Costume3DEntry(id: url.path, name: url.deletingPathExtension().lastPathComponent, kind: .rigged(url), isBundled: false))
                }
            }
        }
        entries = found
    }

    private func watch() {
        guard let folderURL else { return }
        let descriptor = open(folderURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .attrib, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            rescanTask?.cancel()
            rescanTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled else { return }
                rescan()
                changeCount += 1
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }
}
