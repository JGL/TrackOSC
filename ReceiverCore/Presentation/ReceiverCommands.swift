//
//  ReceiverCommands.swift
//  TrackOSC (ReceiverCore)
//
//  Menu items every receiver-type app shares: Presentation (full screen with
//  hidden controls) and Connection.
//

import SwiftUI

struct ReceiverCommands: Commands {
    let model: ReceiverModel

    var body: some Commands {
        CommandMenu("Presentation") {
            Button(model.presentation.isPresenting ? "Exit Presentation" : "Enter Presentation") {
                model.presentation.togglePresentation()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button(model.presentation.isGUIHidden ? "Show Controls" : "Hide Controls") {
                model.presentation.toggleGUI()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Divider()

            Toggle("Always on Top (when windowed)", isOn: Binding(
                get: { model.settings.alwaysOnTop },
                set: { model.settings.alwaysOnTop = $0; model.presentation.alwaysOnTop = $0 }
            ))
            Toggle("Start in Presentation", isOn: Binding(
                get: { model.settings.startInPresentation },
                set: { model.settings.startInPresentation = $0 }
            ))
        }

        CommandMenu("Connection") {
            Button("Restart Listening") { model.restart() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Toggle("Forward Incoming Messages", isOn: Binding(
                get: { model.settings.forwardEnabled },
                set: { model.settings.forwardEnabled = $0; model.applyForwarding() }
            ))
        }
    }
}
