//
//  LaunchpadOverlayWindowController.swift
//  Docky
//

import AppKit
import Combine
import SwiftUI

final class LaunchpadOverlayWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var isInterruptingMainWindow = false
    private let animationDuration: TimeInterval = 0.18
    private let preferences = DockyPreferences.shared
    /// The screen the launchpad is currently anchored to. Resolved at present
    /// time from the cursor location so the overlay always opens on the
    /// display the user is looking at.
    private weak var anchoredScreen: NSScreen?

    init(mainWindow: MainWindow) {
        self.mainWindow = mainWindow

        let overlayWindow = LaunchpadOverlayWindow()
        let hostingController = NSHostingController(rootView: LaunchpadOverlayView())
        overlayWindow.contentViewController = hostingController

        super.init(window: overlayWindow)

        prepareOverlayWindow()
        observeOverlayPresentation()
        observeMainWindow()
        observeSpaceBehavior()
        observeAppActivation()
    }

    /// Cmd+Tab (and any other path that puts another app frontmost) takes
    /// focus away from Docky, so the launchpad — which presented itself by
    /// activating Docky — should dismiss to match the user's intent.
    private func observeAppActivation() {
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                guard LaunchpadOverlayService.shared.isPresented else { return }
                LaunchpadOverlayService.shared.dismiss()
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func observeOverlayPresentation() {
        LaunchpadOverlayService.shared.$isPresented
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPresented in
                guard let self else { return }
                if isPresented {
                    self.presentOverlay()
                } else {
                    self.dismissOverlay()
                }
            }
            .store(in: &cancellables)
    }

    private func observeMainWindow() {
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: mainWindow)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: mainWindow))
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification, object: mainWindow))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFrame()
            }
            .store(in: &cancellables)
    }

    private func presentOverlay() {
        guard let window else { return }

        anchoredScreen = screenForCursor()
        updateWallpaper(for: anchoredScreen)
        updateFrame()
        beginMainWindowInteraction()
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
        animateWindowAlpha(to: 1)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func screenForCursor() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? mainWindow?.screen
            ?? NSScreen.main
    }

    private func updateWallpaper(for screen: NSScreen?) {
        let url = screen.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        if LaunchpadOverlayService.shared.wallpaperURL != url {
            LaunchpadOverlayService.shared.wallpaperURL = url
        }
    }

    private func dismissOverlay() {
        animateWindowAlpha(to: 0) { [weak self] in
            guard let self, let window = self.window else { return }

            window.ignoresMouseEvents = true
            window.orderOut(nil)
            self.mainWindow?.makeKey()
        }
        endMainWindowInteraction()
    }

    private func prepareOverlayWindow() {
        guard let window else { return }

        updateFrame()
        window.collectionBehavior = preferences.windowSpaceBehavior.collectionBehavior(includesFullScreenAuxiliary: true)
        configureHiddenWindowState()
    }

    private func observeSpaceBehavior() {
        observeChanges { [weak self] in
            let behavior = DockyPreferences.shared.windowSpaceBehavior
            self?.window?.collectionBehavior = behavior.collectionBehavior(includesFullScreenAuxiliary: true)
        }
        .store(in: &cancellables)
    }

    private func configureHiddenWindowState() {
        guard let window else { return }

        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderOut(nil)
    }

    private func animateWindowAlpha(to alphaValue: CGFloat, completion: (() -> Void)? = nil) {
        guard let window else {
            completion?()
            return
        }

        window.animator().alphaValue = window.alphaValue

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = alphaValue
        } completionHandler: {
            completion?()
        }
    }

    private func updateFrame() {
        guard let window else { return }
        let screenFrame = anchoredScreen?.frame
            ?? mainWindow?.screen?.frame
            ?? NSScreen.main?.frame
            ?? .zero
        guard !screenFrame.isEmpty else { return }
        window.setFrame(screenFrame, display: window.isVisible)
    }

    private func beginMainWindowInteraction() {
        guard !isInterruptingMainWindow else { return }
        mainWindow?.beginInteraction()
        isInterruptingMainWindow = true
    }

    private func endMainWindowInteraction() {
        guard isInterruptingMainWindow else { return }
        mainWindow?.endInteraction()
        isInterruptingMainWindow = false
    }
}

private final class LaunchpadOverlayWindow: NSWindow {
    private let backgroundBlurRadius = 40

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        applyBackgroundBlur()
    }

    /// Mirrors `MainWindow.applyBackgroundBlur` so the launchpad overlay rides
    /// the same private SkyLight backdrop blur as the dock chrome. Applied on
    /// every order — the window number is only valid once the window is on
    /// screen, and `orderOut` invalidates it.
    private func applyBackgroundBlur() {
        guard windowNumber > 0 else { return }
        _ = CGSSetWindowBackgroundBlurRadius(
            CGSMainConnectionID(),
            windowNumber,
            backgroundBlurRadius
        )
    }
}

/// Live state for an in-flight Launchpad drag. The display layer
/// reorders entries based on `targetIndex` so siblings shift to make
/// way as the cursor moves; the dragged tile renders both as a
/// translucent placeholder in its preview slot and as a floating
/// copy that follows the cursor.
private struct LaunchpadDragState: Equatable {
    let layoutItemID: String
    let originIndex: Int
    /// Insert position the dragged item would land at if dropped now.
    var targetIndex: Int
    /// Cursor location in the launchpad grid coordinate space.
    var location: CGPoint
    /// When non-nil the drag is hovering over a single cell long
    /// enough to convert from a reorder into a folder merge.
    var mergeTargetItemID: String?
}

/// Preference key that aggregates per-cell frames keyed by layout id.
/// Used by the drag handler to map the cursor to an insertion index.
private struct LaunchpadCellFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct LaunchpadOverlayView: View {
    @ObservedObject private var overlay = LaunchpadOverlayService.shared
    @Bindable private var preferences = DockyPreferences.shared
    @State private var searchText = ""
    @State private var selectedEntryID: String?
    @State private var visiblePageID: String?
    /// Source of truth for vertical-mode scroll position. Tracks the
    /// entry currently anchored at the top of the viewport so we can
    /// auto-scroll to follow keyboard selection.
    @State private var visibleEntryID: String?
    @State private var expandedFolderID: String?
    @State private var renamingFolderID: String?
    @State private var renamingFolderDraft: String = ""
    /// Drives in-place rename of the expanded folder's title. Lifted to
    /// the parent so `handleKeyDown` can route Enter to commit and Esc
    /// to cancel before the launchpad-level monitor consumes them.
    @State private var isRenamingExpandedFolder: Bool = false
    @State private var expandedFolderRenameDraft: String = ""
    @State private var dragState: LaunchpadDragState?
    @State private var cellFrames: [String: CGRect] = [:]
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isRenameFocused: Bool

    private static let launchpadGridCoordinateSpace = "launchpadGrid"

