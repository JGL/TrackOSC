//
//  PoseioscSenderMacApp.swift
//  Poseiosc Sender (macOS)
//
//  Mac camera → Apple Vision detections → OSC, in the VisionOSC wire format.
//

import SwiftUI

@main
struct PoseioscSenderMacApp: App {
    @State private var model = MacAppModel()

    var body: some Scene {
        WindowGroup {
            MacContentView(model: model)
                .frame(minWidth: 760, minHeight: 420)
        }
    }
}
