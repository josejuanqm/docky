//
//  AppFolderTileView.swift
//  Docky
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct AppFolderTileView: View {
    let tile: AppFolderTile
    let cornerRadius: CGFloat
    let suppressesGroupedOpenedBackdrop: Bool
    private let dockSettings = DockSettingsService.shared
    @ObservedObject private var layout = DockLayoutService.shared
    @Bindable private var preferences = DockyPreferences.shared
    @ObservedObject private var store = TileStore.shared
    @ObservedObject private var workspace = WorkspaceService.shared
    @ObservedObject private var dockBadges = DockBadgeService.shared

    init(
        tile: AppFolderTile,
        cornerRadius: CGFloat,
        suppressesGroupedOpenedBackdrop: Bool = false
    ) {
        self.tile = tile
        self.cornerRadius = cornerRadius
        self.suppressesGroupedOpenedBackdrop = suppressesGroupedOpenedBackdrop
        self._layout = ObservedObject(wrappedValue: DockLayoutService.shared)
        self._preferences = Bindable(wrappedValue: DockyPreferences.shared)
        self._store = ObservedObject(wrappedValue: TileStore.shared)
        self._workspace = ObservedObject(wrappedValue: WorkspaceService.shared)
        self._dockBadges = ObservedObject(wrappedValue: DockBadgeService.shared)
    }

    var openedAppCount: Int {
        guard !suppressesGroupedOpenedBackdrop else {
            return 0
        }

        if tile.contentViewMode == .inline {
            return store.isInlineAppFolderExpanded(folderID: tile.identifier) ? tile.apps.count : 0
        }

        guard preferences.showsGroupedOpenedAppsInDock else {
            return 0
        }

        return tile.apps.count { app in
            workspace.isRunning(bundleIdentifier: app.bundleIdentifier)
        }
    }

    private var groupedOpenedAppSpan: Int {
        max(openedAppCount, 0) + 1
    }

    private var tileSize: CGFloat {
        layout.scaled(dockSettings.displayTileSize)
    }

    private var position: ResolvedDockWindowPosition {
        preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
    }

    private var groupedOpenedBackdropExtent: CGFloat {
        (CGFloat(groupedOpenedAppSpan) * tileSize) - 4
    }

    private var groupedOpenedBackdropOffset: CGFloat {
        (groupedOpenedBackdropExtent / 2) - (tileSize / 2) - 2
    }

    private var groupedOpenedBackdropHorizontalXOffset: CGFloat {
        groupedOpenedBackdropOffset + (position == .bottom ? 3 : 0)
    }

    private func groupedOpenedBackdropCrossAxisExtent(in size: CGSize) -> CGFloat? {
        guard position.isVertical else {
            return nil
        }

        return size.width + 8
    }

    private var groupedOpenedBackdropVerticalYOffset: CGFloat {
        position.isVertical ? 3 : 0
    }

    private var isInlineExpanded: Bool {
        tile.contentViewMode == .inline && store.isInlineAppFolderExpanded(folderID: tile.identifier)
    }

    private var inlineExpandedChevronName: String {
        switch position {
        case .left, .right, .top:
            "chevron.up"
        case .bottom:
            "chevron.left"
        }
    }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var showsBackdrop: Bool {
        // Magnification reshapes the tile group every frame; the backdrop
        // sized against rest geometry would visibly lag behind, so hide
        // it when the user has magnification turned on.
        guard !dockSettings.magnification else { return false }
        return openedAppCount > 0 && preferences.showsGroupedOpenedAppsBackdrop
    }

    @ViewBuilder
    private var content: some View {
        GeometryReader { geo in
            displayContent(in: geo.size)
                .background(
                    Color.primary.opacity(showsBackdrop ? 0.2 : 0)
                        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
                        .padding(.top, position.isVertical ? 0 : -4)
                        .padding(.bottom, position.isVertical ? 0 : -3)
                        .frame(
                            width: position.isVertical ? groupedOpenedBackdropCrossAxisExtent(in: geo.size) : groupedOpenedBackdropExtent,
                            height: position.isVertical ? groupedOpenedBackdropExtent : nil
                        )
                        .offset(
                            x: position.isVertical ? 0 : groupedOpenedBackdropHorizontalXOffset,
                            y: position.isVertical ? groupedOpenedBackdropOffset + groupedOpenedBackdropVerticalYOffset : 0
                        )
                )
        }
    }

    @ViewBuilder
    private func displayContent(in size: CGSize) -> some View {
        if isInlineExpanded {
            inlineExpandedPlaceholder(in: size)
        } else {
            preview(in: size)
        }
    }

    private func inlineExpandedPlaceholder(in size: CGSize) -> some View {
        let minSide = min(size.width, size.height)
        let chevronSize = min(minSide * 0.32, 20)
        let inset = min(minSide * 0.1, 6)

        return ZStack {
            preview(in: size)
                .opacity(0.14)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.primary.opacity(0.08))

            Image(systemName: inlineExpandedChevronName)
                .font(.system(size: chevronSize, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))
        }
    }

    @ViewBuilder
    private func preview(in size: CGSize) -> some View {
        if tile.displayMode == .stack {
            stackedPreview(in: size)
        } else {
            iconGrid(in: size)
        }
    }

    private func iconGrid(in size: CGSize) -> some View {
        let displayedApps = Array(tile.apps.prefix(4))
        let side = min(size.width, size.height) * 0.36
        let gap = min(size.width, size.height) * (preferences.effectiveTileClipShape == .circle ? 0 : 0.06)

        return ZStack {
            Color.clear
                .background(.ultraThinMaterial)
                .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
                .dockyGlassBorder(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .padding(.top, 1)
                .padding(.bottom, 2)

            VStack(spacing: gap) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            Group {
                                if index < displayedApps.count {
                                    gridIcon(
                                        forBundleIdentifier: displayedApps[index].bundleIdentifier,
                                        side: side
                                    )
                                } else {
                                    if preferences.effectiveTileClipShape == .circle {
                                        let inset = preferences.effectiveTileClipShape == .circle ? floor(side * 3 / 32) : 0
                                        Circle()
                                            .fill(.primary.opacity(0.06))
                                            .padding(inset)
                                    } else {
                                        RoundedRectangle(cornerRadius: min(cornerRadius, 8), style: .continuous)
                                            .fill(.primary.opacity(0.06))
                                    }
                                }
                            }
                            .frame(width: side, height: side)
                        }
                    }
                }
            }
            .padding(size.width * 0.12)
        }
    }

    @ViewBuilder
    private func stackedPreview(in size: CGSize) -> some View {
        let displayedApps = Array(tile.apps.prefix(3))

        if let topApp = displayedApps.first {
            let additionalApps = Array(displayedApps.dropFirst().suffix(2))
            let chromeInset = floor(min(size.width, size.height) * 3 / 32)

            ZStack {
                ForEach(Array(additionalApps.enumerated()), id: \.element.bundleIdentifier) { index, app in
                    let depth = additionalApps.count - index
                    appStackTile(for: app, in: size, chromeInset: chromeInset)
                        .rotationEffect(.degrees(stackRotationDegrees(for: depth)))
                        .offset(
                            x: stackOffset(for: depth),
                            y: stackOffset(for: depth + 1)
                        )
                }

                appStackTile(for: topApp, in: size, chromeInset: chromeInset)
            }
            .frame(width: size.width, height: size.height)
        } else {
            iconGrid(in: size)
        }
    }

    private func appStackTile(for app: AppTile, in size: CGSize, chromeInset: CGFloat) -> some View {
        AppTileView(
            tile: AppTile(bundleIdentifier: app.bundleIdentifier, displayName: app.displayName),
            clipShape: preferences.effectiveTileClipShape,
            transparencyCompensationInset: chromeInset
        )
        .frame(width: size.width, height: size.height)
    }

    private func stackRotationDegrees(for depth: Int) -> Double {
        let magnitude = Double(depth) * 2.5
        return depth.isMultiple(of: 2) ? magnitude : -magnitude
    }

    private func stackOffset(for depth: Int) -> CGFloat {
        let magnitude = CGFloat(depth / 2) * 2.5
        return depth.isMultiple(of: 2) ? magnitude : -magnitude
    }

    @ViewBuilder
    private func gridIcon(forBundleIdentifier bundleIdentifier: String, side: CGFloat) -> some View {
        Group {
            if shouldApplyCircleClip(to: bundleIdentifier) {
                baseGridIcon(forBundleIdentifier: bundleIdentifier, side: side)
                    .dockyGlass(in: Circle())
                    .clipShape(Circle())
            } else {
                baseGridIcon(forBundleIdentifier: bundleIdentifier, side: side)
            }
        }
        // Painted after the clip so the badge can sit outside a circular
        // icon's edge without being cut off.
        .overlay(alignment: .topTrailing) {
            previewBadge(forBundleIdentifier: bundleIdentifier)
        }
    }

    /// Per-app notification badge for the dock-tile grid preview. Only shown
    /// when badges are on and the folder is in per-app mode; the dot/number
    /// form follows `folderBadgePreviewStyle`.
    @ViewBuilder
    private func previewBadge(forBundleIdentifier bundleIdentifier: String) -> some View {
        if preferences.showsAppBadges,
           preferences.folderBadgeMode == .perApp,
           let badge = dockBadges.badge(forBundleIdentifier: bundleIdentifier) {
            switch preferences.folderBadgePreviewStyle {
            case .dot:
                DockBadgeDotView(scale: 1.35, verticalOffsetFactor: -0.20)
            case .number:
                DockBadgeView(text: badge, scale: 1.35, verticalOffsetFactor: -0.20)
            }
        }
    }

    private func baseGridIcon(forBundleIdentifier bundleIdentifier: String, side: CGFloat) -> some View {
        let inset = shouldApplyCircleClip(to: bundleIdentifier) ? floor(side * 3 / 32) : 0
        let overridePadding = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: bundleIdentifier) != nil
            ? preferences.appIconOverridePadding(forBundleIdentifier: bundleIdentifier) * side
            : 0

        return Image(nsImage: icon(forBundleIdentifier: bundleIdentifier))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: side + inset * 2, height: side + inset * 2)
            .frame(width: side - inset * 2, height: side - inset * 2)
            .padding(overridePadding)
    }

    private func shouldApplyCircleClip(to bundleIdentifier: String) -> Bool {
        preferences.effectiveTileClipShape == .circle
    }

    private func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        if let overrideURL = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: bundleIdentifier),
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return IconCacheService.shared.icon(forBundleIdentifier: bundleIdentifier)
    }
}

