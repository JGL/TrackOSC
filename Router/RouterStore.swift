//
//  RouterStore.swift
//  TrackOSC Router (macOS)
//

import Foundation
import Observation
import PoseioscShared

@Observable @MainActor
final class RouterStore {
    let model = ReceiverModel(app: .router)
    let engine = RouterEngine()
    var selectedRuleID: UUID?

    private var tickTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    init() {
        engine.rules = RuleStore.load() ?? RuleStore.starterRules
        engine.dryRun = UserDefaults.standard.bool(forKey: "dryRun")
        selectedRuleID = engine.rules.first?.id
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self else { return }
                engine.tick(latest: model.latest)
            }
        }
    }

    var selectedRule: Rule? {
        engine.rules.first { $0.id == selectedRuleID }
    }

    func update(_ rule: Rule) {
        guard let index = engine.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        if engine.rules[index] != rule {
            engine.rules[index] = rule
            scheduleSave()
        }
    }

    func add(_ rule: Rule) {
        var copy = rule
        copy.id = UUID()
        engine.rules.append(copy)
        selectedRuleID = copy.id
        scheduleSave()
    }

    func addBlankRule() {
        add(Rule(name: "New rule", trigger: .presence(kind: .poses, edge: .appear), action: .log))
    }

    func duplicateSelected() {
        guard var rule = selectedRule else { return }
        rule.name += " copy"
        add(rule)
    }

    func deleteSelected() {
        guard let id = selectedRuleID, let index = engine.rules.firstIndex(where: { $0.id == id }) else { return }
        engine.rules.remove(at: index)
        selectedRuleID = engine.rules[safe: min(index, engine.rules.count - 1)]?.id
        scheduleSave()
    }

    func move(from source: IndexSet, to destination: Int) {
        engine.rules.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    func importRules() {
        guard let imported = RuleStore.importPanel() else { return }
        for rule in imported { add(rule) }
    }

    func setDryRun(_ on: Bool) {
        engine.dryRun = on
        UserDefaults.standard.set(on, forKey: "dryRun")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            RuleStore.save(engine.rules)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
