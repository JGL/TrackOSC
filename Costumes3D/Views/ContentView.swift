//
//  ContentView.swift
//  TrackOSC 3D Costumes (macOS)
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: Costumes3DStore
    @State private var tab: String = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--panel"), i + 1 < args.count { return args[i + 1].lowercased() }
        return "costumes"
    }()

    var body: some View {
        ReceiverWindow(model: store.model) {
            Stage3DView(store: store)
        } controls: {
            TabView(selection: $tab) {
                Tab("Costumes", systemImage: "tshirt", value: "costumes") {
                    Library3DPanel(store: store)
                }
                Tab("Rig", systemImage: "figure.stand", value: "rig") {
                    RigPanel(store: store)
                }
                Tab("Display", systemImage: "rectangle.on.rectangle", value: "display") {
                    Display3DPanel(store: store)
                }
                Tab("Status", systemImage: "waveform.path.ecg", value: "status") {
                    ReceiverStatusView(model: store.model)
                }
            }
        } toolbar: {
            ToolbarItemGroup(placement: .automatic) {
                Button { store.nextCostume(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous costume ([)")
                Text(store.selectedEntry?.name ?? "\u{2013}").font(.callout).frame(minWidth: 100)
                Button { store.nextCostume(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next costume (])")
                Button { store.resetView() } label: { Label("Reset View", systemImage: "arrow.counterclockwise") }
                    .help("Reset the orbit camera (0)")
            }
        }
    }
}
