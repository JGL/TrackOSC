//
//  ContentView.swift
//  TrackOSC Receiver (macOS)
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: ReceiverStore

    var body: some View {
        ReceiverWindow(model: store.model) {
            switch store.visualizerMode {
            case .twoD:
                VisualizerView(model: store.model)
            case .threeD:
                Visualizer3DView(store: store)
            }
        } controls: {
            ReceiverStatusView(model: store.model)
        } toolbar: {
            ToolbarItemGroup(placement: .automatic) {
                Picker("View", selection: $store.visualizerMode) {
                    ForEach(VisualizerMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("2D: every message in wire pixels. 3D: /poses3d/arr in metres.")

                if store.visualizerMode == .threeD {
                    Button("Reset view") { store.resetViewToken += 1 }
                }
            }
        }
    }
}
