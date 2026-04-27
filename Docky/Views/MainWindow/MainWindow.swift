//
//  MainWindow.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import AppKit
import Combine
import SwiftUI

final class MainWindowContainerView: NSView {
    static let contentPadding: CGFloat = 2

    private let contentView = ClickThroughHostingView(rootView: MainWindowView())
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: Self.contentPadding),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.contentPadding),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.contentPadding),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.contentPadding),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        (window as? MainWindow)?.pointerDidEnterWindow()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        (window as? MainWindow)?.pointerDidExitWindow()
    }
}

final class MainWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override var level: NSWindow.Level { get { .mainMenu } set {} }

    private enum VisibilityState {
        case visible
        case hidden
    }

    private let backgroundBlurRadius = 10
    private let hiddenRevealThickness: CGFloat = 2
    private let baseAutohideAnimationDuration: TimeInterval = 0.12
    private let tileMutationAnimationDuration: TimeInterval = 0.18
    private let dockSettings = DockSettingsService.shared
    private let preferences = DockyPreferences.shared
    private let layout = DockLayoutService.shared
    private let tileStore = TileStore.shared
    private let editMode = DockEditModeService.shared
    private let minimumWidth: CGFloat = 120
    private var cancellables: Set<AnyCancellable> = []
    private var hideWorkItem: DispatchWorkItem?
    private var isPointerInsideWindow = false
    private var activeInteractionCount = 0
    private var visibilityState: VisibilityState

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        visibilityState = DockyPreferences.shared.autohidesWindow ? .hidden : .visible
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        backgroundColor = .clear
        isOpaque = false
        isMovableByWindowBackground = false
        observeFrameInputs()
        observeVisibilityInputs()
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        applyBackgroundBlur()
    }

    private func applyBackgroundBlur() {
        guard windowNumber > 0 else { return }
        _ = CGSSetWindowBackgroundBlurRadius(
            CGSMainConnectionID(),
            windowNumber,
            backgroundBlurRadius
        )
    }

    private func observeFrameInputs() {
        let layoutSignals: [AnyPublisher<Void, Never>] = [
            dockSettings.$orientation.map { _ in () }.eraseToAnyPublisher(),
            dockSettings.$tileSize.map { _ in () }.eraseToAnyPublisher(),
            dockSettings.$largeSize.map { _ in () }.eraseToAnyPublisher(),
            dockSettings.$magnification.map { _ in () }.eraseToAnyPublisher(),
            preferences.$tileVerticalPadding.map { _ in () }.eraseToAnyPublisher(),
            preferences.$tileSpacing.map { _ in () }.eraseToAnyPublisher(),
            preferences.$overflowBehavior.map { _ in () }.eraseToAnyPublisher(),
            preferences.$windowAxisSizing.map { _ in () }.eraseToAnyPublisher(),
            preferences.$windowPosition.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(layoutSignals)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyCurrentFrame(animated: false) }
            .store(in: &cancellables)

        tileStore.$tiles
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyCurrentFrame(animated: true, duration: self?.tileMutationAnimationDuration) }
            .store(in: &cancellables)

        editMode.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self else { return }
                if isActive {
                    self.hideWorkItem?.cancel()
                    self.setVisibility(.visible, animated: true)
                } else {
                    self.scheduleHideIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    private func observeVisibilityInputs() {
        preferences.$autohidesWindow
            .receive(on: DispatchQueue.main)
            .sink { [weak self] autohidesWindow in
                self?.handleAutohideChanged(autohidesWindow)
            }
            .store(in: &cancellables)
    }

    func pointerDidEnterWindow() {
        isPointerInsideWindow = true
        hideWorkItem?.cancel()

        guard preferences.autohidesWindow else { return }
        setVisibility(.visible, animated: true)
    }

    func pointerDidExitWindow() {
        isPointerInsideWindow = false
        scheduleHideIfNeeded()
    }

    func beginInteraction() {
        activeInteractionCount += 1
        hideWorkItem?.cancel()

        guard preferences.autohidesWindow else { return }
        setVisibility(.visible, animated: true)
    }

    func endInteraction() {
        activeInteractionCount = max(0, activeInteractionCount - 1)
        scheduleHideIfNeeded()
    }

    private func handleAutohideChanged(_ autohidesWindow: Bool) {
        hideWorkItem?.cancel()

        if autohidesWindow {
            let nextState: VisibilityState = shouldRemainVisible ? .visible : .hidden
            setVisibility(nextState, animated: true)
            return
        }

        setVisibility(.visible, animated: true)
    }

    private func scheduleHideIfNeeded() {
        hideWorkItem?.cancel()

        guard preferences.autohidesWindow, !shouldRemainVisible else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.shouldRemainVisible else { return }
            self.setVisibility(.hidden, animated: true)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + dockSettings.autohideDelay, execute: workItem)
    }

    private var shouldRemainVisible: Bool {
        isPointerInsideWindow || activeInteractionCount > 0 || editMode.isActive
    }

    private func setVisibility(_ state: VisibilityState, animated: Bool) {
        guard visibilityState != state else {
            applyCurrentFrame(animated: false)
            return
        }

        visibilityState = state
        applyCurrentFrame(animated: animated)
    }

    private func applyCurrentFrame(animated: Bool) {
        applyCurrentFrame(animated: animated, duration: nil)
    }

    private func applyCurrentFrame(animated: Bool, duration: TimeInterval?) {
        let screenBounds = screen?.frame ?? NSScreen.main?.frame ?? .zero
        let contentPadding = MainWindowContainerView.contentPadding
        let position = preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
        let baseIconHeight = dockSettings.magnification ? dockSettings.largeSize : dockSettings.tileSize
        let baseTileHeight = baseIconHeight + preferences.tileVerticalPadding * 2
        let naturalContentSize = TileContainerView.contentSize(
            tiles: tileStore.tiles,
            tileSize: dockSettings.tileSize,
            tileHeight: baseTileHeight,
            tileSpacing: preferences.tileSpacing,
            position: position
        )
        let unreservedAvailableAxisLength = max(
            0,
            axisLength(of: screenBounds.size, position: position) - contentPadding * 2
        )
        let shouldUseFullAxisSizing = preferences.windowAxisSizing == .fullAxis
        let contentAvailableAxisLength = max(
            0,
            unreservedAvailableAxisLength
                - (shouldReserveStatusBarLength(
                    for: naturalContentSize,
                    availableAxisLength: unreservedAvailableAxisLength,
                    position: position
                ) ? reservedStatusBarLength : 0)
        )
        let availableAxisLength = shouldUseFullAxisSizing
            ? unreservedAvailableAxisLength
            : contentAvailableAxisLength
        let compactsWidgetsForOverflow = shouldCompactWidgetsForOverflow(
            contentSize: naturalContentSize,
            availableAxisLength: availableAxisLength,
            position: position
        )
        let baseContentSize = TileContainerView.contentSize(
            tiles: tileStore.tiles,
            tileSize: dockSettings.tileSize,
            tileHeight: baseTileHeight,
            tileSpacing: preferences.tileSpacing,
            position: position,
            compactWidgets: compactsWidgetsForOverflow
        )
        let contentScale = overflowContentScale(
            for: baseContentSize,
            availableAxisLength: availableAxisLength,
            position: position
        )
        layout.setContentScale(contentScale)
        layout.setCompactsWidgetsForOverflow(compactsWidgetsForOverflow)

        let scaledTileSize = dockSettings.tileSize * contentScale
        let scaledIconHeight = baseIconHeight * contentScale
        let scaledTileHeight = scaledIconHeight + (preferences.tileVerticalPadding * contentScale * 2)
        let scaledTileSpacing = preferences.tileSpacing * contentScale
        let displayedContentSize = TileContainerView.contentSize(
            tiles: tileStore.tiles,
            tileSize: scaledTileSize,
            tileHeight: scaledTileHeight,
            tileSpacing: scaledTileSpacing,
            position: position,
            compactWidgets: compactsWidgetsForOverflow,
            edgePadding: TileContainerView.edgePadding * contentScale
        )
        let displayedAxisLength = shouldUseFullAxisSizing
            ? availableAxisLength
            : min(axisLength(of: displayedContentSize, position: position), availableAxisLength)
        let width = displayedWindowWidth(
            for: displayedContentSize,
            displayedAxisLength: displayedAxisLength,
            availableAxisLength: availableAxisLength,
            contentPadding: contentPadding,
            position: position
        )
        let height = displayedWindowHeight(
            for: displayedContentSize,
            displayedAxisLength: displayedAxisLength,
            contentPadding: contentPadding,
            position: position
        )
        let size = CGSize(width: width, height: height)
        let origin = frameOrigin(
            in: screenBounds,
            size: size,
            position: position,
            visibilityState: visibilityState
        )

        let frame = CGRect(origin: origin, size: size)
        applyFrame(frame, animated: animated, duration: duration)
    }

    private func applyFrame(_ frame: CGRect, animated: Bool, duration: TimeInterval?) {
        guard animated else {
            setFrame(frame, display: true, animate: false)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration ?? autohideAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(frame, display: true)
        }
    }

    private var autohideAnimationDuration: TimeInterval {
        max(0.08, min(0.4, baseAutohideAnimationDuration * max(dockSettings.autohideTimeModifier, 0.01)))
    }

    private func overflowContentScale(
        for contentSize: CGSize,
        availableAxisLength: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGFloat {
        guard preferences.overflowBehavior == .rescale, availableAxisLength > 0 else {
            return 1
        }

        let contentAxisLength = axisLength(of: contentSize, position: position)
        guard contentAxisLength > 0 else { return 1 }
        return min(1, availableAxisLength / contentAxisLength)
    }

    private func shouldCompactWidgetsForOverflow(
        contentSize: CGSize,
        availableAxisLength: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> Bool {
        guard preferences.overflowBehavior == .rescale, availableAxisLength > 0 else {
            return false
        }

        return axisLength(of: contentSize, position: position) > availableAxisLength
    }

    private func axisLength(of size: CGSize, position: ResolvedDockWindowPosition) -> CGFloat {
        position.isVertical ? size.height : size.width
    }

    private func shouldReserveStatusBarLength(
        for contentSize: CGSize,
        availableAxisLength: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> Bool {
        axisLength(of: contentSize, position: position) > availableAxisLength
    }

    private var reservedStatusBarLength: CGFloat {
        NSStatusBar.system.thickness * 4
    }

    private func displayedWindowWidth(
        for contentSize: CGSize,
        displayedAxisLength: CGFloat,
        availableAxisLength: CGFloat,
        contentPadding: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGFloat {
        if position.isVertical {
            return contentSize.width + contentPadding * 2
        }

        let visibleAxisLength = availableAxisLength > 0
            ? min(max(minimumWidth, displayedAxisLength), availableAxisLength)
            : max(minimumWidth, displayedAxisLength)
        return visibleAxisLength + contentPadding * 2
    }

    private func displayedWindowHeight(
        for contentSize: CGSize,
        displayedAxisLength: CGFloat,
        contentPadding: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGFloat {
        if position.isVertical {
            return displayedAxisLength + contentPadding * 2
        }

        return contentSize.height + contentPadding * 2
    }

    private func frameOrigin(
        in screenBounds: CGRect,
        size: CGSize,
        position: ResolvedDockWindowPosition,
        visibilityState: VisibilityState
    ) -> CGPoint {
        let hidden = visibilityState == .hidden

        switch position {
        case .top:
            return CGPoint(
                x: screenBounds.minX + (screenBounds.width - size.width) / 2,
                y: hidden ? screenBounds.maxY - hiddenRevealThickness : screenBounds.maxY - size.height
            )
        case .left:
            return CGPoint(
                x: hidden ? screenBounds.minX - size.width + hiddenRevealThickness : screenBounds.minX,
                y: screenBounds.minY + (screenBounds.height - size.height) / 2
            )
        case .right:
            return CGPoint(
                x: hidden ? screenBounds.maxX - hiddenRevealThickness : screenBounds.maxX - size.width,
                y: screenBounds.minY + (screenBounds.height - size.height) / 2
            )
        case .bottom:
            return CGPoint(
                x: screenBounds.minX + (screenBounds.width - size.width) / 2,
                y: hidden ? screenBounds.minY - size.height + hiddenRevealThickness : screenBounds.minY
            )
        }
    }
}
