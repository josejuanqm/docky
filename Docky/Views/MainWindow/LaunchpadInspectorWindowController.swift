//
//  LaunchpadInspectorWindowController.swift
//  Docky
//
//  Floating utility panel that hosts `LaunchpadSettingsView` over the
//  Launchpad overlay so the user can tune grid columns, icon size, and
//  transparency without dismissing the launchpad first. Edits flow
//  through `DockyPreferences` and the launchpad re-renders against
//  them in real time.
//

import AppKit
import Combine
import SwiftUI

final class LaunchpadInspectorWindowController: NSWindowController, NSWindowDelegate {
    private var cancellables: Set<AnyCancellable> = []
    private let hostingController: NSHostingController<LaunchpadSettingsView>
    /// Whether the user has positioned the panel manually this session.
    /// On first present, we anchor the panel near the top-right of the
    /// active screen; once moved, we leave it alone so re-summons land
    /// where the user last parked it.
    private var hasPositioned = false

    init() {
        let hosting = NSHostingController(
            rootView: LaunchpadSettingsView(hidesAvailabilitySection: true)
        )
        self.hostingController = hosting
        let panel = LaunchpadInspectorPanel()
        panel.contentViewController = hosting
        super.init(window: panel)
        panel.delegate = self
        observe()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func observe() {
        LaunchpadInspectorService.shared.$isPresented
            .receive(on: DispatchQueue.main)
            .sink { [weak self] presented in
                self?.applyPresented(presented)
            }
            .store(in: &cancellables)

        // Auto-dismiss when the launchpad itself closes, so the panel
        // doesn't linger on the desktop after the overlay is gone.
        LaunchpadOverlayService.shared.$isPresented
            .receive(on: DispatchQueue.main)
            .sink { presented in
                if !presented { LaunchpadInspectorService.shared.dismiss() }
            }
            .store(in: &cancellables)
    }

    private func applyPresented(_ presented: Bool) {
        guard let window else { return }
        if presented {
            positionWindowIfNeeded()
            window.orderFrontRegardless()
            window.makeKey()
        } else {
            window.orderOut(nil)
        }
    }

    private func positionWindowIfNeeded() {
        guard let window, !hasPositioned else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let preferred = CGSize(width: 440, height: 580)
        let origin = CGPoint(
            x: visibleFrame.maxX - preferred.width - 24,
            y: visibleFrame.maxY - preferred.height - 24
        )
        window.setFrame(CGRect(origin: origin, size: preferred), display: false)
        hasPositioned = true
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Route the title-bar close through the service so other
        // observers (e.g. the launchpad's chrome button highlight)
        // stay in sync with the panel's actual visibility.
        LaunchpadInspectorService.shared.dismiss()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        // User dragged the panel; honor that position on the next
        // present instead of snapping back to the corner anchor.
        hasPositioned = true
    }
}

private final class LaunchpadInspectorPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 580),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        title = "Launchpad"
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        // Sit one notch above the launchpad overlay (mainMenu + 1) so
        // the panel never gets sandwiched behind the grid it's editing.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        minSize = NSSize(width: 380, height: 420)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