/// In-flight reorder state for the launchpad-style folder rearrange.
/// `targetIndex` is interpreted in the post-removal coordinate space so
/// the reflow math matches what `TileStore.reorderAppsInFolder(...
/// toIndex:)` will eventually apply.
private struct AppFolderReorderDragState: Equatable {
    let bundleIdentifier: String
    let originIndex: Int
    var targetIndex: Int
    var location: CGPoint
}

/// Aggregates per-cell frames keyed by bundle identifier so the drag
/// handler can convert the cursor location into an insertion index.
private struct AppFolderCellFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct AppFolderPopoverView: View {
    let tile: AppFolderTile
    let tileID: String
    @Binding var isPresented: Bool
    let onPopoverSizeChange: (CGSize) -> Void
    @Bindable private var preferences = DockyPreferences.shared
    @ObservedObject private var dockBadges = DockBadgeService.shared
    @State private var isEditingTitle = false
    @State private var editingTitle = ""
    @State private var isTitleHovered = false
    /// Launchpad-style edit mode. Toggled by the header's Reorder/Done
    /// button. When on, taps no longer launch apps and the in-popover
    /// drag-and-drop reorder is enabled; drag-out to the dock is
    /// suppressed so a slightly-too-long click can't accidentally pop an
    /// app out of the folder.
    @State private var isReorderMode = false
    @State private var dragState: AppFolderReorderDragState?
    @State private var cellFrames: [String: CGRect] = [:]
    @FocusState private var isTitleFieldFocused: Bool