    private let searchBarWidth: CGFloat = 280
    private let searchBarTopInset: CGFloat = 56
    private let searchBarHeight: CGFloat = 64
    /// Minimum inter-row spacing. The actual spacing grows past this when
    /// the configured rows don't fill the available height, so the grid
    /// stretches vertically to fit the chrome. Kept hardcoded because
    /// exposing it as a preference produced no perceivable change in the
    /// common case (the stretch-to-fill almost always wins).
    private let minRowSpacing: CGFloat = 32
    private let horizontalInset: CGFloat = 80
    /// Padding between the grid edge and the surrounding chrome — applied
    /// both below the search bar and above the page indicator so the grid
    /// sits visually balanced between the two.
    private let gridChromePadding: CGFloat = 56
    private let pageIndicatorBottomInset: CGFloat = 24
    /// Visual height occupied by the page-indicator dot row: each dot is
    /// 7pt with 8pt of tap-target padding on every side (7 + 16 = 23).
    private let pageIndicatorVisualHeight: CGFloat = 23
    private let wallpaperBlurRadius: CGFloat = 50
    /// Reference logical screen height the launchpad metrics are tuned
    /// for (1440p): at this height, icons render at exactly `baseIconSize`
    /// and gaps at the configured `columnSpacing` / `rowSpacing` values.
    /// Taller or shorter screens scale linearly off this baseline.
    private let referenceScreenHeight: CGFloat = 1440
    /// Reference label height below the icon, scaled with the icon.
    private let baseLabelHeight: CGFloat = 22

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        GeometryReader { proxy in
            let topInset = searchBarTopInset + searchBarHeight + gridChromePadding
            // Mirror the top so the gap from the grid bottom to the page
            // indicator equals the gap from the search bar to the grid top.
            let bottomInset = pageIndicatorBottomInset + pageIndicatorVisualHeight + gridChromePadding
            // Linear scale off the 1440p reference (screen *height*).
            // Clamped at 1.0 so icons never exceed `baseIconSize`, and at
            // 0.5 so very small displays don't shrink the cell math
            // beyond legibility.
            let scale = max(0.5, min(1.0, proxy.size.height / referenceScreenHeight))
            let iconSize = preferences.launchpadBaseIconSize * scale
            let labelHeight = baseLabelHeight * scale
            let cellSpacing = iconSize * 0.04
            let scaledColumnSpacing = preferences.launchpadColumnSpacing * scale
            let scaledMinRowSpacing = minRowSpacing * scale
            let scaledHorizontalInset = horizontalInset * scale
            // Square cells: the cell side equals the natural card height
            // (icon + label + inter-spacing) so the grid item is aspect 1:1.
            // The icon stays at `iconSize`, centered horizontally inside
            // the square — the extra width becomes padding around the icon.
            let cellHeight = iconSize + labelHeight + cellSpacing
            let cellWidth = cellHeight
            let usableWidth = max(0, proxy.size.width - scaledHorizontalInset * 2)
            let usableHeight = max(0, proxy.size.height - topInset - bottomInset)
            // Columns from the user preference, but clamped so the row
            // doesn't overflow the screen on narrow displays.
            let configuredColumns = max(1, preferences.launchpadGridColumnCount)
            let configuredRows = max(1, preferences.launchpadGridRowCount)
            let maxColumnsThatFit = max(1, Int((usableWidth + scaledColumnSpacing) / (cellWidth + scaledColumnSpacing)))
            let maxRowsThatFit = max(1, Int((usableHeight + scaledMinRowSpacing) / (cellHeight + scaledMinRowSpacing)))
            let pageColumns = max(1, min(configuredColumns, maxColumnsThatFit))
            // Honor the configured row count, but never exceed what fits
            // on screen — otherwise rows would overflow the page.
            let pageRows = max(1, min(configuredRows, maxRowsThatFit))
            // Stretch the grid to fill `usableHeight`: distribute any
            // leftover vertical space across the inter-row gaps. The min
            // is the floor, so when the configured rows already fill the
            // height, spacing stays at the floor.
            let extraVertical = max(0, usableHeight - cellHeight * CGFloat(pageRows))
            let scaledRowSpacing = pageRows > 1
                ? max(scaledMinRowSpacing, extraVertical / CGFloat(pageRows - 1))
                : scaledMinRowSpacing
            let isVertical = preferences.launchpadLayoutAxis == .vertical
            let pageSize = pageColumns * pageRows
            let pages = isVertical ? [] : paginate(displayedEntries, pageSize: pageSize)
            // In vertical mode no page indicator / chevrons render, so
            // the bottom of the grid only needs the small ambient
            // padding the chrome reserves around all edges.
            let resolvedBottomInset = isVertical ? gridChromePadding : bottomInset

            ZStack {
                wallpaperBackground(in: proxy.size)

                Color.black
                    .opacity(1 - preferences.launchpadOverlayTransparency)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        overlay.dismiss()
                    }

                if isVertical {
                    verticalScrollView(
                        cellWidth: cellWidth,
                        cellHeight: cellHeight,
                        iconSide: iconSize,
                        columns: pageColumns,
                        columnSpacing: scaledColumnSpacing,
                        rowSpacing: scaledRowSpacing,
                        horizontalInset: scaledHorizontalInset,
                        topInset: topInset,
                        bottomInset: resolvedBottomInset
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 0) {
                                ForEach(pages.indices, id: \.self) { pageIndex in
                                    pageGrid(
                                        pageEntries: pages[pageIndex],
                                        cellWidth: cellWidth,
                                        cellHeight: cellHeight,
                                        iconSide: iconSize,
                                        pageWidth: proxy.size.width,
                                        columns: pageColumns,
                                        columnSpacing: scaledColumnSpacing,
                                        rowSpacing: scaledRowSpacing,
                                        horizontalInset: scaledHorizontalInset
                                    )
                                    .id("page-\(pageIndex)")
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $visiblePageID, anchor: .leading)
                        .scrollClipDisabled()
                        .padding(.top, topInset)
                        .padding(.bottom, resolvedBottomInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: selectedEntryID) { selection in
                            guard let selection,
                                  let pageIndex = pageIndex(for: selection, in: pages) else { return }
                            withAnimation(.easeInOut(duration: 0.18)) {
                                scrollProxy.scrollTo("page-\(pageIndex)", anchor: .leading)
                            }
                        }
                        .onChange(of: filteredEntries.map(\.id)) { _ in
                            synchronizeSelection()
                        }
                    }
                }

                VStack {
                    // ZStack so the surrounding band acts as a dismiss
                    // target. The full-width clear layer sits behind the
                    // capsule, so taps on the capsule (text field, clear,
                    // gear) still route to their owners and only clicks
                    // in the empty strip flow through to `overlay.dismiss`.
                    // The capsule is bottom-anchored so it lands at the
                    // same y-position the previous `.padding(.top:)` gave it.
                    ZStack(alignment: .bottom) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { overlay.dismiss() }
                        searchField
                            .frame(width: searchBarWidth, height: searchBarHeight)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: searchBarHeight + searchBarTopInset)

                    Spacer()

                    if !isVertical {
                        pageIndicator(pageCount: pages.count, currentIndex: currentPageIndex(in: pages)) { index in
                            scrollToPage(index: index, pageCount: pages.count)
                        }
                        .padding(.bottom, pageIndicatorBottomInset)
                    }
                }

                if !isVertical {
                    pageNavigationChevrons(pageCount: pages.count, currentIndex: currentPageIndex(in: pages))
                }

                if let renamingFolderID {
                    folderRenameOverlay(folderID: renamingFolderID)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(2)
                }

