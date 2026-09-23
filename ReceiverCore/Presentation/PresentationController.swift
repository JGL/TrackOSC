//
//  PresentationController.swift
//  TrackOSC (ReceiverCore)
//
//  "Presentation" is the installation mode every receiver-type app shares:
//  the window goes full screen, the controls and toolbar disappear, and the
//  cursor hides after a moment of stillness, leaving only the stage. Esc, the
//  menu item or the shortcut bring everything back.
//

import AppKit
import Observation
import SwiftUI

@Observable @MainActor
final class PresentationController {
    /// Controls, toolbar and status are hidden; only the stage is visible.
    private(set) var isGUIHidden = false
    /// The hosting window is in native full screen.
    private(set) var isFullScreen = false
    /// A small "press Esc" hint is showing over the stage.
    private(set) var isHintVisible = false

    var cursorHideDelay: Double = 2
    var alwaysOnTop = false {
        didSet { applyWindowLevel() }
    }

    private weak var window: NSWindow?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var hideTask: Task<Void, Never>?

    var isPresenting: Bool { isGUIHidden && isFullScreen }

    /// Called once the SwiftUI content has a window (see WindowAccessor).
    func attach(window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.acceptsMouseMovedEvents = true
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = [
            center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.isFullScreen = true }
            },
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.isFullScreen = false
                    self?.applyWindowLevel()
                }
            }
        ]
        isFullScreen = window.styleMask.contains(.fullScreen)
        installMonitors()
        applyWindowLevel()
    }

    func enterPresentation() {
        isGUIHidden = true
        if let window, !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        showHintThenHideCursor()
    }

    func exitPresentation() {
        isGUIHidden = false
        hideTask?.cancel()
        isHintVisible = false
        NSCursor.setHiddenUntilMouseMoves(false)
        if let window, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    func togglePresentation() {
        if isPresenting { exitPresentation() } else { enterPresentation() }
    }

    /// Hide or show the controls without touching full screen.
    func toggleGUI() {
        isGUIHidden.toggle()
        if isGUIHidden { showHintThenHideCursor() } else {
            hideTask?.cancel()
            isHintVisible = false
        }
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    // MARK: - Private

    private func showHintThenHideCursor() {
        isHintVisible = true
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(cursorHideDelay))
            guard !Task.isCancelled, isGUIHidden else { return }
            isHintVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func installMonitors() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.keyCode == 53, isGUIHidden else { return event }   // Esc
                exitPresentation()
                return nil
            }
        }
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
                guard let self, isGUIHidden else { return event }
                showHintThenHideCursor()
                return event
            }
        }
    }

    private func applyWindowLevel() {
        guard let window else { return }
        // A floating level and native full screen do not mix; only float when windowed.
        window.level = (alwaysOnTop && !window.styleMask.contains(.fullScreen)) ? .floating : .normal
    }
}

/// Hands the hosting NSWindow to the presentation controller.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window { onWindow(window) }
    }
}