    fileprivate static let columns = 3
    fileprivate static let itemWidth: CGFloat = 96
    fileprivate static let itemHeight: CGFloat = 96
    fileprivate static let itemSpacing: CGFloat = 12
    fileprivate static let contentPadding: CGFloat = 20
    fileprivate static let headerHeight: CGFloat = 42
    fileprivate static let maxHeight: CGFloat = 620
    /// Local coordinate space the grid uses to compute drag insertion
    /// indices. The DragGesture reports cursor location in this space so
    /// the math doesn't have to chase the popover's screen origin.
    private static let gridCoordinateSpace = "appFolderGrid"

    init(
        tile: AppFolderTile,
        tileID: String,
        isPresented: Binding<Bool>,
        onPopoverSizeChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.tile = tile
        self.tileID = tileID
        _isPresented = isPresented
        self.onPopoverSizeChange = onPopoverSizeChange
    }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        VStack(spacing: 0) {
            HStack {
                titleView

                Spacer(minLength: 0)

                reorderToggle
            }
            .padding(.horizontal, Self.contentPadding)
            .padding(.top, 16)
            .frame(height: Self.headerHeight)

            ScrollView(showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    LazyVGrid(columns: gridColumns, spacing: Self.itemSpacing) {
                        ForEach(displayedApps, id: \.bundleIdentifier) { app in
                            gridCell(for: app)
                        }
                    }
                    .padding(Self.contentPadding)
                    .coordinateSpace(name: Self.gridCoordinateSpace)
                    .onPreferenceChange(AppFolderCellFramePreference.self) { frames in
                        cellFrames = frames
                    }

                    // The dragged icon renders as a free-floating overlay
                    // that follows the cursor. Its grid slot is hidden so
                    // siblings can reflow into the freed space without a
                    // ghost placeholder.
                    if let dragState,
                       let app = tile.apps.first(where: { $0.bundleIdentifier == dragState.bundleIdentifier }) {
                        iconImage(for: app)
                            .position(dragState.location)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(width: popoverSize.width, height: popoverSize.height)
        .onAppear {
            onPopoverSizeChange(popoverSize)
        }
        .onChange(of: tile.apps.count) { _ in
            onPopoverSizeChange(popoverSize)
        }
        .onChange(of: isPresented) { presented in
            // Reset reorder mode when the popover closes so re-opening
            // always starts in the standard launch-on-tap state.
            if !presented, isReorderMode {
                isReorderMode = false
            }
        }
    }

    /// Apps in the order they should be rendered right now. With no
    /// active drag this is just `tile.apps`; mid-drag the dragged app
    /// is removed from its origin and re-inserted at `dragState.targetIndex`
    /// so siblings shift to make way.
    private var displayedApps: [AppTile] {
        guard let dragState else { return tile.apps }
        var apps = tile.apps
        guard let currentIndex = apps.firstIndex(where: { $0.bundleIdentifier == dragState.bundleIdentifier }) else {
            return apps
        }
        let item = apps.remove(at: currentIndex)
        let clamped = max(0, min(dragState.targetIndex, apps.count))
        apps.insert(item, at: clamped)
        return apps
    }

    @ViewBuilder
    private func gridCell(for app: AppTile) -> some View {
        let isBeingDragged = dragState?.bundleIdentifier == app.bundleIdentifier

        Button {
            guard !isReorderMode else { return }
            WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
            isPresented = false
        } label: {
            iconImage(for: app)
                .opacity(isBeingDragged ? 0 : (isReorderMode ? 0.85 : 1))
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: AppFolderCellFramePreference.self,
                    value: [app.bundleIdentifier: proxy.frame(in: .named(Self.gridCoordinateSpace))]
                )
            }
        }
        .modifier(AppFolderItemDragModifier(
            app: app,
            tileID: tileID,
            isReorderMode: isReorderMode,
            beginDragOutOfFolder: beginDragOutOfFolder,
            openDroppedFiles: { providers, target in
                openDroppedFiles(providers: providers, with: target)
            }
        ))
        .modifier(AppFolderReorderGestureModifier(
            isReorderMode: isReorderMode,
            coordinateSpace: Self.gridCoordinateSpace,
            onChange: { value in
                handleReorderChange(bundleIdentifier: app.bundleIdentifier, value: value)
            },
            onEnd: { value in
                handleReorderEnd(bundleIdentifier: app.bundleIdentifier, value: value)
            }
        ))
        .background {
            ContextActionMenuPresenter { modifierFlags in
                appContextActions(for: app, modifierFlags: modifierFlags)
            }
        }
    }