                if let folder = expandedFolder {
                    ExpandedFolderOverlay(
                        folder: folder,
                        folderLayoutID: folderLayoutID(for: folder),
                        sourceCellSize: CGSize(width: cellWidth, height: cellHeight),
                        sourceIconSide: iconSize,
                        columnsPerPage: pageColumns,
                        rowsPerPage: pageRows,
                        isRenaming: $isRenamingExpandedFolder,
                        renameDraft: $expandedFolderRenameDraft,
                        onLaunch: { app in
                            launch(app)
                        },
                        onDismiss: {
                            dismissExpandedFolder()
                        },
                        onCommitRename: {
                            commitExpandedFolderRename()
                        }
                    )
                    // Scale 1.3 → 1.0 with a fade gives the "falling on top"
                    // feel the user asked for. Symmetric so dismiss reverses
                    // it: scale 1.0 → 1.3 with a fade out.
                    .transition(.scale(scale: 1.3).combined(with: .opacity))
                    .zIndex(1)
                }

                // Floating copy of the dragged tile, anchored to the
                // cursor. The grid below keeps a translucent ghost in
                // the dragged item's preview slot, so siblings shift
                // around it while this duplicate follows the pointer.
                if let dragState,
                   let entry = filteredEntries.first(where: { layoutItemID(for: $0) == dragState.layoutItemID }) {
                    floatingDragPreview(for: entry, cellSize: CGSize(width: cellWidth, height: cellHeight), iconSide: iconSize)
                        .position(dragState.location)
                        .scaleEffect(1.08)
                        .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
                        .opacity(0.95)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .zIndex(5)
                }
            }
            .coordinateSpace(name: Self.launchpadGridCoordinateSpace)
            .onPreferenceChange(LaunchpadCellFramePreference.self) { frames in
                cellFrames = frames
            }
            .ignoresSafeArea()
            .environment(\.colorScheme, preferredColorScheme)
            .onExitCommand {
                if isRenamingExpandedFolder {
                    cancelExpandedFolderRename()
                } else if renamingFolderID != nil {
                    dismissRename(save: false)
                } else if expandedFolder != nil {
                    dismissExpandedFolder()
                } else {
                    overlay.dismiss()
                }
            }
            .background {
                LaunchpadOverlayKeyMonitor { event in
                    handleKeyDown(event, columnCount: pageColumns, rowCount: pageRows)
                }
            }
            .onAppear {
                isSearchFocused = true
                synchronizeSelection()
            }
            .onChange(of: overlay.isPresented) { isPresented in
                if isPresented {
                    searchText = ""
                    isSearchFocused = true
                    synchronizeSelection()
                }
            }
        }
    }

    /// Loads the cached wallpaper for the screen the overlay is currently
    /// anchored to and renders it under a heavy SwiftUI blur. The blur is
    /// done in-window (rather than via the SkyLight backdrop on the window)
    /// so we can guarantee that the visible base is the desktop wallpaper —
    /// not whatever app windows happen to sit underneath.
    @ViewBuilder
    private func wallpaperBackground(in size: CGSize) -> some View {
        if let url = overlay.wallpaperURL,
           let image = IconCacheService.shared.image(forImageFileURL: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .blur(radius: wallpaperBlurRadius, opaque: true)
                .clipped()
                .allowsHitTesting(false)
        }
    }

    private func pageGrid(
        pageEntries: [LaunchpadEntry],
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        iconSide: CGFloat,
        pageWidth: CGFloat,
        columns: Int,
        columnSpacing: CGFloat,
        rowSpacing: CGFloat,
        horizontalInset: CGFloat
    ) -> some View {
        let gridColumns = Array(
            repeating: GridItem(.fixed(cellWidth), spacing: columnSpacing, alignment: .top),
            count: columns
        )

        // Center the grid horizontally on the page: spacers on either
        // side of a `.fixedSize`-clamped LazyVGrid eat the leftover width
        // equally. Vertical alignment stays at the top via the outer
        // `.frame(maxHeight: .infinity, alignment: .top)`.
        return HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: horizontalInset)

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: rowSpacing) {
                ForEach(pageEntries) { entry in
                    entryCell(
                        for: entry,
                        cellSize: CGSize(width: cellWidth, height: cellHeight),
                        iconSide: iconSide
                    )
                    .frame(width: cellWidth, height: cellHeight)
                    .id(entry.id)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: horizontalInset)
        }
        .frame(width: pageWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        // Sits behind the grid so button taps on icons consume their own
        // gesture first; only taps on truly empty page area fall through
        // and dismiss. Necessary because the ScrollView covers the page
        // region, so the outer tint's dismiss gesture can't reach here.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    overlay.dismiss()
                }
        )
    }

    /// Vertical "Apps view"-style rendering: a single continuous
    /// `LazyVGrid` of every `LaunchpadEntry`, scrolling freely.
    ///
    /// `topInset` / `bottomInset` are applied as `.contentMargins`
    /// rather than outer paddings so the scroll viewport occupies
    /// the full chrome area, content can scroll behind the search
    /// bar and dock chrome, and `.scrollClipDisabled()` lets cells
    /// render past the viewport edges without getting clipped (e.g.
    /// during drag previews).
    @ViewBuilder
    private func verticalScrollView(
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        iconSide: CGFloat,
        columns: Int,
        columnSpacing: CGFloat,
        rowSpacing: CGFloat,
        horizontalInset: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> some View {
        let gridColumns = Array(
            repeating: GridItem(.fixed(cellWidth), spacing: columnSpacing, alignment: .top),
            count: columns
        )

        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    Spacer(minLength: horizontalInset)

                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: rowSpacing) {
                        ForEach(displayedEntries) { entry in
                            entryCell(
                                for: entry,
                                cellSize: CGSize(width: cellWidth, height: cellHeight),
                                iconSide: iconSide
                            )
                            .frame(width: cellWidth, height: cellHeight)
                            .id(entry.id)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: horizontalInset)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { overlay.dismiss() }
                )
            }
            .scrollPosition(id: $visibleEntryID, anchor: .top)
            .scrollClipDisabled()
            .contentMargins(.top, topInset, for: .scrollContent)
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
            .onChange(of: selectedEntryID) { selection in
                guard let selection else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    scrollProxy.scrollTo(selection, anchor: .center)
                }
            }
            .onChange(of: filteredEntries.map(\.id)) { _ in
                synchronizeSelection()
            }
        }
    }

    /// Pick a color scheme based on what the user actually sees behind the
    /// labels — the wallpaper luminance attenuated by the dark tint that
    /// transparency controls. Threshold at 0.55 to bias toward dark mode
    /// (white labels) since that's the usual launchpad look. The hard flip
    /// is fine: transparency is dragged manually, not animated, so we don't
    /// care about hysteresis.
    private var preferredColorScheme: ColorScheme {
        let tintFactor = Double(preferences.launchpadOverlayTransparency)
        let effective = overlay.wallpaperLuminance * tintFactor
        return effective > 0.55 ? .light : .dark
    }

    private func paginate(_ entries: [LaunchpadEntry], pageSize: Int) -> [[LaunchpadEntry]] {
        guard !entries.isEmpty, pageSize > 0 else { return [[]] }
        return stride(from: 0, to: entries.count, by: pageSize).map { offset in
            Array(entries[offset..<min(offset + pageSize, entries.count)])
        }
    }

    private func pageIndex(for entryID: String, in pages: [[LaunchpadEntry]]) -> Int? {
        pages.firstIndex { page in page.contains { $0.id == entryID } }
    }

    /// Resolve the currently visible page from the scroll-position binding.
    /// `visiblePageID` is the `"page-N"` id assigned to each page above; nil
    /// before the user has scrolled (treated as page 0).
    private func currentPageIndex(in pages: [[LaunchpadEntry]]) -> Int {
        guard let visiblePageID,
              let parsed = Int(visiblePageID.dropFirst("page-".count)) else { return 0 }
        return min(max(parsed, 0), max(pages.count - 1, 0))
    }

    @ViewBuilder
    private func pageIndicator(
        pageCount: Int,
        currentIndex: Int,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        if pageCount > 1 {
            HStack(spacing: 10) {
                ForEach(0..<pageCount, id: \.self) { index in
                    // Visual dot stays 7pt but the click target is 22pt
                    // (via contentShape) so it's reachable with a mouse.
                    Circle()
                        .fill(.primary.opacity(index == currentIndex ? 0.85 : 0.3))
                        .frame(width: 7, height: 7)
                        .padding(8)
                        .contentShape(Circle())
                        .onTapGesture { onSelect(index) }
                        .animation(.easeInOut(duration: 0.18), value: currentIndex)
                }
            }
        }
    }

    @ViewBuilder
    private func pageNavigationChevrons(pageCount: Int, currentIndex: Int) -> some View {
        if pageCount > 1 {
            HStack {
                pageChevronButton(
                    direction: .previous,
                    isEnabled: currentIndex > 0
                ) {
                    scrollToPage(index: currentIndex - 1, pageCount: pageCount)
                }
                Spacer()
                pageChevronButton(
                    direction: .next,
                    isEnabled: currentIndex < pageCount - 1
                ) {
                    scrollToPage(index: currentIndex + 1, pageCount: pageCount)
                }
            }
            .padding(.horizontal, 24)
            .allowsHitTesting(true)
        }
    }

    /// Drives paging via the `scrollPosition` binding rather than via
    /// `ScrollViewReader.scrollTo` — the latter doesn't update the
    /// binding, so `currentPageIndex` would stay stale and the next
    /// chevron click would re-target the same page. Wrapped in
    /// `withAnimation` so the transition is smooth despite the
    /// `.scrollTargetBehavior(.paging)` snap.
    private func scrollToPage(index: Int, pageCount: Int) {
        let clamped = max(0, min(index, pageCount - 1))
        withAnimation(.easeInOut(duration: 0.22)) {
            visiblePageID = "page-\(clamped)"
        }
    }

    private enum LaunchpadPageChevronDirection {
        case previous, next

        var systemImage: String {
            switch self {
            case .previous: "chevron.left"
            case .next: "chevron.right"
            }
        }
    }

    @ViewBuilder
    private func pageChevronButton(
        direction: LaunchpadPageChevronDirection,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: direction.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary.opacity(isEnabled ? 0.85 : 0.2))
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }

    @ViewBuilder
    private func entryCell(for entry: LaunchpadEntry, cellSize: CGSize, iconSide: CGFloat) -> some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let layoutID = layoutItemID(for: entry)
        let isDragging = dragState?.layoutItemID == layoutID
        let isMergeTarget = dragState?.mergeTargetItemID == layoutID

        Group {
            switch entry {
            case .app(let app):
                Button {
                    launch(app)
                } label: {
                    LaunchpadAppCard(app: app, cellSize: cellSize, iconSide: iconSide)
                }
                .buttonStyle(.plain)
            case .folder(let folder):
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                        expandedFolderID = folderLayoutID(for: folder)
                    }
                } label: {
                    LaunchpadFolderCard(folder: folder, cellSize: cellSize, tileSide: iconSide)
                }
                .buttonStyle(.plain)
            }
        }
        // Translucent placeholder in the dragged item's slot while
        // the floating copy follows the cursor.
        .opacity(isDragging ? 0.18 : 1)
        // Subtle scale-up on the merge target to signal "drop here to
        // create / join a folder".
        .scaleEffect(isMergeTarget ? 1.08 : 1)
        .animation(.spring(duration: 0.22, bounce: 0.18), value: isMergeTarget)
        // Record the cell's frame so the drag handler can convert
        // cursor coords into an insertion index and detect which
        // cell the cursor is over.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LaunchpadCellFramePreference.self,
                    value: [layoutID: proxy.frame(in: .named(Self.launchpadGridCoordinateSpace))]
                )
            }
        )
        // `highPriorityGesture` instead of `simultaneousGesture`: when
        // the drag fires (finger moved more than `minimumDistance`),
        // it consumes the event and the Button's tap action does
        // *not* run, so dropping doesn't double as launching the app
        // or opening the folder. A pure tap with no movement leaves
        // the gesture inactive, so the Button still handles the
        // click → launch/open path.
        .highPriorityGesture(
            DragGesture(
                minimumDistance: 6,
                coordinateSpace: .named(Self.launchpadGridCoordinateSpace)
            )
            .onChanged { value in
                guard !isSearching else { return }
                handleDragChange(layoutID: layoutID, value: value)
            }
            .onEnded { value in
                guard !isSearching else { return }
                handleDragEnd(layoutID: layoutID, value: value)
            }
        )
        .contextMenu {
            if case .folder(let folder) = entry, !isSearching {
                folderContextMenu(for: folder)
            }
        }
    }

    private func layoutItemID(for entry: LaunchpadEntry) -> String {
        switch entry {
        case .app(let app): return "app:\(app.bundleIdentifier)"
        case .folder(let folder): return "folder:\(folderLayoutID(for: folder))"
        }
    }

    /// Strips the `virtual:` prefix injected by `resolveEntries` so we
    /// get back the raw folder UUID stored in the layout.
    private func folderLayoutID(for folder: AppFolderTile) -> String {
        if folder.identifier.hasPrefix("virtual:") {
            return String(folder.identifier.dropFirst("virtual:".count))
        }
        return folder.identifier
    }

    @ViewBuilder
    private func floatingDragPreview(for entry: LaunchpadEntry, cellSize: CGSize, iconSide: CGFloat) -> some View {
        switch entry {
        case .app(let app):
            LaunchpadAppCard(app: app, cellSize: cellSize, iconSide: iconSide)
        case .folder(let folder):
            LaunchpadFolderCard(folder: folder, cellSize: cellSize, tileSide: iconSide)
        }
    }

    // MARK: - Live drag handling

    /// Entries to render in the grid right now, with the dragged
    /// item moved into its preview target slot so siblings shift to
    /// make way during the drag.
    private var displayedEntries: [LaunchpadEntry] {
        guard let dragState else { return filteredEntries }
        var entries = filteredEntries
        guard let currentIndex = entries.firstIndex(where: { layoutItemID(for: $0) == dragState.layoutItemID }) else {
            return entries
        }
        let item = entries.remove(at: currentIndex)
        // After removing the dragged item, adjust the insertion index
        // so a "move past myself to the right" doesn't double-skip.
        let target = max(0, min(dragState.targetIndex, entries.count))
        let adjusted = currentIndex < target ? target - 1 : target
        let clamped = max(0, min(adjusted, entries.count))
        entries.insert(item, at: clamped)
        return entries
    }

    private func handleDragChange(layoutID: String, value: DragGesture.Value) {
        // First call of the drag — capture the origin.
        if dragState == nil {
            guard let originIndex = filteredEntries.firstIndex(where: { layoutItemID(for: $0) == layoutID }) else { return }
            dragState = LaunchpadDragState(
                layoutItemID: layoutID,
                originIndex: originIndex,
                targetIndex: originIndex,
                location: value.location,
                mergeTargetItemID: nil
            )
        }

        guard var state = dragState else { return }
        state.location = value.location
        let resolution = resolveDropTarget(at: value.location, draggedLayoutID: layoutID)

        // Cursor in the middle band of a target cell ⇒ merge mode:
        // freeze the live shift and highlight the target. Cursor in
        // the side bands or in a gap ⇒ live shift, no merge.
        if let candidate = resolution.mergeCandidateID, candidate != layoutID {
            state.mergeTargetItemID = candidate
            // Don't update targetIndex — keep displayedEntries frozen
            // so the target stays under the cursor.
        } else {
            state.mergeTargetItemID = nil
            state.targetIndex = resolution.insertionIndex
        }

        withAnimation(.spring(duration: 0.32, bounce: 0.18)) {
            dragState = state
        }
    }

    private func handleDragEnd(layoutID: String, value: DragGesture.Value) {
        defer {
            withAnimation(.spring(duration: 0.28, bounce: 0.2)) {
                dragState = nil
            }
        }
        guard let state = dragState, state.layoutItemID == layoutID else { return }

        let layoutService = LaunchpadLayoutService.shared

        // Merge path wins when active.
        if let mergeID = state.mergeTargetItemID {
            performMerge(draggedLayoutID: layoutID, targetLayoutID: mergeID)
            return
        }

        // Reorder path: place dragged at the previewed target index.
        if state.targetIndex != state.originIndex {
            layoutService.moveItem(id: layoutID, toIndex: state.targetIndex)
        }
    }

    private struct DropResolution {
        let insertionIndex: Int
        let mergeCandidateID: String?
    }

    /// Maps a cursor location to an insertion index and (when the
    /// cursor lies over a single cell's center) a merge candidate
    /// id. The merge candidate is whichever tile the cursor is
    /// directly over — the dwell timer decides whether the drop
    /// becomes a folder merge.
    private func resolveDropTarget(at location: CGPoint, draggedLayoutID: String) -> DropResolution {
        let entries = filteredEntries
        guard !entries.isEmpty else { return DropResolution(insertionIndex: 0, mergeCandidateID: nil) }

        // Find which cell the cursor is over (excluding the dragged
        // cell so it doesn't keep flagging itself as a merge candidate).
        let frames = cellFrames
        var directHit: (entryIndex: Int, frame: CGRect, id: String)?
        var nearestHit: (entryIndex: Int, frame: CGRect, id: String, distance: CGFloat)?

        for (entryIndex, entry) in entries.enumerated() {
            let id = layoutItemID(for: entry)
            guard id != draggedLayoutID, let frame = frames[id] else { continue }

            if frame.contains(location) {
                directHit = (entryIndex, frame, id)
                break
            }

            let dx = location.x - frame.midX
            let dy = location.y - frame.midY
            let distance = sqrt(dx * dx + dy * dy)
            if nearestHit == nil || distance < nearestHit!.distance {
                nearestHit = (entryIndex, frame, id, distance)
            }
        }

        let hit = directHit ?? nearestHit.map { (entryIndex: $0.entryIndex, frame: $0.frame, id: $0.id) }
        guard let hit else { return DropResolution(insertionIndex: entries.count, mergeCandidateID: nil) }

        // Center 60% of the cell width => merge candidate. The outer
        // 20% on each side stays as the reorder zone so users can
        // still insert tiles between neighbours.
        let centerBand = hit.frame.insetBy(dx: hit.frame.width * 0.20, dy: 0)
        let mergeID = (directHit != nil && centerBand.minX...centerBand.maxX ~= location.x) ? hit.id : nil

        // Insertion index: before this cell if cursor left of midX,
        // after otherwise. The caller adjusts for the dragged item's
        // own position when rendering the preview.
        let insertion = location.x < hit.frame.midX ? hit.entryIndex : hit.entryIndex + 1
        return DropResolution(insertionIndex: insertion, mergeCandidateID: mergeID)
    }

    private func performMerge(draggedLayoutID: String, targetLayoutID: String) {
        let layoutService = LaunchpadLayoutService.shared
        guard let draggedEntry = filteredEntries.first(where: { layoutItemID(for: $0) == draggedLayoutID }),
              case .app(let draggedApp) = draggedEntry else {
            return // Folders aren't merge sources.
        }
        guard let targetEntry = filteredEntries.first(where: { layoutItemID(for: $0) == targetLayoutID }) else { return }

        switch targetEntry {
        case .app(let targetApp):
            guard draggedApp.bundleIdentifier != targetApp.bundleIdentifier else { return }
            createFolder(merging: draggedApp.bundleIdentifier, withTarget: targetApp)
        case .folder(let targetFolder):
            layoutService.addApp(
                bundleID: draggedApp.bundleIdentifier,
                toFolderWithID: folderLayoutID(for: targetFolder)
            )
        }
    }

    private func createFolder(merging draggedBundleID: String, withTarget targetApp: AppTile) {
        let layoutService = LaunchpadLayoutService.shared
        let seedName = appFolderSeedName(for: appsForBundleIDs([targetApp.bundleIdentifier, draggedBundleID]))
        guard let folderID = layoutService.createFolder(
            merging: draggedBundleID,
            intoSlotOf: targetApp.bundleIdentifier,
            name: seedName
        ) else { return }
        // Hand off to AI naming on macOS 26+; fall back to seed name
        // (which the layout already holds).
        suggestFolderName(folderID: folderID, bundleIDs: [targetApp.bundleIdentifier, draggedBundleID])
    }

    private func appsForBundleIDs(_ bundleIDs: [String]) -> [AppTile] {
        var byID: [String: AppTile] = [:]
        for entry in overlay.entries {
            switch entry {
            case .app(let app): byID[app.bundleIdentifier] = app
            case .folder(let folder):
                for app in folder.apps { byID[app.bundleIdentifier] = app }
            }
        }
        return bundleIDs.compactMap { byID[$0] }
    }

    private func suggestFolderName(folderID: String, bundleIDs: [String]) {
        let apps = appsForBundleIDs(bundleIDs)
        guard apps.count >= 2 else { return }

        if #available(macOS 26.0, *) {
            Task { @MainActor in
                guard let suggestion = await AppFolderNamingService.shared.suggestInitialName(for: apps),
                      !suggestion.isEmpty else { return }
                LaunchpadLayoutService.shared.renameFolder(id: folderID, to: suggestion)
            }
        }
    }

    @ViewBuilder
    private func folderContextMenu(for folder: AppFolderTile) -> some View {
        let folderID = folderLayoutID(for: folder)
        Button("Rename…") {
            renamingFolderID = folderID
            renamingFolderDraft = folder.displayName
            isRenameFocused = true
        }
        Button("Ungroup", role: .destructive) {
            LaunchpadLayoutService.shared.ungroupFolder(id: folderID)
        }
    }

    @ViewBuilder
    private func folderRenameOverlay(folderID: String) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissRename(save: false) }

            VStack(alignment: .leading, spacing: 12) {
                Text("Rename Folder")
                    .font(.title3.weight(.semibold))
                TextField("Name", text: $renamingFolderDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 17))
                    .focused($isRenameFocused)
                    .onSubmit { dismissRename(save: true) }
                HStack {
                    Spacer()
                    Button("Cancel") { dismissRename(save: false) }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { dismissRename(save: true) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(renamingFolderDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 340)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            }
        }
    }

    private func dismissRename(save: Bool) {
        if save, let renamingFolderID {
            LaunchpadLayoutService.shared.renameFolder(id: renamingFolderID, to: renamingFolderDraft)
        }
        renamingFolderID = nil
        renamingFolderDraft = ""
        isRenameFocused = false
        isSearchFocused = true
    }

    private func dismissExpandedFolder() {
        // Drop rename state alongside the folder so the next expand
        // starts in display mode with no stale draft.
        isRenamingExpandedFolder = false
        expandedFolderRenameDraft = ""
        withAnimation(.easeInOut(duration: 0.22)) {
            expandedFolderID = nil
        }
    }

    private func commitExpandedFolderRename() {
        guard isRenamingExpandedFolder, let expandedFolderID else {
            isRenamingExpandedFolder = false
            return
        }
        let trimmed = expandedFolderRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            LaunchpadLayoutService.shared.renameFolder(id: expandedFolderID, to: trimmed)
        }
        isRenamingExpandedFolder = false
        expandedFolderRenameDraft = ""
    }

    private func cancelExpandedFolderRename() {
        isRenamingExpandedFolder = false
        expandedFolderRenameDraft = ""
    }

    /// Derives the currently-expanded folder from the live entries so
    /// drag/drop mutations (pop out, add) reflect in the expanded view
    /// without a stale snapshot. The folder auto-dismisses when its
    /// member count drops below two (the layout collapses singletons
    /// back to plain apps).
    private var expandedFolder: AppFolderTile? {
        guard let expandedFolderID else { return nil }
        for entry in overlay.entries {
            if case .folder(let folder) = entry,
               folderLayoutID(for: folder) == expandedFolderID {
                return folder
            }
        }
        return nil
    }

    private var filteredEntries: [LaunchpadEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return overlay.entries }

        return overlay.entries
            .compactMap { entry -> (entry: LaunchpadEntry, score: Int)? in
                let score = matchScore(for: entry, query: query)
                guard score != Int.max else { return nil }
                return (entry, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score < rhs.score
                }

                return lhs.entry.displayName.localizedCaseInsensitiveCompare(rhs.entry.displayName) == .orderedAscending
            }
            .map(\.entry)
    }

    private func matchScore(for entry: LaunchpadEntry, query: String) -> Int {
        let loweredQuery = query.lowercased()
        let displayName = entry.displayName.lowercased()
        let bundleIdentifier = entry.matchableBundleIdentifier.lowercased()

        if displayName == loweredQuery {
            return 0
        }

        if displayName.hasPrefix(loweredQuery) {
            return 1
        }

        if let range = displayName.range(of: loweredQuery) {
            return 10 + displayName.distance(from: displayName.startIndex, to: range.lowerBound)
        }

        if !bundleIdentifier.isEmpty {
            if bundleIdentifier == loweredQuery {
                return 100
            }

            if bundleIdentifier.hasPrefix(loweredQuery) {
                return 101
            }

            if let range = bundleIdentifier.range(of: loweredQuery) {
                return 110 + bundleIdentifier.distance(from: bundleIdentifier.startIndex, to: range.lowerBound)
            }
        }

        return Int.max
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.primary.opacity(0.7))

            TextField("Search Applications", text: $searchText)
                .textFieldStyle(.plain)
                .font(.headline.weight(.regular))
                .foregroundStyle(.primary.opacity(0.95))
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.primary.opacity(0.45), .primary.opacity(0.2))
                }
                .buttonStyle(.plain)
            }

            Button {
                LaunchpadInspectorService.shared.toggle()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Launchpad Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .dockyGlass(in: Capsule())
    }

    private func handleKeyDown(_ event: NSEvent, columnCount: Int, rowCount: Int) -> Bool {
        // The overlay's hosting view stays alive for the app's lifetime, so this
        // local monitor keeps firing while the overlay is hidden. Without the
        // guard, Enter while Docky is frontmost for any other reason (NSAlert,
        // settings, permissions, Cmd-Tab back) launches the first launchpad app.
        guard overlay.isPresented, event.type == .keyDown else { return false }

        // Renaming the expanded folder's title intercepts a small set of
        // keys (commit / cancel) and lets everything else fall through to
        // the TextField's field editor.
        if isRenamingExpandedFolder {
            switch event.keyCode {
            case 53:
                cancelExpandedFolderRename()
                return true
            case 36, 76:
                commitExpandedFolderRename()
                return true
            default:
                return false
            }
        }

        // Same deal for the right-click "Rename…" modal: while it's up,
        // only Enter / Esc are ours (commit / cancel); arrows and
        // editing keys belong to the field editor.
        if renamingFolderID != nil {
            switch event.keyCode {
            case 53:
                dismissRename(save: false)
                return true
            case 36, 76:
                let trimmed = renamingFolderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    dismissRename(save: true)
                }
                return true
            default:
                return false
            }
        }

        switch event.keyCode {
        case 53:
            // Esc closes the expanded folder first; only when nothing is
            // expanded does it dismiss the launchpad as a whole.
            if expandedFolder != nil {
                dismissExpandedFolder()
            } else {
                overlay.dismiss()
            }
            return true
        case 36, 76:
            // While a folder is expanded the user is interacting with the
            // expanded card; let its own button taps drive launches.
            guard expandedFolder == nil else { return false }
            guard case .app(let app) = selectedEntry else { return false }
            launch(app)
            return true
        case 123:
            moveSelection(delta: -1)
            return true
        case 124:
            moveSelection(delta: 1)
            return true
        case 125:
            moveSelection(delta: columnCount)
            return true
        case 126:
            moveSelection(delta: -columnCount)
            return true
        case 116:
            // Page Up — jump by one screenful of rows. `rowCount` is
            // the on-screen page rows for both modes; in vertical it
            // approximates a "screenful" jump.
            moveSelection(delta: -columnCount * max(1, rowCount))
            return true
        case 121:
            // Page Down — symmetric with Page Up.
            moveSelection(delta: columnCount * max(1, rowCount))
            return true
        case 115:
            // Home — first entry.
            moveSelection(toAbsoluteIndex: 0)
            return true
        case 119:
            // End — last entry.
            moveSelection(toAbsoluteIndex: Int.max)
            return true
        default:
            return false
        }
    }

    private var selectedEntry: LaunchpadEntry? {
        guard let selectedEntryID else {
            return filteredEntries.first
        }

        return filteredEntries.first { $0.id == selectedEntryID } ?? filteredEntries.first
    }

    private func synchronizeSelection() {
        selectedEntryID = selectedEntry?.id
    }

    private func moveSelection(delta: Int) {
        guard !filteredEntries.isEmpty else { return }

        let currentIndex = filteredEntries.firstIndex { $0.id == selectedEntryID } ?? 0
        let newIndex = min(max(currentIndex + delta, 0), filteredEntries.count - 1)
        selectedEntryID = filteredEntries[newIndex].id
        isSearchFocused = true
    }

    /// Like `moveSelection(delta:)` but jumps to an absolute index in
    /// the visible list. Clamped to the valid range; pass `0` for
    /// Home and `Int.max` for End.
    private func moveSelection(toAbsoluteIndex index: Int) {
        guard !filteredEntries.isEmpty else { return }

        let clamped = min(max(index, 0), filteredEntries.count - 1)
        selectedEntryID = filteredEntries[clamped].id
        isSearchFocused = true
    }

    private func launch(_ app: AppTile) {
        overlay.dismiss()
        WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
    }
}

