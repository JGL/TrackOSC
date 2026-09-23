//
//  RuleEditor.swift
//  TrackOSC Router (macOS)
//
//  Edits one rule through drafts (flat structs) so the trigger and action
//  enums can be switched without losing what was typed.
//

import SwiftUI

private enum TriggerType: String, CaseIterable, Identifiable {
    case presence, threshold, range, continuous, stringMatch
    var id: String { rawValue }
    var label: String {
        switch self {
        case .presence: "Presence edge"
        case .threshold: "Threshold"
        case .range: "Range"
        case .continuous: "Continuous mapping"
        case .stringMatch: "Text match"
        }
    }
}

private enum ActionType: String, CaseIterable, Identifiable {
    case midiNote, midiCC, shortcut, keyPress, http, log
    var id: String { rawValue }
    var label: String {
        switch self {
        case .midiNote: "MIDI note"
        case .midiCC: "MIDI control change"
        case .shortcut: "Run a Shortcut"
        case .keyPress: "Press a key"
        case .http: "HTTP request"
        case .log: "Log only"
        }
    }
}

private struct Draft: Equatable {
    var name = ""
    var triggerType = TriggerType.presence
    var kind = FrameKind.poses
    var edge = EdgeKind.appear
    var source = ValueSource()
    var threshold = 0.5
    var direction = Direction.rise
    var hysteresis = 0.05
    var low = 0.0, high = 1.0
    var rangeEdge = RangeEdge.enter
    var inMin = 0.0, inMax = 1.0, outMin = 0.0, outMax = 127.0, rateHz = 30.0
    var matchMode = MatchMode.contains
    var pattern = ""
    var cooldown = 10.0

    var actionType = ActionType.log
    var channel = 1, note = 60, velocity = 100, durationMs = 200
    var controller = 1, ccValue = 127
    var shortcutName = "", shortcutInput = "{text}"
    var keyCode = 49
    var modifiers = KeyModifiers()
    var method = "GET", url = "http://127.0.0.1:8080/?value={value}", body = ""

    init(_ rule: Rule) {
        name = rule.name
        switch rule.trigger {
        case .presence(let k, let e): triggerType = .presence; kind = k; edge = e
        case .threshold(let s, let v, let d, let h): triggerType = .threshold; source = s; threshold = v; direction = d; hysteresis = h
        case .range(let s, let l, let h, let e): triggerType = .range; source = s; low = l; high = h; rangeEdge = e
        case .continuous(let s, let a, let b, let c, let d, let hz): triggerType = .continuous; source = s; inMin = a; inMax = b; outMin = c; outMax = d; rateHz = hz
        case .stringMatch(let s, let m, let p, let c): triggerType = .stringMatch; source = s; matchMode = m; pattern = p; cooldown = c
        }
        switch rule.action {
        case .midiNote(let ch, let n, let v, let ms): actionType = .midiNote; channel = ch; note = n; velocity = v; durationMs = ms
        case .midiCC(let ch, let cc, let v): actionType = .midiCC; channel = ch; controller = cc; ccValue = v
        case .shortcut(let n, let i): actionType = .shortcut; shortcutName = n; shortcutInput = i
        case .keyPress(let k, let m): actionType = .keyPress; keyCode = k; modifiers = m
        case .http(let m, let u, let b): actionType = .http; method = m; url = u; body = b
        case .log: actionType = .log
        }
    }

    func rule(id: UUID, isEnabled: Bool) -> Rule {
        let trigger: Trigger = switch triggerType {
        case .presence: .presence(kind: kind, edge: edge)
        case .threshold: .threshold(source: source, value: threshold, direction: direction, hysteresis: hysteresis)
        case .range: .range(source: source, low: low, high: high, edge: rangeEdge)
        case .continuous: .continuous(source: source, inMin: inMin, inMax: inMax, outMin: outMin, outMax: outMax, rateHz: rateHz)
        case .stringMatch: .stringMatch(source: source, mode: matchMode, pattern: pattern, cooldown: cooldown)
        }
        let action: Action = switch actionType {
        case .midiNote: .midiNote(channel: channel, note: note, velocity: velocity, durationMs: durationMs)
        case .midiCC: .midiCC(channel: channel, controller: controller, value: ccValue)
        case .shortcut: .shortcut(name: shortcutName, input: shortcutInput)
        case .keyPress: .keyPress(keyCode: keyCode, modifiers: modifiers)
        case .http: .http(method: method, url: url, body: body)
        case .log: .log
        }
        return Rule(id: id, name: name, isEnabled: isEnabled, trigger: trigger, action: action)
    }
}

struct RuleEditor: View {
    @Bindable var store: RouterStore
    let rule: Rule
    @State private var draft: Draft
    @State private var draftRuleID: UUID