    @ViewBuilder
    private func iconImage(for app: AppTile) -> some View {
        Image(nsImage: icon(forBundleIdentifier: app.bundleIdentifier))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: Self.itemWidth, height: Self.itemHeight)
            .padding(overrideIconPadding(for: app.bundleIdentifier, side: Self.itemWidth))
            // The opened folder always shows the real per-app count,
            // regardless of the tile's combined/per-app preference — these
            // icons are full size, so the number is always legible.
            .overlay(alignment: .topTrailing) {
                if preferences.showsAppBadges,
                   let badge = dockBadges.badge(forBundleIdentifier: app.bundleIdentifier) {
                    DockBadgeView(text: badge)
                }
            }
    }

    private func handleReorderChange(bundleIdentifier: String, value: DragGesture.Value) {
        if dragState == nil {
            guard let originIndex = tile.apps.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
            dragState = AppFolderReorderDragState(
                bundleIdentifier: bundleIdentifier,
                originIndex: originIndex,
                targetIndex: originIndex,
                location: value.location
            )
        }
        guard var state = dragState else { return }
        state.location = value.location
        state.targetIndex = resolveInsertionIndex(at: value.location, draggedBundleIdentifier: bundleIdentifier)
        withAnimation(.spring(duration: 0.32, bounce: 0.18)) {
            dragState = state
        }
    }

    private func handleReorderEnd(bundleIdentifier: String, value: DragGesture.Value) {
        defer {
            withAnimation(.spring(duration: 0.28, bounce: 0.2)) {
                dragState = nil
            }
        }
        guard let state = dragState, state.bundleIdentifier == bundleIdentifier else { return }
        guard state.targetIndex != state.originIndex else { return }
        TileStore.shared.reorderAppsInFolder(
            tileID: tileID,
            movingBundleIdentifier: bundleIdentifier,
            toIndex: state.targetIndex
        )
    }

    /// Maps the cursor location to the post-removal insertion index.
    /// Excludes the dragged cell so it can't flag itself as the target.
    /// Falls back to "end of list" when no cell is found in range, which
    /// covers drags that drift below the last row.
    private func resolveInsertionIndex(at location: CGPoint, draggedBundleIdentifier: String) -> Int {
        let apps = tile.apps
        guard !apps.isEmpty else { return 0 }

        var directHit: (index: Int, frame: CGRect)?
        var nearestHit: (index: Int, frame: CGRect, distance: CGFloat)?

        for (index, app) in apps.enumerated() {
            guard app.bundleIdentifier != draggedBundleIdentifier,
                  let frame = cellFrames[app.bundleIdentifier] else { continue }
            if frame.contains(location) {
                directHit = (index, frame)
                break
            }
            let dx = location.x - frame.midX
            let dy = location.y - frame.midY
            let distance = sqrt(dx * dx + dy * dy)
            if nearestHit == nil || distance < nearestHit!.distance {
                nearestHit = (index, frame, distance)
            }
        }

        let hit = directHit ?? nearestHit.map { (index: $0.index, frame: $0.frame) }
        guard let hit else { return apps.count - 1 }

        // Insert before the hit cell when the cursor is on its leading
        // half, after when on the trailing half. Works row-by-row because
        // each cell's frame already encodes its own row.
        let insertion = location.x < hit.frame.midX ? hit.index : hit.index + 1
        return max(0, min(insertion, apps.count - 1))
    }

    @ViewBuilder
    private var reorderToggle: some View {
        Button {
            isReorderMode.toggle()
        } label: {
            Text(isReorderMode ? "Done" : "Reorder")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isReorderMode ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(isReorderMode ? "Stop rearranging icons" : "Drag icons to rearrange them")
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditingTitle {
            TextField("Folder", text: $editingTitle)
                .textFieldStyle(.plain)
                .font(.headline)
                .lineLimit(1)
                .focused($isTitleFieldFocused)
                .onSubmit { commitTitleEdit() }
                .onExitCommand { cancelTitleEdit() }
                .onChange(of: isTitleFieldFocused) { focused in
                    if !focused, isEditingTitle {
                        commitTitleEdit()
                    }
                }
        } else {
            Text(tile.displayName)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(isTitleHovered ? 0.08 : 0))
                )
                .padding(.horizontal, -4)
                .padding(.vertical, -2)
                .contentShape(Rectangle())
                .onHover { isTitleHovered = $0 }
                .onTapGesture { startTitleEdit() }
                .help("Click to rename")
        }
    }

    private func startTitleEdit() {
        editingTitle = tile.displayName
        isEditingTitle = true
        DispatchQueue.main.async {
            isTitleFieldFocused = true
        }
    }

    private func commitTitleEdit() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != tile.displayName {
            TileStore.shared.renameAppFolder(tileID: tileID, displayName: trimmed)
        }
        isEditingTitle = false
        isTitleFieldFocused = false
    }

    private func cancelTitleEdit() {
        isEditingTitle = false
        isTitleFieldFocused = false
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(Self.itemWidth), spacing: Self.itemSpacing, alignment: .top),
            count: Self.columns
        )
    }

    private var popoverSize: CGSize {
        Self.popoverSize(forAppCount: tile.apps.count)
    }

    static func popoverSize(forAppCount appCount: Int) -> CGSize {
        let rows = max(Int(ceil(Double(appCount) / Double(columns))), 1)
        let width = CGFloat(columns) * itemWidth + CGFloat(columns - 1) * itemSpacing + contentPadding * 2
        let gridHeight = CGFloat(rows) * itemHeight + CGFloat(max(rows - 1, 0)) * itemSpacing
        let height = min(gridHeight + contentPadding * 2 + headerHeight + 16, maxHeight)
        return CGSize(width: width, height: height)
    }

    private func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        if let overrideURL = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: bundleIdentifier),
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return IconCacheService.shared.icon(forBundleIdentifier: bundleIdentifier)
    }

    private func overrideIconPadding(for bundleIdentifier: String, side: CGFloat) -> CGFloat {
        guard preferences.effectiveAppIconOverrideURL(forBundleIdentifier: bundleIdentifier) != nil else {
            return 0
        }
        return preferences.appIconOverridePadding(forBundleIdentifier: bundleIdentifier) * side
    }

    /// Builds the same context menu a dock AppTile would show, scoped to the
    /// catalog-defined actions plus the running-windows section. Docky-only
    /// options ("Show as Widget", "Hide in Docky") are intentionally omitted —
    /// they don't apply to apps surfaced from inside an app folder.
    private func appContextActions(
        for app: AppTile,
        modifierFlags: NSEvent.ModifierFlags
    ) -> [ContextAction] {
        let syntheticTile = Tile(content: .app(app))
        let baseActions = MenuCatalogService.shared
            .contextActions(for: syntheticTile, modifierFlags: modifierFlags) ?? []
        let windows = WorkspaceService.shared.appWindows(bundleIdentifier: app.bundleIdentifier)
        let withWindows = injectingAppWindowActions(windows, into: baseActions)
        return appendingRemoveFromFolder(to: withWindows, for: app)
    }

    private func appendingRemoveFromFolder(
        to actions: [ContextAction],
        for app: AppTile
    ) -> [ContextAction] {
        let folderID = tileID
        let bundleIdentifier = app.bundleIdentifier

        var result = actions
        if !result.isEmpty, result.last?.kind != .divider {
            result.append(.divider)
        }
        result.append(.action(
            String(localized: "Remove from Folder"),
            image: NSImage(systemSymbolName: "folder.badge.minus", accessibilityDescription: nil)
        ) {
            TileStore.shared.removeAppFromFolder(
                tileID: folderID,
                bundleIdentifier: bundleIdentifier
            )
        })
        return result
    }

    private func openDroppedFiles(providers: [NSItemProvider], with app: AppTile) {
        // The "open file with app" drop fires for any file URL dropped on a
        // sibling icon — including ours. When the active drag started by
        // dragging an icon OUT of this folder, ignore the drop so the user
        // doesn't accidentally open the dragged app with the sibling.
        guard DockDragService.shared.sourceFolderTileID == nil else {
            DockDragService.shared.clear()
            return
        }

        let typeID = UTType.fileURL.identifier
        let group = DispatchGroup()
        var collected: [URL] = []
        let queue = DispatchQueue(label: "docky.appfolder.drop")

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(typeID) else { continue }
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
                defer { group.leave() }
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                queue.sync { collected.append(url) }
            }
        }

        group.notify(queue: .main) {
            guard !collected.isEmpty else {
                DockDragService.shared.clear()
                return
            }
            WorkspaceService.shared.open(
                fileURLs: collected,
                withApplicationBundleIdentifier: app.bundleIdentifier
            )
            isPresented = false
            DockDragService.shared.clear()
        }
    }

    /// Begins a system drag that carries the app's bundle URL on the
    /// pasteboard. The dock window's drag destination resolves that URL to
    /// the existing `.app` preview kind via `DockDragService.resolvePreview`,
    /// and the source-folder fields tell the drop handler to remove the app
    /// from this folder before pinning it at the destination.
    ///
    /// The popover intentionally stays open through the drag so the user
    /// can drop on a sibling icon to reorder. Drag-out flows still work
    /// because the popover is anchored above its source tile and leaves
    /// the rest of the dock visible; the AppKit drag image is owned at
    /// the screen level so dropping on the desktop or another dock tile
    /// is unaffected by the popover's visibility.
    private func beginDragOutOfFolder(for app: AppTile) -> NSItemProvider {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
        DockDragService.shared.sourceFolderTileID = tileID
        DockDragService.shared.sourceFolderBundleIdentifier = app.bundleIdentifier
        // Set kind synchronously so the dock's autohide gate ([[shouldRemainVisible]])
        // engages before the popover would otherwise close. draggingEntered
        // overwrites kind with the same value once the cursor reaches the
        // dock window.
        if let url {
            DockDragService.shared.kind = .app(url, app)
        }
        // Arm a polling cleanup. Drags that never cross the dock view (e.g.
        // user drops on Finder) won't trigger the dock's draggingEnded, so
        // this is what eventually clears the kind+source-folder state and
        // lets the dock auto-hide again.
        DockDragService.shared.armMouseReleaseCleanup()

        if let url {
            return NSItemProvider(object: url as NSURL)
        }
        return NSItemProvider()
    }
}

