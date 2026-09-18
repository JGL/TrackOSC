//
//  AppModel.swift
//  Poseiosc Sender (iOS)
//
//  Wires camera → conveyor → Vision processor → OSC sender, and holds the
//  overlay state for SwiftUI.
//

import Foundation
import AVFoundation
import Observation
import UIKit

@Observable @MainActor
final class AppModel {
    let settings = SettingsStore()
    let camera = CameraManager()
    let oscSender = OSCSenderService()
    let bonjour = BonjourBrowser()

    private(set) var overlay = OverlaySnapshot()
    private(set) var processedFPS: Double = 0
    /// Rate of the 3D body lane, which runs independently of the main pipeline.
    private(set) var pose3DFPS: Double = 0

    var sentCount: UInt64 { oscSender.counters.sent }

    private var processor: VisionProcessor?
    private var recentProcessTimes: [Date] = []
    private var recentPose3DTimes: [Date] = []
    private var lastPose3DSequence: UInt64 = 0

    func start() {
        oscSender.setDestination(host: settings.host, port: settings.port)
        oscSender.start()
        bonjour.start()

        let processor = VisionProcessor(sender: oscSender) { [weak self] snapshot in
            Task { @MainActor in
                self?.acceptSnapshot(snapshot)
            }
        }
        self.processor = processor

        let conveyor = FrameConveyor { frame in
            await processor.process(frame)
        }
        camera.attach(conveyor: conveyor)
        camera.start(position: settings.useFrontCamera ? .front : .back)

        applySettings()
    }

    func stop() {
        camera.stop()
    }

    /// Push current settings into the pipeline. Call after any settings change.
    func applySettings() {
        oscSender.setDestination(host: settings.host, port: settings.port)
        camera.setOrientationLock(settings.cameraOrientation)
        applyInterfaceOrientation()
        let config = settings.detectorConfig
        Task { [processor] in
            await processor?.setConfig(config)
        }
    }

    /// Reads the current interface orientation and feeds it to the camera as
    /// the Auto-mode angle. Triggered from the view layer on size changes —
    /// the interface orientation is the single source of truth for Auto, so
    /// what's on screen and what's sent can never disagree.
    func refreshInterfaceOrientation() {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.effectiveGeometry.interfaceOrientation ?? .portrait

        // Device-verified mapping (2026-07-29): interface .landscapeRight is
        // the device rotated ANTICLOCKWISE (Apple's device/interface landscape
        // names cross over) and needs 180°; .landscapeLeft needs 0°.
        let angle: Int32 = switch orientation {
        case .portrait: 90
        case .portraitUpsideDown: 270
        case .landscapeRight: 180
        case .landscapeLeft: 0
        default: 90
        }
        camera.setAutoInterfaceAngle(angle)
    }

    /// Locks the UI orientation to match a locked camera orientation, so the
    /// interface can never rotate out from under the capture configuration.
    private func applyInterfaceOrientation() {
        let mask: UIInterfaceOrientationMask = switch settings.cameraOrientation {
        case .auto: .allButUpsideDown
        case .portrait: .portrait
        case .landscapeLeft, .landscapeRight: .landscape
        }
        SenderAppDelegate.orientationMask.value = mask

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            windowScene.keyWindow?.rootViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    func switchCamera() {
        settings.useFrontCamera.toggle()
        camera.switchCamera()
    }

    private func acceptSnapshot(_ snapshot: OverlaySnapshot) {
        overlay = snapshot
        let now = Date.now
        recentProcessTimes.append(now)
        recentProcessTimes.removeAll { now.timeIntervalSince($0) > 1.0 }
        processedFPS = Double(recentProcessTimes.count)

        if snapshot.poses3DSequence != lastPose3DSequence {
            lastPose3DSequence = snapshot.poses3DSequence
            recentPose3DTimes.append(now)
        }
        recentPose3DTimes.removeAll { now.timeIntervalSince($0) > 1.0 }
        pose3DFPS = Double(recentPose3DTimes.count)
    }
}
