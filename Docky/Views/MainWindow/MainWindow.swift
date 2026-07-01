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
    private let contentView = ClickThroughHostingView(rootView: MainWindowView())
    private var trackingArea: NSTrackingArea?
    private var topConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!

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

        topConstraint = contentView.topAnchor.constraint(equalTo: topAnchor)
        bottomConstraint = bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        leadingConstraint = contentView.leadingAnchor.constraint(equalTo: leadingAnchor)
        trailingConstraint = trailingAnchor.constraint(equalTo: contentView.trailingAnchor)

        NSLayoutConstraint.activate([
            topConstraint, bottomConstraint, leadingConstraint, trailingConstraint
        ])

        applyContentInsets()
        observePreferencesForInsets()
    }

    /// Re-applies the per-edge content padding. Full-axis mode forces
    /// every edge to 0 so the chrome bleeds to the panel border; in
    /// fit-content mode each edge picks up its own theme/user override
    /// from `DockyPreferences`.
    private func applyContentInsets() {
        let prefs = DockyPreferences.shared
        let fullAxis = prefs.effectiveWindowAxisSizing == .fullAxis
        let top = fullAxis ? 0 : prefs.effectiveWindowContentInsetTop
        let leading = fullAxis ? 0 : prefs.effectiveWindowContentInsetLeading
        let bottom = fullAxis ? 0 : prefs.effectiveWindowContentInsetBottom
        let trailing = fullAxis ? 0 : prefs.effectiveWindowContentInsetTrailing
        topConstraint.constant = top
        bottomConstraint.constant = bottom
        leadingConstraint.constant = leading
        trailingConstraint.constant = trailing
    }

    /// Observation-framework wiring: every read inside the closure is
    /// tracked; the `onChange` callback fires once per change, then we
    /// re-register by recursing. Same pattern AppKit code elsewhere in
    /// the project uses to bridge from `@Observable` into NSView land.
    private func observePreferencesForInsets() {
        withObservationTracking {
            _ = DockyPreferences.shared.effectiveWindowAxisSizing
            _ = DockyPreferences.shared.effectiveWindowContentInsetTop
            _ = DockyPreferences.shared.effectiveWindowContentInsetLeading
            _ = DockyPreferences.shared.effectiveWindowContentInsetBottom
            _ = DockyPreferences.shared.effectiveWindowContentInsetTrailing
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyContentInsets()
                self.observePreferencesForInsets()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        (window as? MainWindow)?.pointerDidEnterWindow()
        forwardMagnificationPointer(from: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        forwardMagnificationPointer(from: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        (window as? MainWindow)?.pointerDidExitWindow()
        DockMagnificationService.shared.clearPointer()
    }

    /// Pushes the live pointer position into the magnification service in
    /// the hosting view's top-left origin coordinate space, same as what
    /// SwiftUI sees via `GeometryProxy.frame(in: .global)`. Caller flips Y
    /// when the underlying NSHostingView isn't already flipped.
    ///
    /// We only forward when the cursor is within the chrome's cross-axis
    /// strip. The window is taller (or wider, for side docks) than the
    /// chrome to make room for magnified icons, so a window-wide tracking
    /// area would magnify tiles as soon as the pointer entered the empty
    /// headroom above the chrome, well before it ever touched a tile.
    private func forwardMagnificationPointer(from event: NSEvent) {
        let inHosting = contentView.convert(event.locationInWindow, from: nil)
        let topLeft: CGPoint = contentView.isFlipped
            ? inHosting
            : CGPoint(x: inHosting.x, y: contentView.bounds.height - inHosting.y)
        guard cursorIsAtChromeFringe(topLeft, hostingSize: contentView.bounds.size) else {
            DockMagnificationService.shared.clearPointer()
            return
        }
        DockMagnificationService.shared.updatePointer(at: topLeft)
    }

    /// Cross-axis bounds check against the resting chrome. We don't gate
    /// on the along-axis (proximity to dock edge in that direction is the
    /// whole point of the cosine falloff), only the cross-axis fringe.
    private func cursorIsAtChromeFringe(_ point: CGPoint, hostingSize: CGSize) -> Bool {
        let chromeSize = DockLayoutService.shared.chromeSize
        guard chromeSize.width > 0, chromeSize.height > 0 else { return true }
        let position = DockyPreferences.shared.windowPosition
            .resolved(systemOrientation: DockSettingsService.shared.orientation)
        switch position {
        case .bottom:
            return point.y >= hostingSize.height - chromeSize.height
        case .top:
            return point.y <= chromeSize.height
        case .left:
            return point.x <= chromeSize.width
        case .right:
            return point.x >= hostingSize.width - chromeSize.width
        }
    }
}

/// NSPanel (not NSWindow) so the `.nonactivatingPanel` style mask actually
/// takes effect, that's the only way to keep clicks on the dock from
/// activating Docky as a foreground app, which would otherwise break
/// frontmost-tracked behaviors (cycle windows on tile click, hide-on-second-click).
final class MainWindow: NSPanel {
    /// We default to `false` so tile clicks don't bring Docky to the
    /// foreground (frontmost-tracked behaviors like cycle-on-click rely
    /// on the previously-frontmost app staying key). Embedded controls
    /// that need keyboard input, currently only the Search widget's
    /// 2x/3x text field, set `allowsKeyWindow` to `true` while focused
    /// so SwiftUI can route keystrokes into them, then flip it back off
    /// on resign.
    static var allowsKeyWindow: Bool = false
    override var canBecomeKey: Bool { Self.allowsKeyWindow }
    override var canBecomeMain: Bool { false }

    override var level: NSWindow.Level { get { .mainMenu } set {} }

    private enum VisibilityState {
        case visible
        case hidden
    }

    private let backgroundBlurRadius = 10
    private let hiddenRevealThickness: CGFloat = 2
    private let baseAutohideAnimationDuration: TimeInterval = 0.22
    private let tileMutationAnimationDuration: TimeInterval = 0.18
    private let dockSettings = DockSettingsService.shared
    private let preferences = DockyPreferences.shared
    private let layout = DockLayoutService.shared
    private let tileStore = TileStore.shared
    private let editMode = DockEditModeService.shared
    private let minimumWidth: CGFloat = 120
    private var cancellables: Set<AnyCancellable> = []
    private var hideWorkItem: DispatchWorkItem?
    private var fullscreenRecheckWorkItem: DispatchWorkItem?
    private var fullscreenRevealWorkItem: DispatchWorkItem?
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
    private var isFullscreenActiveOnTargetScreen = false
    private var isMaximizedActiveOnTargetScreen = false

    private var fullscreenHidingActive: Bool {
        isFullscreenActiveOnTargetScreen && preferences.hidesDuringFullscreen
    }

    private var effectivelyAutohides: Bool {
        preferences.autohidesWindow
            || fullscreenHidingActive
            || (isMaximizedActiveOnTargetScreen && preferences.maximizedWindowBehavior == .hideDocky)
    }

    private var isContentOverlapActive: Bool {
        fullscreenHidingActive
            || (isMaximizedActiveOnTargetScreen && preferences.maximizedWindowBehavior == .hideDocky)
    }

    /// The frame Docky claims for content reservation, or nil when Docky is
    /// hidden / off-screen / not currently rendering. Used by services that
    /// keep other apps' windows out of Docky's way.
    var currentReservationFrame: CGRect? {
        visibilityState == .visible ? frame : nil
    }

    /// Screen-coordinate rect of the visible chrome (the dock pill itself,
    /// not the magnification headroom around it). Built from `chromeSize`
    /// rather than crossing the SwiftUI/AppKit coord boundary, since the
    /// chrome is always centered along-axis within the window (in
    /// full-axis mode it just happens to span edge-to-edge), and pinned
    /// to the inward cross-axis edge with magnification headroom on the
    /// other side. Overlays that need to align to chrome edges read this.
    func chromeScreenFrame() -> CGRect? {
        let chromeSize = DockLayoutService.shared.chromeSize
        guard chromeSize.width > 0, chromeSize.height > 0 else { return nil }
        let position = DockyPreferences.shared.windowPosition
            .resolved(systemOrientation: DockSettingsService.shared.orientation)
        let f = frame
        let width = min(chromeSize.width, f.width)
        let height = min(chromeSize.height, f.height)
        switch position {
        case .bottom:
            return CGRect(x: f.midX - width / 2, y: f.minY, width: width, height: height)
        case .top:
            return CGRect(x: f.midX - width / 2, y: f.maxY - height, width: width, height: height)
        case .left:
            return CGRect(x: f.minX, y: f.midY - height / 2, width: width, height: height)
        case .right:
            return CGRect(x: f.maxX - width, y: f.midY - height / 2, width: width, height: height)
        }
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        visibilityState = DockyPreferences.shared.autohidesWindow ? .hidden : .visible
        // Force `.nonactivatingPanel` regardless of what the XIB hands us so
        // tile clicks never bring Docky to the foreground. Other bits stay
        // intact (the XIB-supplied mask covers titled/resizable/etc.).
        super.init(
            contentRect: contentRect,
            styleMask: style.union(.nonactivatingPanel),
            backing: backingStoreType,
            defer: flag
        )
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
        // Magnification tracking lives on the content view's NSTrackingArea
        // (.mouseMoved + .activeAlways). Enabling mouseMoved on the window
        // itself ensures AppKit routes those events through the responder
        // chain even though this panel never becomes key.
        acceptsMouseMovedEvents = true
        applyCollectionBehavior()
        observeFrameInputs()
        observeScreenAndSpaceInputs()
        observeWindowPlacementInputs()
        observeVisibilityInputs()
        updatePointerScreenMonitoring()
        updateDragRevealMonitoring()
        let initialOverlap = computeContentOverlapStateOnTargetScreen()
        isFullscreenActiveOnTargetScreen = initialOverlap.isFullscreen
        isMaximizedActiveOnTargetScreen = initialOverlap.isMaximized
        if isContentOverlapActive {
            visibilityState = shouldRemainVisible ? .visible : .hidden
        }
    }

    deinit {
        fullscreenRecheckWorkItem?.cancel()
        fullscreenRevealWorkItem?.cancel()
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
        // DockyPreferences is now `@Observable` so we read its
        // properties through `observeChanges` (Observation framework
        // auto-tracks). DockSettingsService / DockDragService /
        // DockEditModeService are still ObservableObject; their
        // `@Published` projections are merged via Combine below.
        let layoutSignals: [AnyPublisher<Void, Never>] = [
            editMode.$paletteDrag.map { _ in () }.eraseToAnyPublisher(),
            editMode.$paletteDropDestination.map { _ in () }.eraseToAnyPublisher(),
            DockDragService.shared.$kind.map { _ in () }.eraseToAnyPublisher(),
            DockDragService.shared.$documentTargetTileID.map { _ in () }.eraseToAnyPublisher(),
            DockDragService.shared.$destinationIndex.map { _ in () }.eraseToAnyPublisher(),
            DockDragService.shared.$destinationSection.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(layoutSignals)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyCurrentFrame(animated: true, duration: self?.tileMutationAnimationDuration) }
            .store(in: &cancellables)

        observeChanges { [weak self] in
            guard let self else { return }
            // Touch every preference and dock-setting that drives frame
            // layout. The Observation framework tracks these reads and
            // re-runs the closure on any change.
            _ = preferences.effectiveTileVerticalPadding
            _ = preferences.effectiveTileSpacing
            _ = preferences.overflowBehavior
            _ = preferences.effectiveWindowAxisSizing
            _ = preferences.windowPosition
            _ = preferences.windowDisplayTarget
            _ = dockSettings.orientation
            _ = dockSettings.tileSize
            _ = dockSettings.largeSize
            _ = dockSettings.magnification
            self.applyCurrentFrame(animated: true, duration: self.tileMutationAnimationDuration)
        }
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

        // Keep the dock visible while any drag is in flight (Finder→dock,
        // palette, or icon-out-of-folder). The cursor can briefly be outside
        // the dock window during the transit, so without this the dock would
        // start to auto-hide just as the user is moving the drag toward it.
        DockDragService.shared.$kind
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasDrag in
                guard let self else { return }
                if hasDrag {
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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentFrame(animated: false)
                self?.updateFullscreenStateAndApply(animated: false)
            }
            .store(in: &cancellables)

        let workspaceCenter = NSWorkspace.shared.notificationCenter

        workspaceCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentFrame(animated: false)
                self?.updateFullscreenStateAndApply(animated: true)
                // The space change fires during the fullscreen exit animation
                // while the fullscreen window is still on-screen. Re-check once
                // the animation has had time to complete.
                self?.scheduleFullscreenRecheck()
            }
            .store(in: &cancellables)

        workspaceCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFullscreenStateAndApply(animated: true)
                self?.scheduleFullscreenRecheck()
            }
            .store(in: &cancellables)
    }

    private func observeWindowPlacementInputs() {
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.windowSpaceBehavior
            self?.applyCollectionBehavior()
        }
        .store(in: &cancellables)

        observeChanges { [weak self] in
            _ = DockyPreferences.shared.windowDisplayTarget
            self?.lastPointerScreenFrame = nil
            self?.updatePointerScreenMonitoring()
            self?.updateFullscreenStateAndApply(animated: true)
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

        // App-level activate/space changes don't fire when a window in the
        // foreground app gets maximized or fullscreened, so piggy-back on the
        // registry's AX resize/move signal. Debounce so a drag-resize doesn't
        // hammer the overlap recomputation.
        WindowRegistry.shared.$windows
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFullscreenStateAndApply(animated: true)
            }
            .store(in: &cancellables)
    }

    private func observeVisibilityInputs() {
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.autohidesWindow
            self?.applyEffectiveVisibility(animated: true)
        }
        .store(in: &cancellables)

        observeChanges { [weak self] in
            _ = DockyPreferences.shared.maximizedWindowBehavior
            _ = DockyPreferences.shared.hidesDuringFullscreen
            self?.updateFullscreenStateAndApply(animated: true)
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
            self?.updateFullscreenStateAndApply(animated: true)
        }
    }

    func pointerDidEnterWindow() {
        isPointerInsideWindow = true
        hideWorkItem?.cancel()

        guard effectivelyAutohides else { return }

        if shouldDwellBeforeReveal {
            scheduleFullscreenReveal()
            return
        }

        setVisibility(.visible, animated: true)
    }

    func pointerDidExitWindow() {
        isPointerInsideWindow = false
        fullscreenRevealWorkItem?.cancel()
        fullscreenRevealWorkItem = nil
        scheduleHideIfNeeded()
    }

    private var shouldDwellBeforeReveal: Bool {
        isContentOverlapActive
            && visibilityState == .hidden
            && preferences.fullscreenRevealDelay > 0
    }

    private func scheduleFullscreenReveal() {
        fullscreenRevealWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.isPointerInsideWindow,
                  self.effectivelyAutohides
            else { return }
            self.setVisibility(.visible, animated: true)
        }
        fullscreenRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.fullscreenRevealDelay, execute: workItem)
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

        guard effectivelyAutohides else { return }
        setVisibility(.visible, animated: true)
    }

    func endInteraction() {
        activeInteractionCount = max(0, activeInteractionCount - 1)
        scheduleHideIfNeeded()
    }

    private func applyEffectiveVisibility(animated: Bool) {
        hideWorkItem?.cancel()

        if effectivelyAutohides {
            let nextState: VisibilityState = shouldRemainVisible ? .visible : .hidden
            setVisibility(nextState, animated: animated)
            return
        }

        setVisibility(.visible, animated: animated)
    }

    private func scheduleHideIfNeeded() {
        hideWorkItem?.cancel()

        guard effectivelyAutohides, !shouldRemainVisible else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.shouldRemainVisible else { return }
            self.setVisibility(.hidden, animated: true)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.autohideWindowDelay, execute: workItem)
    }

    private var shouldRemainVisible: Bool {
        isPointerInsideWindow || activeInteractionCount > 0 || editMode.isActive || DockDragService.shared.kind != nil
    }

    private func setVisibility(_ state: VisibilityState, animated: Bool) {
        if state == .visible {
            fullscreenRevealWorkItem?.cancel()
            fullscreenRevealWorkItem = nil
        }

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
        let resolvedScreen = targetScreen() ?? screen ?? NSScreen.main
        let screenBounds = resolvedScreen?.frame ?? .zero
        lastPointerScreenFrame = screenBounds
        // Vertical full-axis used to span `screen.frame` and slipped
        // behind the menu bar (and the system Dock, when shown). Use
        // `visibleFrame` for vertical positions so axis length and
        // origin centering are computed against the same clamped
        // rect — the dock then sits exactly between the menu bar
        // and the system Dock without any per-edge offset math.
        // Horizontal positions stay anchored to `screen.frame` so a
        // top dock keeps anchoring to the top edge, etc.
        let visibleBounds = resolvedScreen?.visibleFrame ?? screenBounds
        // Window-frame math needs the *total* horizontal and vertical
        // padding the chrome view leaves around itself inside the panel.
        // Per-edge insets live in `DockyPreferences`; full-axis mode
        // forces them to zero in `MainWindowContainerView` and we
        // mirror that here so the panel sizing stays in sync.
        let fullAxis = preferences.effectiveWindowAxisSizing == .fullAxis
        let horizontalContentPadding: CGFloat = fullAxis ? 0
            : preferences.effectiveWindowContentInsetLeading + preferences.effectiveWindowContentInsetTrailing
        let verticalContentPadding: CGFloat = fullAxis ? 0
            : preferences.effectiveWindowContentInsetTop + preferences.effectiveWindowContentInsetBottom
        let position = preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
        let baseTileSize = dockSettings.displayTileSize
        let baseTileHeight = baseTileSize + preferences.effectiveTileVerticalPadding * 2
        let externalAppDropPreview: AppTile? = {
            if case let .app(_, tile) = DockDragService.shared.kind { return tile }
            return nil
        }()
        let externalFolderDropPreview: FolderTile? = {
            // Only grow the chrome when there's an actual placement: cursor in the
            // trailing drop region with a resolved insertion index. Open-with mode
            // (over an app tile) and idle hovering both leave chrome unchanged.
            guard DockDragService.shared.documentTargetTileID == nil,
                  DockDragService.shared.destinationSection == .trailing,
                  DockDragService.shared.destinationIndex != nil,
                  case let .folder(_, tile) = DockDragService.shared.kind else {
                return nil
            }
            return tile
        }()
        let sizingTiles = TileContainerView.previewedTiles(
            from: tileStore.tiles,
            paletteDrag: editMode.paletteDrag,
            paletteDropDestination: editMode.paletteDropDestination,
            externalAppDropPreview: externalAppDropPreview,
            externalFolderDropPreview: externalFolderDropPreview
        )
        let naturalContentSize = TileContainerView.contentSize(
            tiles: sizingTiles,
            tileSize: baseTileSize,
            tileHeight: baseTileHeight,
            tileSpacing: preferences.effectiveTileSpacing,
            position: position
        )
        let alongAxisContentPadding = position.isVertical ? verticalContentPadding : horizontalContentPadding
        let layoutBounds = position.isVertical ? visibleBounds : screenBounds
        let unreservedAvailableAxisLength = max(
            0,
            axisLength(of: layoutBounds.size, position: position) - alongAxisContentPadding
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
        let availableAxisLength = preferences.effectiveWindowAxisSizing == .fullAxis
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
            tileSpacing: preferences.effectiveTileSpacing,
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
        let scaledTileHeight = scaledTileSize + (preferences.effectiveTileVerticalPadding * contentScale * 2)
        let scaledTileSpacing = preferences.effectiveTileSpacing * contentScale
        let displayedContentSize = TileContainerView.contentSize(
            tiles: sizingTiles,
            tileSize: scaledTileSize,
            tileHeight: scaledTileHeight,
            tileSpacing: scaledTileSpacing,
            position: position,
            compactWidgets: compactsWidgetsForOverflow,
            edgePadding: TileContainerView.edgePadding * contentScale
        )
        let displayedChromeAxisLength = preferences.effectiveWindowAxisSizing == .fullAxis
            ? availableAxisLength
            : min(axisLength(of: displayedContentSize, position: position), availableAxisLength)
        layout.setChromeSize(displayedChromeSize(
            for: displayedContentSize,
            displayedAxisLength: displayedChromeAxisLength,
            position: position
        ))
        // Keep the chrome stretched across the current dock axis even when the
        // tile layout itself remains content-sized.
        let displayedAxisLength = availableAxisLength
        // Magnified icons render beyond the chrome's natural cross-axis
        // extent. We grow only the window, not the chrome rect, so the
        // chrome itself keeps its resting shape and the icons spill into
        // the headroom above (or beside, on a vertical dock) it. Peak
        // size is the UNscaled `largeSize` even when overflow has shrunk
        // the resting tiles, so headroom is measured from the scaled
        // chrome height up to that fixed peak.
        let scaledBaseTileSize = dockSettings.tileSize * contentScale
        let magnificationHeadroom: CGFloat = (
            dockSettings.magnification && dockSettings.largeSize > scaledBaseTileSize
        )
            ? dockSettings.largeSize - scaledBaseTileSize
            : 0
        let windowContentSize: CGSize = {
            guard magnificationHeadroom > 0 else { return displayedContentSize }
            return position.isVertical
                ? CGSize(width: displayedContentSize.width + magnificationHeadroom, height: displayedContentSize.height)
                : CGSize(width: displayedContentSize.width, height: displayedContentSize.height + magnificationHeadroom)
        }()
        let width = displayedWindowWidth(
            for: windowContentSize,
            displayedAxisLength: displayedAxisLength,
            availableAxisLength: availableAxisLength,
            horizontalContentPadding: horizontalContentPadding,
            position: position
        )
        let height = displayedWindowHeight(
            for: windowContentSize,
            displayedAxisLength: displayedAxisLength,
            verticalContentPadding: verticalContentPadding,
            position: position
        )
        let size = CGSize(width: width, height: height)
        let origin = frameOrigin(
            in: layoutBounds,
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
        max(0.16, min(0.5, baseAutohideAnimationDuration * max(dockSettings.autohideTimeModifier, 0.01)))
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
        horizontalContentPadding: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGFloat {
        if position.isVertical {
            return contentSize.width + horizontalContentPadding
        }

        let visibleAxisLength = availableAxisLength > 0
            ? min(max(minimumWidth, displayedAxisLength), availableAxisLength)
            : max(minimumWidth, displayedAxisLength)
        return visibleAxisLength + horizontalContentPadding
    }

    private func displayedWindowHeight(
        for contentSize: CGSize,
        displayedAxisLength: CGFloat,
        verticalContentPadding: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGFloat {
        if position.isVertical {
            return displayedAxisLength + verticalContentPadding
        }

        return contentSize.height + verticalContentPadding
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

    private func updateFullscreenStateAndApply(animated: Bool) {
        let observation = computeContentOverlapStateOnTargetScreen()
        let fullscreenChanged = observation.isFullscreen != isFullscreenActiveOnTargetScreen
        let maximizedChanged = observation.isMaximized != isMaximizedActiveOnTargetScreen
        guard fullscreenChanged || maximizedChanged else { return }
        isFullscreenActiveOnTargetScreen = observation.isFullscreen
        isMaximizedActiveOnTargetScreen = observation.isMaximized
        applyEffectiveVisibility(animated: animated)
    }

    private func scheduleFullscreenRecheck() {
        fullscreenRecheckWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateFullscreenStateAndApply(animated: true)
        }
        fullscreenRecheckWorkItem = workItem
        // Long enough to cover the macOS fullscreen exit animation, which can
        // run up to ~750 ms with reduce-motion off.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: workItem)
    }

    private struct ContentOverlapObservation {
        let isFullscreen: Bool
        let isMaximized: Bool
    }

    private func computeContentOverlapStateOnTargetScreen() -> ContentOverlapObservation {
        guard let screen = targetScreen(),
              let primaryScreenHeight = NSScreen.screens.first?.frame.height
        else {
            return ContentOverlapObservation(isFullscreen: false, isMaximized: false)
        }

        let listOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(listOptions, kCGNullWindowID) as? [[String: Any]] else {
            return ContentOverlapObservation(isFullscreen: false, isMaximized: false)
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame
        var fullscreenCandidate = false
        var foundMaximized = false

        for info in windows {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }

            if let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
               pidNumber.int32Value == ownPID {
                continue
            }

            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }

            // CGWindow uses a flipped Y axis with origin at the top-left of the
            // primary display; convert back to NSScreen space before comparing.
            let nsBounds = CGRect(
                x: cgBounds.minX,
                y: primaryScreenHeight - cgBounds.maxY,
                width: cgBounds.width,
                height: cgBounds.height
            )

            // Fullscreen: window covers the entire NSScreen.frame (including
            // the menubar area). Maximized: window matches visibleFrame
            // exactly, which is smaller than frame by the menubar.
            if Self.rect(nsBounds, matches: frame) {
                fullscreenCandidate = true
            } else if Self.rect(nsBounds, matches: visibleFrame) {
                foundMaximized = true
            }

            if fullscreenCandidate && foundMaximized { break }
        }

        let foundFullscreen = fullscreenCandidate
            && registryReportsFullscreenWindow(matching: frame, primaryScreenHeight: primaryScreenHeight)

        return ContentOverlapObservation(isFullscreen: foundFullscreen, isMaximized: foundMaximized)
    }

    private func registryReportsFullscreenWindow(matching frame: CGRect, primaryScreenHeight: CGFloat) -> Bool {
        WindowRegistry.shared.windows.contains { window in
            guard !window.isMinimized, let axFrame = window.frame else { return false }
            let nsFrame = CGRect(
                x: axFrame.minX,
                y: primaryScreenHeight - axFrame.maxY,
                width: axFrame.width,
                height: axFrame.height
            )
            return Self.rect(nsFrame, matches: frame, tolerance: 2)
        }
    }

    private static func rect(_ a: CGRect, matches b: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(a.minX - b.minX) < tolerance
            && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance
            && abs(a.height - b.height) < tolerance
    }
}