struct AppFolderListMenuPresenter: NSViewRepresentable {
    let tile: AppFolderTile
    let tileID: String
    @Binding var isPresented: Bool
    let preferredEdge: NSRectEdge

    func makeCoordinator() -> Coordinator {
        Coordinator(tile: tile, tileID: tileID, isPresented: $isPresented, preferredEdge: preferredEdge)
    }

    func makeNSView(context: Context) -> AppFolderPopoverAnchorView {
        AppFolderPopoverAnchorView()
    }

    func updateNSView(_ nsView: AppFolderPopoverAnchorView, context: Context) {
        context.coordinator.update(tile: tile, tileID: tileID, isPresented: $isPresented, preferredEdge: preferredEdge)

        if isPresented {
            DispatchQueue.main.async {
                context.coordinator.show(relativeTo: nsView)
            }
        } else {
            context.coordinator.close()
        }
    }

    static func dismantleNSView(_ nsView: AppFolderPopoverAnchorView, coordinator: Coordinator) {
        coordinator.close()
    }

    final class Coordinator: NSObject {
        private var tile: AppFolderTile
        private var tileID: String
        private var isPresented: Binding<Bool>
        private var preferredEdge: NSRectEdge
        private weak var anchorView: NSView?
        private var isShowing = false
        private var isInterruptingAutohide = false

