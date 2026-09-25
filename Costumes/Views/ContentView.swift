//
//  ContentView.swift
//  TrackOSC Costumes (macOS)
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: CostumesStore
    @State private var tab: String = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--panel"), i + 1 < args.count { return args[i + 1].lowercased() }
        return "costumes"
    }()

    var body: some View {
        ReceiverWindow(model: store.model) {
            CostumeStage(store: store)
        } controls: {
            TabView(selection: $tab) {
                Tab("Costumes", systemImage: "tshirt", value: "costumes") {
                    LibraryPanel(store: store)
                }
                Tab("Layers", systemImage: "square.3.layers.3d", value: "layers") {
                    InspectorPanel(store: store)
                }
                Tab("Display", systemImage: "rectangle.on.rectangle", value: "display") {
                    DisplayPanel(store: store)
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
                Toggle(isOn: $store.mirror) { Label("Mirror", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    .help("Mirror the stage (M)")
                Button {
                    store.toggleRecording()
                } label: {
                    Label(store.recorder.isRecording ? "Stop" : "Record", systemImage: store.recorder.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(store.recorder.isRecording ? Color.red : Color.primary)
                }
                .help(store.recorder.isRecording ? "Stop recording (V)" : "Record the stage to an .mp4 in Downloads (V)")
            }
        }
    }
}
