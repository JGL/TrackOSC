//
//  LibraryPanel.swift
//  TrackOSC Costumes (macOS)
//

import SwiftUI

struct LibraryPanel: View {
    @Bindable var store: CostumesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(get: { store.selectedID }, set: { id in
                if let id, let entry = store.library.entries.first(where: { $0.id == id }) { store.select(entry) }
            })) {
                Section("Bundled") {
                    ForEach(store.library.bundled) { entry in row(entry) }
                }
                Section(store.library.folderURL?.lastPathComponent ?? "Your folder") {
                    if store.library.folderURL == nil {
                        Text("Choose a folder of SVG costumes below. They reload when you save them.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if store.library.user.isEmpty {
                        Text("No .svg files in this folder yet.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(store.library.user) { entry in row(entry) }
                }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Button("Choose Folder\u{2026}") { store.library.chooseFolder() }
                if store.library.folderURL != nil {
                    Button("Reveal") { store.library.revealFolder() }
                    Button("Forget") { store.library.forgetFolder() }
                }
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.url(forResource: "README", withExtension: "md", subdirectory: "Costumes") ?? Bundle.main.url(forResource: "README", withExtension: "md") ?? Bundle.main.bundleURL])
                } label: { Label("How to make one", systemImage: "book") }
                .help("Opens the costume-making guide and the bundled costumes in Finder")
            }
            .controlSize(.small)
            .padding(8)
            if let error = store.library.folderError {
                Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 8).padding(.bottom, 6)
            }
            VStack(alignment: .leading, spacing: 6) {
                Picker("People", selection: $store.assignment) {
                    ForEach(CostumeAssignment.allCases) { Text($0.label).tag($0) }
                }
                Text("Keys: [ and ] change costume, 1\u{2013}9 pick one, M mirror, K skeleton, V record, R reload.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .padding(8)
        }
    }

    private func row(_ entry: CostumeEntry) -> some View {
        HStack {
            Image(systemName: "tshirt")
                .foregroundStyle(entry.id == store.selectedID ? Color.accentColor : .secondary)
            Text(entry.name)
            Spacer()
            if let index = store.library.entries.firstIndex(of: entry), index < 9 {
                Text("\(index + 1)").font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
        }
        .tag(entry.id)
    }
}