        init(tile: AppFolderTile, tileID: String, isPresented: Binding<Bool>, preferredEdge: NSRectEdge) {
            self.tile = tile
            self.tileID = tileID
            self.isPresented = isPresented
            self.preferredEdge = preferredEdge
            super.init()
        }

        func update(tile: AppFolderTile, tileID: String, isPresented: Binding<Bool>, preferredEdge: NSRectEdge) {
            self.tile = tile
            self.tileID = tileID
            self.isPresented = isPresented
            self.preferredEdge = preferredEdge
        }

        func show(relativeTo view: NSView) {
            guard view.window != nil, !isShowing else { return }

            anchorView = view
            isShowing = true
            beginAutohideInterruption(for: view)
            popUp(menu: buildMenu(), in: view)
            endAutohideInterruption()
            isShowing = false

            DispatchQueue.main.async { [isPresented] in
                guard isPresented.wrappedValue else { return }
                isPresented.wrappedValue = false
            }
        }

        func close() {
            endAutohideInterruption()
            isShowing = false
        }

        private func buildMenu() -> NSMenu {
            let menu = NSMenu(title: tile.displayName)

            let showsBadges = DockyPreferences.shared.showsAppBadges
            for app in tile.apps {
                var title = app.displayName
                // Surface each app's unread count inline, e.g. "Mail (5)".
                // Plain text keeps the native menu look (no red pill).
                if showsBadges,
                   let badge = DockBadgeService.shared.badge(forBundleIdentifier: app.bundleIdentifier) {
                    title += " (\(badge))"
                }
                let item = NSMenuItem(title: title, action: #selector(openApp(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = app.bundleIdentifier
                item.image = listMenuIcon(for: app.bundleIdentifier)
                menu.addItem(item)
            }

            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }

            let openAll = NSMenuItem(title: "Open All", action: #selector(openAllApps), keyEquivalent: "")
            openAll.target = self
            openAll.isEnabled = !tile.apps.isEmpty
            menu.addItem(openAll)

            if !tile.apps.isEmpty {
                menu.addItem(.separator())
                let removeRoot = NSMenuItem(
                    title: String(localized: "Remove from Folder"),
                    action: nil,
                    keyEquivalent: ""
                )
                removeRoot.image = NSImage(systemSymbolName: "folder.badge.minus", accessibilityDescription: nil)
                let removeSubmenu = NSMenu(title: String(localized: "Remove from Folder"))
                for app in tile.apps {
                    let item = NSMenuItem(
                        title: app.displayName,
                        action: #selector(removeApp(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = app.bundleIdentifier
                    item.image = listMenuIcon(for: app.bundleIdentifier)
                    removeSubmenu.addItem(item)
                }
                removeRoot.submenu = removeSubmenu
                menu.addItem(removeRoot)
            }

            return menu
        }

        private func listMenuIcon(for bundleIdentifier: String) -> NSImage {
            let baseIcon: NSImage
            if let overrideURL = DockyPreferences.shared.effectiveAppIconOverrideURL(forBundleIdentifier: bundleIdentifier),
               let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
                baseIcon = overrideImage
            } else {
                baseIcon = IconCacheService.shared.icon(forBundleIdentifier: bundleIdentifier)
            }

            let icon = baseIcon.copy() as? NSImage ?? baseIcon
            icon.size = NSSize(width: 16, height: 16)
            return icon
        }

        @objc private func openApp(_ sender: NSMenuItem) {
            guard let bundleIdentifier = sender.representedObject as? String else { return }
            WorkspaceService.shared.activateOrOpen(bundleIdentifier: bundleIdentifier)
        }

        @objc private func openAllApps() {
            for app in tile.apps {
                WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
            }
        }

        @objc private func removeApp(_ sender: NSMenuItem) {
            guard let bundleIdentifier = sender.representedObject as? String else { return }
            TileStore.shared.removeAppFromFolder(
                tileID: tileID,
                bundleIdentifier: bundleIdentifier
            )
        }

        private func popUp(menu: NSMenu, in view: NSView) {
            let selector = NSSelectorFromString("_popUpMenuRelativeToRect:inView:preferredEdge:")
            if menu.responds(to: selector) {
                typealias Fn = @convention(c) (NSMenu, Selector, NSRect, NSView?, NSRectEdge) -> Void
                let imp = menu.method(for: selector)
                let fn = unsafeBitCast(imp, to: Fn.self)
                fn(menu, selector, view.bounds, view, preferredEdge)
                return
            }

            menu.update()
            menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.midX - menu.size.width / 2, y: view.bounds.maxY), in: view)
        }