private struct LaunchpadAppCard: View {
    let app: AppTile
    let cellSize: CGSize
    /// Rendered icon edge. Decoupled from `cellSize.width` so square cells
    /// can be larger than the icon (extra width becomes horizontal padding
    /// around the icon).
    let iconSide: CGFloat
    @Bindable private var preferences = DockyPreferences.shared

    var body: some View {
        VStack(spacing: cellSpacing) {
            AsyncAppIcon(
                bundleIdentifier: app.bundleIdentifier,
                overrideURL: preferences.effectiveAppIconOverrideURL(forBundleIdentifier: app.bundleIdentifier),
                side: iconSide,
                padding: overridePadding
            )

            Text(app.displayName)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.95))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .frame(width: cellSize.width, height: cellSize.height, alignment: .top)
        .contentShape(Rectangle())
    }

    private var cellSpacing: CGFloat {
        cellSize.height * 0.04
    }

    /// Optional per-icon padding applied around override icons (only when
    /// the user has set a custom icon for this app).
    private var overridePadding: CGFloat {
        guard preferences.effectiveAppIconOverrideURL(forBundleIdentifier: app.bundleIdentifier) != nil else {
            return 0
        }
        return preferences.appIconOverridePadding(forBundleIdentifier: app.bundleIdentifier) * iconSide
    }
}

