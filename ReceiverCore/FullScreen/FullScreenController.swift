//
//  FullScreenController.swift
//  TrackOSC (ReceiverCore)
//
//  Full screen is the installation mode every receiver-type app shares:
//  the window fills the screen in the stage's background colour with the
//  title bar, toolbar, controls and cursor all gone, leaving only the
//  content. Esc, the menu item or ⌘⇧F bring everything back.
//

import AppKit
import Observation
import SwiftUI

@Observable @MainActor
final class FullScreenController {
    /// Controls, toolbar and status are hidden; only the stage is visible.
    private(set) var isGUIHidden = false
    /// The hosting window is in native full screen.
    private(set) var isNativeFullScreen = false
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
    private var background = NSColor.black

    /// Native full screen with the controls hidden: the installation mode.
    var isInFullScreenMode: Bool { isGUIHidden && isNativeFullScreen }

    /// Called once the SwiftUI content has a window (see WindowAccessor).
    func attach(window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.acceptsMouseMovedEvents = true
        window.backgroundColor = background
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = [
            center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.isNativeFullScreen = true
                    self?.applyChrome()
                }
            },
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.isNativeFullScreen = false
                    self?.applyChrome()
                    self?.applyWindowLevel()
                }
            }
        ]
        isNativeFullScreen = window.styleMask.contains(.fullScreen)
        installMonitors()
        applyWindowLevel()
        applyChrome()
    }

    /// The window's own background, so nothing but the stage colour shows
    /// around or behind the content.
    func setBackground(_ color: NSColor) {
        background = color
        window?.backgroundColor = color
    }

    func enterFullScreen() {
        isGUIHidden = true
        applyChrome()
        if let window, !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        showHintThenHideCursor()
    }

    func exitFullScreen() {
        isGUIHidden = false
        hideTask?.cancel()
        isHintVisible = false
        NSCursor.setHiddenUntilMouseMoves(false)
        applyChrome()
        if let window, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    func toggleFullScreen() {
        if isInFullScreenMode { exitFullScreen() } else { enterFullScreen() }
    }

    /// Hide or show the controls without touching native full screen.
    func toggleGUI() {
        isGUIHidden.toggle()
        applyChrome()
        if isGUIHidden { showHintThenHideCursor() } else {
            hideTask?.cancel()
            isHintVisible = false
        }
    }

    func toggleNativeFullScreen() {
        window?.toggleFullScreen(nil)
    }

    // MARK: - Private

    /// With the controls hidden, the title bar and toolbar disappear and the
    /// content extends under where they were, so the window is one flat
    /// colour edge to edge.
    private func applyChrome() {
        guard let window else { return }
        if isGUIHidden {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbar?.isVisible = false
        } else {
            window.styleMask.remove(.fullSizeContentView)
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.toolbar?.isVisible = true
        }
    }

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
                exitFullScreen()
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

/// Hands the hosting NSWindow to the full-screen controller.
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