    init(store: RouterStore, rule: Rule) {
        self.store = store
        self.rule = rule
        _draft = State(initialValue: Draft(rule))
        _draftRuleID = State(initialValue: rule.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name", text: $draft.name)
                .textFieldStyle(.roundedBorder)

            Text("When").font(.headline)
            Picker("Trigger", selection: $draft.triggerType) {
                ForEach(TriggerType.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            triggerFields

            Text("Do").font(.headline)
            Picker("Action", selection: $draft.actionType) {
                ForEach(ActionType.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            actionFields

            HStack {
                Button("Test Action") { store.engine.test(draft.rule(id: rule.id, isEnabled: rule.isEnabled)) }
                Spacer()
                if let source = draft.triggerType == .presence ? nil : draft.source as ValueSource? {
                    Text("Live: \(store.engine.read(source, latest: store.model.latest).display)")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: draft) { _, new in
            store.update(new.rule(id: rule.id, isEnabled: rule.isEnabled))
        }
        .onChange(of: rule.id) { _, new in
            if new != draftRuleID {
                draft = Draft(rule)
                draftRuleID = new
            }
        }
    }

    @ViewBuilder
    private var triggerFields: some View {
        switch draft.triggerType {
        case .presence:
            HStack {
                Picker("Kind", selection: $draft.kind) {
                    ForEach(FrameKind.allCases) { Text($0.address).tag($0) }
                }
                Picker("Edge", selection: $draft.edge) {
                    ForEach(EdgeKind.allCases) { Text($0.label).tag($0) }
                }
            }
        case .threshold:
            sourceFields
            HStack {
                Picker("Direction", selection: $draft.direction) {
                    ForEach(Direction.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                number("value", $draft.threshold)
                Text("hysteresis")
                number("hysteresis", $draft.hysteresis)
            }
        case .range:
            sourceFields
            HStack {
                Picker("Edge", selection: $draft.rangeEdge) {
                    ForEach(RangeEdge.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                number("low", $draft.low)
                Text("to")
                number("high", $draft.high)
            }
        case .continuous:
            sourceFields
            HStack {
                Text("Input")
                number("min", $draft.inMin)
                Text("…")
                number("max", $draft.inMax)
                Text("→ output")
                number("min", $draft.outMin)
                Text("…")
                number("max", $draft.outMax)
            }
            HStack {
                Text("Rate")
                number("Hz", $draft.rateHz)
                Text("Hz (MIDI CC and HTTP get the mapped value; {value} in templates)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .stringMatch:
            sourceFields
            HStack {
                Picker("Mode", selection: $draft.matchMode) {
                    ForEach(MatchMode.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                TextField("pattern", text: $draft.pattern).textFieldStyle(.roundedBorder)
                Text("again after")
                number("s", $draft.cooldown)
                Text("s")
            }
        }
    }

    @ViewBuilder
    private var sourceFields: some View {
        HStack {
            Picker("Source", selection: $draft.source.kind) {
                ForEach(SourceKind.allCases.filter { draft.triggerType == .stringMatch ? $0.isText : !$0.isText }) {
                    Text($0.label).tag($0)
                }
            }
            .labelsHidden()
            if draft.source.kind.usesJoint {
                Picker("Joint", selection: $draft.source.joint) {
                    ForEach(Array(draft.source.kind.jointNames.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            if draft.source.kind.usesPerson {
                Stepper("#\(draft.source.person + 1)", value: $draft.source.person, in: 0...31)
                    .help("Which detection, in the order the sender lists them")
            }
        }
        .onChange(of: draft.source.kind) { _, kind in
            if draft.triggerType == .continuous || draft.triggerType == .threshold || draft.triggerType == .range {
                draft.inMin = kind.defaultRange.lowerBound
                draft.inMax = kind.defaultRange.upperBound
            }
        }
    }

    @ViewBuilder
    private var actionFields: some View {
        switch draft.actionType {
        case .midiNote:
            HStack {
                Text("Channel"); integer($draft.channel, 1...16)
                Text("Note"); integer($draft.note, 0...127)
                Text("Velocity"); integer($draft.velocity, 0...127)
                Text("Length"); integer($draft.durationMs, 1...10_000); Text("ms")
            }
        case .midiCC:
            HStack {
                Text("Channel"); integer($draft.channel, 1...16)
                Text("Controller"); integer($draft.controller, 0...127)
                Text("Value"); integer($draft.ccValue, 0...127)
            }
            Text("A continuous trigger replaces the value with its mapped output (use 0…127).")
                .font(.footnote).foregroundStyle(.secondary)
        case .shortcut:
            TextField("Shortcut name (exactly as in the Shortcuts app)", text: $draft.shortcutName).textFieldStyle(.roundedBorder)
            TextField("Input text ({value}, {text}, {rule})", text: $draft.shortcutInput).textFieldStyle(.roundedBorder)
        case .keyPress:
            HStack {
                Picker("Key", selection: $draft.keyCode) {
                    ForEach(KeyCodes.common, id: \.code) { Text($0.name).tag($0.code) }
                }
                .labelsHidden()
                .frame(width: 140)
                modifierToggle("⌘", .command)
                modifierToggle("⇧", .shift)
                modifierToggle("⌥", .option)
                modifierToggle("⌃", .control)
            }
            Text("Goes to the frontmost app. Needs Accessibility access (see Outputs).")
                .font(.footnote).foregroundStyle(.secondary)
        case .http:
            HStack {
                Picker("Method", selection: $draft.method) {
                    Text("GET").tag("GET")
                    Text("POST").tag("POST")
                }
                .labelsHidden()
                .frame(width: 90)
                TextField("URL ({value}, {text}, {rule})", text: $draft.url).textFieldStyle(.roundedBorder)
            }
            if draft.method == "POST" {
                TextField("Body", text: $draft.body, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
            }
        case .log:
            Text("Shows in the activity feed only. Useful for checking a trigger before wiring it up.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func modifierToggle(_ symbol: String, _ flag: KeyModifiers) -> some View {
        Toggle(symbol, isOn: Binding(
            get: { draft.modifiers.contains(flag) },
            set: { on in if on { draft.modifiers.insert(flag) } else { draft.modifiers.remove(flag) } }
        ))
        .toggleStyle(.button)
    }

    private func number(_ label: String, _ value: Binding<Double>) -> some View {
        TextField(label, value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 70)
    }

    private func integer(_ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        TextField("", value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 56)
    }
}