/// Renders an app icon without blocking the main thread on the first
/// LaunchServices hit. Cached icons render synchronously (a normal
/// `Image(nsImage:)`); cold icons show a neutral placeholder while a
/// detached task warms the cache, then swap in with a short fade.
private struct AsyncAppIcon: View {
    let bundleIdentifier: String
    let overrideURL: URL?
    let side: CGFloat
    let padding: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
                    .padding(padding)
            } else {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(.primary.opacity(0.06))
                    .frame(width: side, height: side)
                    .padding(padding)
            }
        }
        .task(id: cacheKey) {
            await loadIcon()
        }
        .animation(.easeOut(duration: 0.12), value: image)
    }

    private var cacheKey: String {
        "\(bundleIdentifier)|\(overrideURL?.path ?? "")"
    }

    private func loadIcon() async {
        if let overrideURL,
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            image = overrideImage
            return
        }
        if let cached = IconCacheService.shared.cachedIcon(forBundleIdentifier: bundleIdentifier) {
            image = cached
            return
        }
        let loaded = await IconCacheService.shared.loadIconAsync(forBundleIdentifier: bundleIdentifier)
        image = loaded
    }
}

/// Launchpad folder preview. Visually matches the dock folder tile (glass
/// container, white-10% rounded-rect border, dock-tile corner radius), but
/// shows up to a 3×3 grid of member icons rather than the dock's 2×2 — the
/// launchpad has more room and we want the preview to read more like the
/// folder's full contents.
private struct LaunchpadFolderCard: View {
    let folder: AppFolderTile
    let cellSize: CGSize
    /// Matches `LaunchpadAppCard.iconSide` so folder tiles render the same
    /// drawn size as app tiles in the launchpad grid, regardless of how
    /// much horizontal padding the square cell adds.
    let tileSide: CGFloat
    @Bindable private var preferences = DockyPreferences.shared

