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
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var globalDragRevealMonitor: Any?
    private var localDragRevealMonitor: Any?
    private var isPointerInsideWindow = false
    private var activeInteractionCount = 0
    private var visibilityState: VisibilityState
    private var hasCompletedSetup = false
    private var hasResolvedInitialFrame = false
    private var lastPointerScreenFrame: CGRect?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        visibilityState = DockyPreferences.shared.autohidesWindow ? .hidden : .visible
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        performSetupIfNeeded()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        applyCurrentFrame(animated: false)
    }

    private func performSetupIfNeeded() {
        guard !hasCompletedSetup else { return }
        hasCompletedSetup = true

        backgroundColor = .clear
        isOpaque = false
        isMovableByWindowBackground = false
        alphaValue = 0
        applyCollectionBehavior()
        observeFrameInputs()
        observeScreenAndSpaceInputs()
        observeWindowPlacementInputs()
        observeVisibilityInputs()
        updatePointerScreenMonitoring()
        updateDragRevealMonitoring()
    }

    deinit {
        if let globalPointerMonitor {
            NSEvent.removeMonitor(globalPointerMonitor)
        }
        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
        }
        if let globalDragRevealMonitor {
            NSEvent.removeMonitor(globalDragRevealMonitor)
        }
        if let localDragRevealMonitor {
            NSEvent.removeMonitor(localDragRevealMonitor)
        }
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
            preferences.$windowDisplayTarget.map { _ in () }.eraseToAnyPublisher(),
            editMode.$paletteDrag.map { _ in () }.eraseToAnyPublisher(),
            editMode.$paletteDropDestination.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(layoutSignals)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyCurrentFrame(animated: true, duration: self?.tileMutationAnimationDuration) }
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

    private func observeScreenAndSpaceInputs() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSWorkspace.activeSpaceDidChangeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentFrame(animated: false)
            }
            .store(in: &cancellables)
    }

    private func observeWindowPlacementInputs() {
        preferences.$windowSpaceBehavior
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCollectionBehavior()
            }
            .store(in: &cancellables)

        preferences.$windowDisplayTarget
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.lastPointerScreenFrame = nil
                self?.updatePointerScreenMonitoring()
            }
            .store(in: &cancellables)

        PermissionsService.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.lastPointerScreenFrame = nil
                self?.updatePointerScreenMonitoring()
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

    private func applyCollectionBehavior() {
        collectionBehavior = preferences.windowSpaceBehavior.collectionBehavior(includesFullScreenAuxiliary: true)
    }

    private func updatePointerScreenMonitoring() {
        if let globalPointerMonitor {
            NSEvent.removeMonitor(globalPointerMonitor)
            self.globalPointerMonitor = nil
        }
        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
            self.localPointerMonitor = nil
        }

        guard preferences.windowDisplayTarget == .displayContainingPointer else { return }

        let pointerEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        if PermissionsService.shared.accessibility == .granted {
            globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents) { [weak self] _ in
                self?.handlePointerScreenChangeIfNeeded()
            }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: pointerEvents) { [weak self] event in
            self?.handlePointerScreenChangeIfNeeded()
            return event
        }
    }

    private func updateDragRevealMonitoring() {
        if let globalDragRevealMonitor {
            NSEvent.removeMonitor(globalDragRevealMonitor)
            self.globalDragRevealMonitor = nil
        }
        if let localDragRevealMonitor {
            NSEvent.removeMonitor(localDragRevealMonitor)
            self.localDragRevealMonitor = nil
        }

        let dragEvents: NSEvent.EventTypeMask = [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        globalDragRevealMonitor = NSEvent.addGlobalMonitorForEvents(matching: dragEvents) { [weak self] _ in
            self?.syncPointerPresenceForDragSession()
        }
        localDragRevealMonitor = NSEvent.addLocalMonitorForEvents(matching: dragEvents) { [weak self] event in
            self?.syncPointerPresenceForDragSession()
            return event
        }
    }

    private func handlePointerScreenChangeIfNeeded() {
        guard preferences.windowDisplayTarget == .displayContainingPointer else { return }
        let nextScreenFrame = targetScreen()?.frame
        guard nextScreenFrame != lastPointerScreenFrame else { return }
        lastPointerScreenFrame = nextScreenFrame
        DispatchQueue.main.async { [weak self] in
            self?.applyCurrentFrame(animated: false)
        }
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

    private func syncPointerPresenceForDragSession() {
        let containsPointer = frame.contains(NSEvent.mouseLocation)
        if containsPointer, !isPointerInsideWindow {
            pointerDidEnterWindow()
        } else if !containsPointer, isPointerInsideWindow {
            pointerDidExitWindow()
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.autohideWindowDelay, execute: workItem)
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
        let screenBounds = targetScreen()?.frame ?? screen?.frame ?? NSScreen.main?.frame ?? .zero
        lastPointerScreenFrame = screenBounds
        let contentPadding = MainWindowContainerView.contentPadding
        let position = preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
        let baseTileSize = dockSettings.displayTileSize
        let baseTileHeight = baseTileSize + preferences.tileVerticalPadding * 2
        let sizingTiles = TileContainerView.previewedTiles(
            from: tileStore.tiles,
            paletteDrag: editMode.paletteDrag,
            paletteDropDestination: editMode.paletteDropDestination
        )
        let naturalContentSize = TileContainerView.contentSize(
            tiles: sizingTiles,
            tileSize: baseTileSize,
            tileHeight: baseTileHeight,
            tileSpacing: preferences.tileSpacing,
            position: position
        )
        let unreservedAvailableAxisLength = max(
            0,
            axisLength(of: screenBounds.size, position: position) - contentPadding * 2
        )
        let contentAvailableAxisLength = max(
            0,
            unreservedAvailableAxisLength
                - (shouldReserveStatusBarLength(
                    for: naturalContentSize,
                    availableAxisLength: unreservedAvailableAxisLength,
                    position: position
                ) ? reservedStatusBarLength : 0)
        )
        let availableAxisLength = preferences.windowAxisSizing == .fullAxis
            ? unreservedAvailableAxisLength
            : contentAvailableAxisLength
        let compactsWidgetsForOverflow = shouldCompactWidgetsForOverflow(
            contentSize: naturalContentSize,
            availableAxisLength: availableAxisLength,
            position: position
        )
        let baseContentSize = TileContainerView.contentSize(
            tiles: sizingTiles,
            tileSize: baseTileSize,
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

        let scaledTileSize = baseTileSize * contentScale
        let scaledTileHeight = scaledTileSize + (preferences.tileVerticalPadding * contentScale * 2)
        let scaledTileSpacing = preferences.tileSpacing * contentScale
        let displayedContentSize = TileContainerView.contentSize(
            tiles: sizingTiles,
            tileSize: scaledTileSize,
            tileHeight: scaledTileHeight,
            tileSpacing: scaledTileSpacing,
            position: position,
            compactWidgets: compactsWidgetsForOverflow,
            edgePadding: TileContainerView.edgePadding * contentScale
        )
        let displayedChromeAxisLength = min(axisLength(of: displayedContentSize, position: position), availableAxisLength)
        layout.setChromeSize(displayedChromeSize(
            for: displayedContentSize,
            displayedAxisLength: displayedChromeAxisLength,
            position: position
        ))
        // Keep the chrome stretched across the current dock axis even when the
        // tile layout itself remains content-sized.
        let displayedAxisLength = availableAxisLength
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
        let shouldAnimate = animated && hasResolvedInitialFrame

        guard shouldAnimate else {
            setFrame(frame, display: true, animate: false)
            revealAfterInitialFrameIfNeeded()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration ?? autohideAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(frame, display: true)
        }
    }

    private func revealAfterInitialFrameIfNeeded() {
        guard !hasResolvedInitialFrame else { return }
        hasResolvedInitialFrame = true
        alphaValue = 1
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

    private func displayedChromeSize(
        for contentSize: CGSize,
        displayedAxisLength: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGSize {
        if position.isVertical {
            return CGSize(width: contentSize.width, height: displayedAxisLength)
        }

        return CGSize(width: displayedAxisLength, height: contentSize.height)
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

    private func targetScreen() -> NSScreen? {
        switch preferences.windowDisplayTarget {
        case .primaryDisplay:
            return NSScreen.screens.first ?? NSScreen.main
        case .displayContainingPointer:
            let mouseLocation = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
                ?? screen
                ?? NSScreen.main
                ?? NSScreen.screens.first
        }
    }
}