        private func beginAutohideInterruption(for view: NSView) {
            guard !isInterruptingAutohide else { return }
            (view.window as? MainWindow)?.beginInteraction()
            isInterruptingAutohide = true
        }

        private func endAutohideInterruption() {
            guard isInterruptingAutohide else { return }
            (anchorView?.window as? MainWindow)?.endInteraction()
            isInterruptingAutohide = false
        }
    }
}

struct AppFolderPopoverPresenter: NSViewRepresentable {
    let tile: AppFolderTile
    let tileID: String
    @Binding var isPresented: Bool
    let preferredEdge: NSRectEdge

    func makeCoordinator() -> Coordinator {
        Coordinator(tile: tile, tileID: tileID, isPresented: $isPresented, preferredEdge: preferredEdge)
    }

    func makeNSView(context: Context) -> AppFolderPopoverAnchorView {
        AppFolderPopoverAnchorView()
    }

    func updateNSView(_ nsView: AppFolderPopoverAnchorView, context: Context) {
        context.coordinator.update(tile: tile, tileID: tileID, isPresented: $isPresented, preferredEdge: preferredEdge)

        if isPresented {
            context.coordinator.show(relativeTo: nsView)
        } else {
            context.coordinator.close()
        }
    }

    static func dismantleNSView(_ nsView: AppFolderPopoverAnchorView, coordinator: Coordinator) {
        coordinator.close()
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        private let popover = NSPopover()
        private let hostingController = NSHostingController(
            rootView: AppFolderPopoverView(
                tile: AppFolderTile(identifier: "", displayName: "", apps: []),
                tileID: "",
                isPresented: .constant(false)
            )
        )
        private var tile: AppFolderTile
        private var tileID: String
        private var isPresented: Binding<Bool>
        private var preferredEdge: NSRectEdge
        private weak var anchorView: NSView?
        private var isInterruptingAutohide = false
        private var globalClickMonitor: Any?
        private var localClickMonitor: Any?
        private var dragEndSubscription: AnyCancellable?

        init(tile: AppFolderTile, tileID: String, isPresented: Binding<Bool>, preferredEdge: NSRectEdge) {
            self.tile = tile
            self.tileID = tileID
            self.isPresented = isPresented
            self.preferredEdge = preferredEdge
            super.init()
            popover.contentViewController = hostingController
            popover.animates = true
            popover.behavior = .transient
            popover.delegate = self
            update(tile: tile, tileID: tileID, isPresented: isPresented, preferredEdge: preferredEdge)
        }

        func update(tile: AppFolderTile, tileID: String, isPresented: Binding<Bool>, preferredEdge: NSRectEdge) {
            self.tile = tile
            self.tileID = tileID
            self.isPresented = isPresented
            self.preferredEdge = preferredEdge
            hostingController.rootView = AppFolderPopoverView(
                tile: tile,
                tileID: tileID,
                isPresented: isPresented,
                onPopoverSizeChange: { [weak self] size in
                    self?.updateContentSize(size)
                }
            )
        }

        func show(relativeTo view: NSView) {
            guard view.window != nil, !popover.isShown else { return }
            anchorView = view
            beginAutohideInterruption(for: view)
            // Size the popover for the current tile BEFORE showing.
            // Why: relying on SwiftUI's .onAppear to resize after show left the
            // host view smaller than the SwiftUI content when the tile grew
            // between opens (e.g. 3 → 4 apps), clipping the new row out of the
            // hit-test region.
            updateContentSize(AppFolderPopoverView.popoverSize(forAppCount: tile.apps.count))
            popover.show(relativeTo: anchorRect(in: view.bounds), of: view, preferredEdge: preferredEdge)
            installClickAwayMonitors()
            installDragEndSubscriptionIfNeeded()
        }

        func close() {
            removeClickAwayMonitors()
            cancelDragEndSubscription()
            endAutohideInterruption()
            popover.performClose(nil)
        }

        func popoverDidClose(_ notification: Notification) {
            removeClickAwayMonitors()
            cancelDragEndSubscription()
            endAutohideInterruption()
            guard isPresented.wrappedValue else { return }
            DispatchQueue.main.async { [isPresented] in
                isPresented.wrappedValue = false
            }
        }

        /// When the popover is presented during an active drag (spring-load),
        /// observe the drag service so the popover closes the moment the drag
        /// ends — drop on us, drop elsewhere, or Esc. The dropFirst() skips
        /// the initial value so we only react to subsequent transitions.
        private func installDragEndSubscriptionIfNeeded() {
            cancelDragEndSubscription()
            guard DockDragService.shared.kind != nil else { return }
            dragEndSubscription = DockDragService.shared.$kind
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] kind in
                    guard kind == nil else { return }
                    self?.dismissAfterDragEnd()
                }
        }

        private func cancelDragEndSubscription() {
            dragEndSubscription?.cancel()
            dragEndSubscription = nil
        }

        private func dismissAfterDragEnd() {
            cancelDragEndSubscription()
            // Tiny delay lets any in-flight drop handler (which may also be
            // setting isPresented = false) finish cleanly before we close.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, isPresented] in
                guard let self else { return }
                if isPresented.wrappedValue {
                    self.popover.performClose(nil)
                    isPresented.wrappedValue = false
                }
            }
        }

        /// NSPopover.behavior = .transient should auto-dismiss on outside
        /// clicks, but it's unreliable when the host window is non-activating
        /// (Docky's dock window). Belt-and-suspenders: explicit monitors
        /// catch any mouse-down outside the popover and close it.
        private func installClickAwayMonitors() {
            removeClickAwayMonitors()
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                self?.dismissForClickAway()
            }
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self else { return event }
                let popoverWindow = self.popover.contentViewController?.view.window
                if event.window !== popoverWindow {
                    self.dismissForClickAway()
                }
                return event
            }
        }

        private func removeClickAwayMonitors() {
            if let monitor = globalClickMonitor {
                NSEvent.removeMonitor(monitor)
                globalClickMonitor = nil
            }
            if let monitor = localClickMonitor {
                NSEvent.removeMonitor(monitor)
                localClickMonitor = nil
            }
        }

        private func dismissForClickAway() {
            removeClickAwayMonitors()
            DispatchQueue.main.async { [weak self, isPresented] in
                self?.popover.performClose(nil)
                if isPresented.wrappedValue {
                    isPresented.wrappedValue = false
                }
            }
        }

        private func beginAutohideInterruption(for view: NSView) {
            guard !isInterruptingAutohide else { return }
            (view.window as? MainWindow)?.beginInteraction()
            isInterruptingAutohide = true
        }

        private func endAutohideInterruption() {
            guard isInterruptingAutohide else { return }
            (anchorView?.window as? MainWindow)?.endInteraction()
            isInterruptingAutohide = false
        }

        private func updateContentSize(_ size: CGSize) {
            let contentSize = NSSize(width: size.width, height: size.height)
            guard contentSize.width > 0, contentSize.height > 0 else { return }
            hostingController.preferredContentSize = contentSize
            popover.contentSize = contentSize
        }

        private func anchorRect(in bounds: NSRect) -> NSRect {
            switch preferredEdge {
            case .minX:
                NSRect(x: bounds.minX, y: bounds.midY - 0.5, width: 1, height: 1)
            case .maxX:
                NSRect(x: bounds.maxX - 1, y: bounds.midY - 0.5, width: 1, height: 1)
            case .minY:
                NSRect(x: bounds.midX - 0.5, y: bounds.minY, width: 1, height: 1)
            case .maxY:
                NSRect(x: bounds.midX - 0.5, y: bounds.maxY - 1, width: 1, height: 1)
            @unknown default:
                NSRect(x: bounds.midX - 0.5, y: bounds.maxY - 1, width: 1, height: 1)
            }
        }
    }
}

