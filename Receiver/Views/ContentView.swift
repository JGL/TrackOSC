//
//  ContentView.swift
//  TrackOSC Receiver (macOS)
//

import SwiftUI

struct ContentView: View {
    @Bindable var model: ReceiverModel
    @State private var portText = ""

    var body: some View {
        HSplitView {
            Group {
                switch model.visualizerMode {
                case .twoD:
                    VisualizerView(model: model)
                case .threeD:
                    Visualizer3DView(model: model)
                }
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            SidebarView(model: model)
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: $model.visualizerMode) {
                    ForEach(VisualizerMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("2D: every message in wire pixels. 3D: /poses3d/arr in metres.")

                if model.visualizerMode == .threeD {
                    Button("Reset view") { model.resetViewToken += 1 }
                }

                Circle()
                    .fill(model.isListening ? .green : .red)
                    .frame(width: 10, height: 10)
                Text(model.isListening ? "Listening on UDP \(String(model.listenPort))" : "Not listening")
                    .font(.callout)

                TextField("Port", text: $portText)
                    .frame(width: 64)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyPort)
                Button("Restart", action: applyPort)

                if let name = model.advertisedName {
                    Label(name, systemImage: "dot.radiowaves.left.and.right")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { portText = String(model.listenPort) }
        .safeAreaInset(edge: .bottom) {
            if let error = model.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.8))
            }
        }
    }

    private func applyPort() {
        guard let port = UInt16(portText), port > 0 else {
            portText = String(model.listenPort)
            return
        }
        model.restart(port: port)
    }
}
