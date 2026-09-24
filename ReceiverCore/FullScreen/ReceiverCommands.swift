//
//  ReceiverCommands.swift
//  TrackOSC (ReceiverCore)
//
//  Menu items every receiver-type app shares: Full Screen (the installation
//  mode: full screen with hidden controls) and Connection.
//

import SwiftUI

struct ReceiverCommands: Commands {
    let model: ReceiverModel

    var body: some Commands {
        CommandMenu("Full Screen") {
            Button(model.fullScreen.isInFullScreenMode ? "Exit Full Screen" : "Enter Full Screen") {
                model.fullScreen.toggleFullScreen()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button(model.fullScreen.isGUIHidden ? "Show Controls" : "Hide Controls") {
                model.fullScreen.toggleGUI()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Divider()

            Toggle("Always on Top (when windowed)", isOn: Binding(
                get: { model.settings.alwaysOnTop },
                set: { model.settings.alwaysOnTop = $0; model.fullScreen.alwaysOnTop = $0 }
            ))
            Toggle("Start in Full Screen", isOn: Binding(
                get: { model.settings.startInFullScreen },
                set: { model.settings.startInFullScreen = $0 }
            ))
        }

        CommandMenu("Connection") {
            Button("Restart Listening") { model.restart() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Toggle("Forward Incoming Messages", isOn: Binding(
                get: { model.settings.forwardEnabled },
                set: { model.settings.forwardEnabled = $0; model.applyForwarding() }
            ))
            Picker("Listen To", selection: Binding(
                get: { model.settings.sourcePolicy },
                set: { model.settings.sourcePolicy = $0; model.applySourcePolicy() }
            )) {
                ForEach(SourcePolicy.allCases) { Text($0.label).tag($0) }
            }
        }
    }
}
