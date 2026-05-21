//
//  ProfileSwitcherWindowController.swift
//  Docky
//
//  Hosts the profile-switcher ball in its own borderless companion window
//  that floats just outside the dock chrome, on the chrome's interior
//  side. Modeled on `DockEditorHintWindowController` — same pattern of
//  observing the main window's frame and dock-position preference, then
//  re-positioning the panel each time either changes. Companion-window
//  approach (rather than growing the main dock window) keeps the dock's
//  size math untouched and lets the ball overflow the chrome cleanly.
//

import AppKit
import Combine
import SwiftUI

final class ProfileSwitcherWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var alphaObservation: NSKeyValueObservation?
    private let preferences = DockyPreferences.shared
    private let dockSettings = DockSettingsService.shared
    private let hostingController: NSHostingController<ProfileSwitcherButtonView>
    private let chromeGap: CGFloat = 8
    /// Whether we've called `mainWindow.beginInteraction()` without a
    /// matching `endInteraction()` yet. Keeps the count balanced when
    /// the switcher's hover state flips repeatedly.
    private var isHoldingMainInteraction = false

    init(mainWindow: MainWindow) {
        self.mainWindow = mainWindow
        let position = preferences.windowPosition
            .resolved(systemOrientation: dockSettings.orientation)
        let rootView = ProfileSwitcherButtonView(
            dockPosition: position,
            availableLength: Self.availableLength(for: position, mainFrame: mainWindow.frame),
            onActiveChange: { _ in }
        )
        let hosting = NSHostingController(rootView: rootView)
        self.hostingController = hosting

        let companion = ProfileSwitcherCompanionWindow()
        companion.contentViewController = hosting
        super.init(window: companion)

        // Wire the callback now that `self` exists.
        hosting.rootView = ProfileSwitcherButtonView(
            dockPosition: position,
            availableLength: Self.availableLength(for: position, mainFrame: mainWindow.frame),
            onActiveChange: { [weak self] active in
                self?.applySwitcherActive(active)
            }
        )

        prepareWindow()
        observeMainWindow()
        observePositionChanges()
        observeSpaceBehavior()
    }

    deinit {
        if isHoldingMainInteraction {
            mainWindow?.endInteraction()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func prepareWindow() {
        guard let window, let mainWindow else { return }
        window.collectionBehavior = preferences.windowSpaceBehavior
            .collectionBehavior(includesFullScreenAuxiliary: true)
        window.alphaValue = mainWindow.alphaValue
        window.ignoresMouseEvents = false
        updateRootViewAndFrame()
        window.orderFront(nil)

        alphaObservation = mainWindow.observe(\.alphaValue, options: [.initial, .new]) { [weak self] _, change in
            guard let self, let newAlpha = change.newValue else { return }
            self.window?.alphaValue = newAlpha
            // When the dock is hidden (alpha ≈ 0) the switcher shouldn't
            // be reachable either, so stop hit-testing it.
            self.window?.ignoresMouseEvents = newAlpha < 0.05
        }
    }

    private func applySwitcherActive(_ active: Bool) {
        guard let mainWindow else { return }
        if active, !isHoldingMainInteraction {
            mainWindow.beginInteraction()
            isHoldingMainInteraction = true
        } else if !active, isHoldingMainInteraction {
            mainWindow.endInteraction()
            isHoldingMainInteraction = false
        }
    }

    private func observeMainWindow() {
        let center = NotificationCenter.default
        center.publisher(for: NSWindow.didMoveNotification, object: mainWindow)
            .merge(with: center.publisher(for: NSWindow.didResizeNotification, object: mainWindow))
            .merge(with: center.publisher(for: NSWindow.didChangeScreenNotification, object: mainWindow))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateRootViewAndFrame()
            }
            .store(in: &cancellables)
    }

    private func observePositionChanges() {
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.windowPosition
            self?.updateRootViewAndFrame()
        }
        .store(in: &cancellables)
    }

    private func observeSpaceBehavior() {
        observeChanges { [weak self] in
            let behavior = DockyPreferences.shared.windowSpaceBehavior
            self?.window?.collectionBehavior = behavior.collectionBehavior(includesFullScreenAuxiliary: true)
        }
        .store(in: &cancellables)
    }

    private func updateRootViewAndFrame() {
        guard let window, let mainWindow else { return }
        let position = preferences.windowPosition
            .resolved(systemOrientation: dockSettings.orientation)
        let mainFrame = mainWindow.frame
        hostingController.rootView = ProfileSwitcherButtonView(
            dockPosition: position,
            availableLength: Self.availableLength(for: position, mainFrame: mainFrame),
            onActiveChange: { [weak self] active in
                self?.applySwitcherActive(active)
            }
        )
        hostingController.view.layoutSubtreeIfNeeded()
        let size = hostingController.view.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        let origin: CGPoint
        switch position {
        case .bottom:
            origin = CGPoint(
                x: mainFrame.midX - size.width / 2,
                y: mainFrame.maxY + chromeGap
            )
        case .top:
            origin = CGPoint(
                x: mainFrame.midX - size.width / 2,
                y: mainFrame.minY - size.height - chromeGap
            )
        case .left:
            origin = CGPoint(
                x: mainFrame.maxX + chromeGap,
                y: mainFrame.midY - size.height / 2
            )
        case .right:
            origin = CGPoint(
                x: mainFrame.minX - size.width - chromeGap,
                y: mainFrame.midY - size.height / 2
            )
        }

        window.setFrame(CGRect(origin: origin, size: size).integral, display: true)
    }

    private static func availableLength(
        for position: ResolvedDockWindowPosition,
        mainFrame: CGRect
    ) -> CGFloat {
        position.isVertical ? mainFrame.height : mainFrame.width
    }
}

private final class ProfileSwitcherCompanionWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .mainMenu
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