final class AppFolderPopoverAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Carries the normal-mode drag/drop behavior on each app-folder grid
/// item: drag begins the "remove from folder" flow that hands the app
/// off to the dock, drop opens files with the app. In reorder mode the
/// modifier becomes a no-op so the launchpad-style `DragGesture` owns
/// the gesture path without competing handlers.
private struct AppFolderItemDragModifier: ViewModifier {
    let app: AppTile
    let tileID: String
    let isReorderMode: Bool
    let beginDragOutOfFolder: (AppTile) -> NSItemProvider
    let openDroppedFiles: ([NSItemProvider], AppTile) -> Void

    func body(content: Content) -> some View {
        if isReorderMode {
            content
        } else {
            content
                .onDrag { beginDragOutOfFolder(app) }
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
                    openDroppedFiles(providers, app)
                    return true
                }
        }
    }
}

/// Conditionally attaches the launchpad-style reorder `DragGesture`.
/// `.highPriorityGesture` so a movement past `minimumDistance` consumes
/// the event and the Button's tap action stays inert during reorder mode.
private struct AppFolderReorderGestureModifier: ViewModifier {
    let isReorderMode: Bool
    let coordinateSpace: String
    let onChange: (DragGesture.Value) -> Void
    let onEnd: (DragGesture.Value) -> Void

    func body(content: Content) -> some View {
        if isReorderMode {
            content
                .highPriorityGesture(
                    DragGesture(
                        minimumDistance: 6,
                        coordinateSpace: .named(coordinateSpace)
                    )
                    .onChanged { onChange($0) }
                    .onEnded { onEnd($0) }
                )
        } else {
            content
        }
    }
}
