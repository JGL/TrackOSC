//
//  RecorderStore.swift
//  TrackOSC Recorder (macOS)
//
//  App state on top of the shared ReceiverModel: the recorder tap, the
//  player, and a 30 Hz refresh of their UI-facing status.
//

import Foundation
import Observation
import PoseioscShared

@Observable @MainActor
final class RecorderStore {
    let model = ReceiverModel(app: .recorder)
    let recorder = RecorderController()
    let player = PlayerController()
    let folder = RecordingsFolder()

    /// Polled from the recorder at display rate.
    var recordingStatus = RecorderController.Status()
    var recorderError: String?
    /// Start a recording as soon as the app launches (for installations that
    /// should log every session).
    var recordOnLaunch: Bool {
        didSet { UserDefaults.standard.set(recordOnLaunch, forKey: "recordOnLaunch") }
    }

    private var refreshTask: Task<Void, Never>?

    init() {
        recordOnLaunch = UserDefaults.standard.bool(forKey: "recordOnLaunch")
        model.service.addTap(recorder)
        if recordOnLaunch { startRecording() }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                self?.refresh()
            }
        }
    }

    func toggleRecording() {
        if recorder.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        recorderError = nil
        do {
            let url = try folder.newRecordingURL()
            try recorder.start(url: url)
        } catch {
            recorderError = "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        do {
            if let url = try recorder.stop() {
                folder.lastRecording = url
                player.remember(url)
            }
        } catch {
            recorderError = "Could not finish recording: \(error.localizedDescription)"
        }
    }

    /// True when playback would arrive on this app's own listener.
    var isPlayingIntoSelf: Bool {
        player.destinationPort == model.effectivePort
            && ["127.0.0.1", "localhost", "::1"].contains(player.destinationHost.lowercased())
    }

    private func refresh() {
        recordingStatus = recorder.status()
        player.refreshPosition()
    }
}