    private static let gridDimension = 3

    var body: some View {
        VStack(spacing: cellSpacing) {
            folderGrid
                .frame(width: tileSide, height: tileSide)

            Text(folder.displayName)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.95))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .frame(width: cellSize.width, height: cellSize.height, alignment: .top)
        .contentShape(Rectangle())
    }

    private var cellSpacing: CGFloat {
        cellSize.height * 0.04
    }

    private var folderGrid: some View {
        // Reuse the dock's tile chrome math so a launchpad folder reads in
        // the same proportions as a dock folder: outer chrome inset is
        // `floor(tileSide * 3 / 32)`, corner radius is `tileSide * 0.225`,
        // and the icons inside the glass container sit at the dock's 12%
        // inner padding with a 6% gap (relative to the inner container).
        let chromeInset = floor(tileSide * 3 / 32)
        let cornerRadius = tileSide * 0.225
        let containerSide = max(0, tileSide - chromeInset * 2)
        let innerPadding = containerSide * 0.12
        let gap = containerSide * 0.06
        let displayedApps = Array(folder.apps.prefix(Self.gridDimension * Self.gridDimension))
        let cellSide = max(
            0,
            (containerSide - innerPadding * 2 - gap * CGFloat(Self.gridDimension - 1)) / CGFloat(Self.gridDimension)
        )
        let columns = Array(
            repeating: GridItem(.fixed(cellSide), spacing: gap, alignment: .top),
            count: Self.gridDimension
        )

        return ZStack {
            Color.clear
                .dockyGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .dockyGlassBorder(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            // LazyVGrid fills row-major from top-leading and stops at the
            // last app, so partially filled grids leave the trailing rows
            // empty rather than rendering placeholder dots — matches the
            // macOS Launchpad folder preview look.
            LazyVGrid(columns: columns, alignment: .leading, spacing: gap) {
                ForEach(displayedApps, id: \.bundleIdentifier) { app in
                    AsyncAppIcon(
                        bundleIdentifier: app.bundleIdentifier,
                        overrideURL: preferences.effectiveAppIconOverrideURL(forBundleIdentifier: app.bundleIdentifier),
                        side: cellSide,
                        padding: overrideIconPadding(for: app.bundleIdentifier, side: cellSide)
                    )
                }
            }
            .padding(innerPadding)
            .frame(width: containerSide, height: containerSide, alignment: .topLeading)
        }
        .padding(chromeInset)
        .frame(width: tileSide, height: tileSide)
    }

    private func overrideIconPadding(for bundleIdentifier: String, side: CGFloat) -> CGFloat {
        guard preferences.effectiveAppIconOverrideURL(forBundleIdentifier: bundleIdentifier) != nil else {
            return 0
        }
        return preferences.appIconOverridePadding(forBundleIdentifier: bundleIdentifier) * side
    }

    private func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        if let overrideURL = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: bundleIdentifier),
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }
        return IconCacheService.shared.icon(forBundleIdentifier: bundleIdentifier)
    }
}

