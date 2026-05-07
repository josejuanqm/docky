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
        preferences.$windowSpaceBehavior
            .receive(on: DispatchQueue.main)
            .sink { [weak self] behavior in
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

private struct LaunchpadOverlayView: View {
    @ObservedObject private var overlay = LaunchpadOverlayService.shared
    @ObservedObject private var preferences = DockyPreferences.shared
    @State private var searchText = ""
    @State private var selectedEntryID: String?
    @State private var visiblePageID: String?
    @State private var expandedFolder: AppFolderTile?
    @FocusState private var isSearchFocused: Bool

    private let searchBarWidth: CGFloat = 350
    private let searchBarTopInset: CGFloat = 56
    private let searchBarHeight: CGFloat = 56
    private let columnSpacing: CGFloat = 48
    private let rowSpacing: CGFloat = 32
    private let horizontalInset: CGFloat = 80
    private let bottomInset: CGFloat = 56
    private let wallpaperBlurRadius: CGFloat = 50
    /// Reference logical screen height the launchpad metrics are tuned
    /// for (1440p): at this height, icons render at exactly `baseIconSize`
    /// and gaps at the configured `columnSpacing` / `rowSpacing` values.
    /// Taller or shorter screens scale linearly off this baseline.
    private let referenceScreenHeight: CGFloat = 1440
    /// Icon edge length at the reference screen height. Icons at other
    /// heights are `baseIconSize × (screenHeight / referenceScreenHeight)`.
    private let baseIconSize: CGFloat = 128
    /// Reference label height below the icon, scaled with the icon.
    private let baseLabelHeight: CGFloat = 22

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        GeometryReader { proxy in
            let topInset = searchBarTopInset + searchBarHeight + 56
            // Linear scale off the 1440p reference (screen *height*).
            // Clamped so very small or very large displays don't blow up
            // the cell math.
            let scale = max(0.5, min(2.5, proxy.size.height / referenceScreenHeight))
            let iconSize = baseIconSize * scale
            let labelHeight = baseLabelHeight * scale
            let cellSpacing = iconSize * 0.04
            let scaledColumnSpacing = columnSpacing * scale
            let scaledRowSpacing = rowSpacing * scale
            let scaledHorizontalInset = horizontalInset * scale
            let cellWidth = iconSize
            let cellHeight = iconSize + labelHeight + cellSpacing
            let usableWidth = max(0, proxy.size.width - scaledHorizontalInset * 2)
            let usableHeight = max(0, proxy.size.height - topInset - bottomInset)
            // Columns from the user preference, but clamped so the row
            // doesn't overflow the screen on narrow displays.
            let configuredColumns = max(1, preferences.launchpadGridColumnCount)
            let configuredRows = max(1, preferences.launchpadGridRowCount)
            let maxColumnsThatFit = max(1, Int((usableWidth + scaledColumnSpacing) / (cellWidth + scaledColumnSpacing)))
            let maxRowsThatFit = max(1, Int((usableHeight + scaledRowSpacing) / (cellHeight + scaledRowSpacing)))
            let pageColumns = max(1, min(configuredColumns, maxColumnsThatFit))
            // Honor the configured row count, but never exceed what fits
            // on screen — otherwise rows would overflow the page.
            let pageRows = max(1, min(configuredRows, maxRowsThatFit))
            let pageSize = pageColumns * pageRows
            let pages = paginate(filteredEntries, pageSize: pageSize)

            ZStack {
                wallpaperBackground(in: proxy.size)

                Color.black
                    .opacity(1 - preferences.launchpadOverlayTransparency)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        overlay.dismiss()
                    }

                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(pages.indices, id: \.self) { pageIndex in
                                pageGrid(
                                    pageEntries: pages[pageIndex],
                                    cellWidth: cellWidth,
                                    cellHeight: cellHeight,
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
                    .padding(.bottom, bottomInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: selectedEntryID) { _, selection in
                        guard let selection,
                              let pageIndex = pageIndex(for: selection, in: pages) else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            scrollProxy.scrollTo("page-\(pageIndex)", anchor: .leading)
                        }
                    }
                    .onChange(of: filteredEntries.map(\.id)) { _, _ in
                        synchronizeSelection()
                    }
                }

                VStack {
                    searchField
                        .frame(width: searchBarWidth)
                        .padding(.top, searchBarTopInset)

                    Spacer()

                    pageIndicator(pageCount: pages.count, currentIndex: currentPageIndex(in: pages))
                        .padding(.bottom, 24)
                }

                if let folder = expandedFolder {
                    ExpandedFolderOverlay(
                        folder: folder,
                        sourceCellSize: CGSize(width: cellWidth, height: cellHeight),
                        columnsPerPage: pageColumns,
                        rowsPerPage: pageRows,
                        onLaunch: { app in
                            launch(app)
                        },
                        onDismiss: {
                            dismissExpandedFolder()
                        }
                    )
                    // Scale 1.3 → 1.0 with a fade gives the "falling on top"
                    // feel the user asked for. Symmetric so dismiss reverses
                    // it: scale 1.0 → 1.3 with a fade out.
                    .transition(.scale(scale: 1.3).combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .ignoresSafeArea()
            .environment(\.colorScheme, preferredColorScheme)
            .onExitCommand {
                if expandedFolder != nil {
                    dismissExpandedFolder()
                } else {
                    overlay.dismiss()
                }
            }
            .background {
                LaunchpadOverlayKeyMonitor { event in
                    handleKeyDown(event, columnCount: pageColumns)
                }
            }
            .onAppear {
                isSearchFocused = true
                synchronizeSelection()
            }
            .onChange(of: overlay.isPresented) { _, isPresented in
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
                        cellSize: CGSize(width: cellWidth, height: cellHeight)
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
    private func pageIndicator(pageCount: Int, currentIndex: Int) -> some View {
        if pageCount > 1 {
            HStack(spacing: 10) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(.primary.opacity(index == currentIndex ? 0.85 : 0.3))
                        .frame(width: 7, height: 7)
                        .animation(.easeInOut(duration: 0.18), value: currentIndex)
                }
            }
        }
    }

    @ViewBuilder
    private func entryCell(for entry: LaunchpadEntry, cellSize: CGSize) -> some View {
        switch entry {
        case .app(let app):
            Button {
                launch(app)
            } label: {
                LaunchpadAppCard(app: app, cellSize: cellSize)
            }
            .buttonStyle(.plain)
        case .folder(let folder):
            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                    expandedFolder = folder
                }
            } label: {
                LaunchpadFolderCard(folder: folder, cellSize: cellSize)
            }
            .buttonStyle(.plain)
        }
    }

    private func dismissExpandedFolder() {
        withAnimation(.easeInOut(duration: 0.22)) {
            expandedFolder = nil
        }
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
                .font(.system(size: 20, weight: .medium))
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.clear, in: .capsule)
    }

    private func handleKeyDown(_ event: NSEvent, columnCount: Int) -> Bool {
        guard event.type == .keyDown else { return false }

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

    private func launch(_ app: AppTile) {
        overlay.dismiss()
        WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
    }
}

private struct LaunchpadAppCard: View {
    let app: AppTile
    let cellSize: CGSize
    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        VStack(spacing: cellSpacing) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSide, height: iconSide)
                .padding(overridePadding)

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

    /// Icon fills the cell horizontally. The body sizes the cell so its
    /// width equals the launchpad's scaled icon size (128 px at the 1440p
    /// reference, scaled linearly elsewhere), so this also drives the
    /// rendered icon size.
    private var iconSide: CGFloat { cellSize.width }

    /// Optional per-icon padding applied around override icons (only when
    /// the user has set a custom icon for this app).
    private var overridePadding: CGFloat {
        guard preferences.effectiveAppIconOverrideURL(forBundleIdentifier: app.bundleIdentifier) != nil else {
            return 0
        }
        return preferences.appIconOverridePadding(forBundleIdentifier: app.bundleIdentifier) * iconSide
    }

    private var icon: NSImage {
        if let overrideURL = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: app.bundleIdentifier),
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return IconCacheService.shared.icon(forBundleIdentifier: app.bundleIdentifier)
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
    @ObservedObject private var preferences = DockyPreferences.shared

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
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))

            // LazyVGrid fills row-major from top-leading and stops at the
            // last app, so partially filled grids leave the trailing rows
            // empty rather than rendering placeholder dots — matches the
            // macOS Launchpad folder preview look.
            LazyVGrid(columns: columns, alignment: .leading, spacing: gap) {
                ForEach(displayedApps, id: \.bundleIdentifier) { app in
                    Image(nsImage: icon(forBundleIdentifier: app.bundleIdentifier))
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: cellSide, height: cellSide)
                        .padding(overrideIconPadding(for: app.bundleIdentifier, side: cellSide))
                }
            }
            .padding(innerPadding)
            .frame(width: containerSide, height: containerSide, alignment: .topLeading)
        }
        .padding(chromeInset)
        .frame(width: tileSide, height: tileSide)
    }

    /// Matches `LaunchpadAppCard.iconSide` so folder tiles render the same
    /// size as app tiles in the launchpad grid.
    private var tileSide: CGFloat { cellSize.width }

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
    /// Cell size of the launchpad grid the user expanded from. Used to
    /// derive the same `tileSide * 0.225` corner radius the folder icon
    /// uses, so the rounding is visually continuous through the expand
    /// animation.
    let sourceCellSize: CGSize
    /// Same column/row count as the underlying launchpad page so the
    /// expanded folder reads as a 1:1 mini-launchpad. Cell size scales
    /// down to fit because the card is only `(1 - 2 * edgePaddingFraction)`
    /// of the screen.
    let columnsPerPage: Int
    let rowsPerPage: Int
    let onLaunch: (AppTile) -> Void
    let onDismiss: () -> Void

    @State private var visiblePageID: String?

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
                    Text(folder.displayName)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(width: cardWidth)

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
                        LaunchpadAppCard(app: app, cellSize: cellSize)
                    }
                    .buttonStyle(.plain)
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