/// Expanded folder card shown when the user opens a folder on the launchpad.
/// Reuses the launchpad's grid+pagination idea inside a glass card. The
/// outer ZStack catches taps for outside-of-card dismiss, so clicking the
/// blurred backdrop closes the folder without dismissing the launchpad.
private struct ExpandedFolderOverlay: View {
    let folder: AppFolderTile
    /// Layout-level folder ID (the raw UUID without the `virtual:`
    /// prefix). Used to tag drag payloads originating from inside
    /// this folder so the launchpad backdrop can pop them out.
    let folderLayoutID: String
    /// Cell size of the launchpad grid the user expanded from. Used to
    /// derive the same `tileSide * 0.225` corner radius the folder icon
    /// uses, so the rounding is visually continuous through the expand
    /// animation.
    let sourceCellSize: CGSize
    /// Drawn icon edge in the source launchpad grid. The expanded folder
    /// renders its app cards at the same icon size for visual continuity.
    let sourceIconSide: CGFloat
    /// Same column/row count as the underlying launchpad page so the
    /// expanded folder reads as a 1:1 mini-launchpad. Cell size scales
    /// down to fit because the card is only `(1 - 2 * edgePaddingFraction)`
    /// of the screen.
    let columnsPerPage: Int
    let rowsPerPage: Int
    /// Inline title rename state, lifted to the parent so Enter / Esc
    /// can be routed via the launchpad-wide key monitor before SwiftUI
    /// sees them.
    @Binding var isRenaming: Bool
    @Binding var renameDraft: String
    let onLaunch: (AppTile) -> Void
    let onDismiss: () -> Void
    /// Invoked when the user commits the rename (Enter or focus loss).
    /// Parent applies the change to `LaunchpadLayoutService` and clears
    /// `isRenaming`.
    let onCommitRename: () -> Void

    @State private var visiblePageID: String?
    @FocusState private var isRenameFieldFocused: Bool

    private let titleSpacing: CGFloat = 20
    private let indicatorAreaHeight: CGFloat = 32
    /// Tight gaps inside the card so icons can grow into the freed space.
    /// Inset/spacing values are roughly a third of the launchpad's outer
    /// grid; cells end up ~25% larger than the launchpad cells at the same
    /// 10% horizontal padding.
    private let cardHorizontalInset: CGFloat = 8
    private let cardVerticalInset: CGFloat = 32
    private let cardColumnSpacing: CGFloat = 8
    private let cardRowSpacing: CGFloat = 8
    /// 10% of the screen on each side so the card has breathing room
    /// without crowding the icons.
    private let horizontalPaddingFraction: CGFloat = 0.10

    private var pageSize: Int { columnsPerPage * rowsPerPage }

    var body: some View {
        GeometryReader { proxy in
            // Cells in the expanded folder are exactly the same size as
            // the launchpad cells behind it, so icons render at the same
            // resolution. The card grows to fit `columnsPerPage` cells
            // horizontally; vertically it hugs the rows actually used.
            let cellSize = sourceCellSize
            let pages = paginate(folder.apps, pageSize: pageSize)
            let maxAppsOnAnyPage = pages.map(\.count).max() ?? 0
            let usedRows = max(1, Int(ceil(Double(maxAppsOnAnyPage) / Double(max(columnsPerPage, 1)))))
            let needsIndicator = pages.count > 1
            let gridContentWidth = CGFloat(columnsPerPage) * cellSize.width
                + CGFloat(max(0, columnsPerPage - 1)) * cardColumnSpacing
            let gridContentHeight = CGFloat(usedRows) * cellSize.height
                + CGFloat(max(0, usedRows - 1)) * cardRowSpacing
            let indicatorReservedHeight: CGFloat = needsIndicator ? indicatorAreaHeight : 0
            let cardWidth = min(
                proxy.size.width,
                gridContentWidth + cardHorizontalInset * 2
            )
            let cardHeight = min(
                proxy.size.height,
                gridContentHeight + indicatorReservedHeight + cardVerticalInset * 2
            )
            let gridHeight = max(0, cardHeight - indicatorReservedHeight - cardVerticalInset * 2)
            // Same formula as `LaunchpadFolderCard.tileSide` → cornerRadius
            // is `tileSide * 0.225`, identical to the folder icon's.
            let folderTileSide = min(min(sourceCellSize.width, sourceCellSize.height) * 0.7, 160)
            let cornerRadius = folderTileSide * 0.225

            ZStack {
                // Full-size ultra-thin material backdrop blurs the
                // launchpad behind the expanded folder so the card has
                // visual breathing room. Doubles as the tap-to-dismiss
                // target — buttons inside the card consume their own
                // taps so launches still go through.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: titleSpacing) {
                    titleView(width: cardWidth)

                    folderCard(
                        width: cardWidth,
                        height: cardHeight,
                        cornerRadius: cornerRadius,
                        cellSize: cellSize,
                        gridHeight: gridHeight,
                        pages: pages
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
        }
    }

    /// Folder title that flips to an inline `TextField` on double-click.
    /// Enter commits via `onCommitRename`; Esc cancels via the parent
    /// view's key monitor (which flips `isRenaming` back off).
    @ViewBuilder
    private func titleView(width: CGFloat) -> some View {
        if isRenaming {
            TextField("Folder name", text: $renameDraft)
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .focused($isRenameFieldFocused)
                .frame(width: width)
                .onSubmit { onCommitRename() }
                .onAppear {
                    isRenameFieldFocused = true
                }
                .onChange(of: isRenaming) { _, nowRenaming in
                    isRenameFieldFocused = nowRenaming
                }
        } else {
            Text(folder.displayName)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(width: width)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    renameDraft = folder.displayName
                    isRenaming = true
                }
        }
    }

    private func folderCard(
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        cellSize: CGSize,
        gridHeight: CGFloat,
        pages: [[AppTile]]
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageGrid(apps: pages[index], cellSize: cellSize, pageWidth: width)
                            .id("folder-page-\(index)")
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visiblePageID, anchor: .leading)
            .scrollClipDisabled()
            .frame(height: gridHeight)

            // Only reserve indicator height when the folder actually
            // paginates; otherwise it eats vertical space and pads the
            // card past its content.
            if pages.count > 1 {
                pageIndicator(pageCount: pages.count)
                    .frame(height: indicatorAreaHeight)
            }
        }
        .padding(.vertical, cardVerticalInset)
        .frame(width: width, height: height)
        .background(Color.primary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
    }

    private func pageGrid(apps: [AppTile], cellSize: CGSize, pageWidth: CGFloat) -> some View {
        let gridColumns = Array(
            repeating: GridItem(.fixed(cellSize.width), spacing: cardColumnSpacing, alignment: .top),
            count: columnsPerPage
        )

        // Mirror the launchpad's pageGrid centering: spacers on either side
        // eat leftover width equally so the grid sits centered in the
        // card rather than pinned to the leading edge.
        return HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: cardHorizontalInset)

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: cardRowSpacing) {
                ForEach(apps, id: \.bundleIdentifier) { app in
                    Button {
                        onLaunch(app)
                    } label: {
                        LaunchpadAppCard(app: app, cellSize: cellSize, iconSide: sourceIconSide)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove from Folder", role: .destructive) {
                            LaunchpadLayoutService.shared.removeFromFolder(bundleID: app.bundleIdentifier)
                        }
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: cardHorizontalInset)
        }
        .frame(width: pageWidth, alignment: .top)
    }

    private func paginate(_ apps: [AppTile], pageSize: Int) -> [[AppTile]] {
        guard !apps.isEmpty, pageSize > 0 else { return [[]] }
        return stride(from: 0, to: apps.count, by: pageSize).map { offset in
            Array(apps[offset..<min(offset + pageSize, apps.count)])
        }
    }

    @ViewBuilder
    private func pageIndicator(pageCount: Int) -> some View {
        if pageCount > 1 {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(.primary.opacity(index == currentPageIndex ? 0.85 : 0.3))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.18), value: currentPageIndex)
                }
            }
        }
    }

    private var currentPageIndex: Int {
        guard let visiblePageID,
              let parsed = Int(visiblePageID.dropFirst("folder-page-".count)) else { return 0 }
        return max(parsed, 0)
    }
}

private struct LaunchpadOverlayKeyMonitor: NSViewRepresentable {
    let keyDownHandler: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(keyDownHandler: keyDownHandler)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.keyDownHandler = keyDownHandler
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var keyDownHandler: (NSEvent) -> Bool
        private var eventMonitor: Any?

        init(keyDownHandler: @escaping (NSEvent) -> Bool) {
            self.keyDownHandler = keyDownHandler
        }

        func start() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.keyDownHandler(event) ? nil : event
            }
        }

        func stop() {
            guard let eventMonitor else { return }
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

