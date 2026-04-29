//
//  TileView.swift
//  Docky
//
//  Generic tile wrapper. Picks a concrete content view based on the tile's
//  case and applies any chrome shared across all tile types (hover, etc).
//

import AppKit
import SwiftUI

struct TileView: View {
    let tile: Tile
    let isDragging: Bool
    let isExternalFileDropTargeted: Bool
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var layout = DockLayoutService.shared
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared
    @ObservedObject private var workspace = WorkspaceService.shared
    @ObservedObject private var mediaPlayback = MediaPlaybackService.shared
    @ObservedObject private var editMode = DockEditModeService.shared
    @State private var isHovering = false
    @State private var isTooltipPresented = false
    @State private var isFolderPopoverPresented = false
    @State private var isFolderListMenuPresented = false
    @State private var isAppFolderPopoverPresented = false
    @State private var isAppFolderListMenuPresented = false
    @State private var isContextMenuPresented = false
    @State private var folderSnapshot: FolderContentsSnapshot = .loaded([])
    @State private var lastFolderPopoverDismissedAt: TimeInterval = 0

    private static let finderBundleIdentifier = "com.apple.finder"
    private static let folderPopoverRetapGuardInterval: TimeInterval = 0.25

    init(tile: Tile, isDragging: Bool = false, isExternalFileDropTargeted: Bool = false) {
        self.tile = tile
        self.isDragging = isDragging
        self.isExternalFileDropTargeted = isExternalFileDropTargeted
        self._dockSettings = ObservedObject(wrappedValue: DockSettingsService.shared)
        self._layout = ObservedObject(wrappedValue: DockLayoutService.shared)
        self._preferences = ObservedObject(wrappedValue: DockyPreferences.shared)
        self._product = ObservedObject(wrappedValue: ProductService.shared)
        self._workspace = ObservedObject(wrappedValue: WorkspaceService.shared)
        self._mediaPlayback = ObservedObject(wrappedValue: MediaPlaybackService.shared)
        self._editMode = ObservedObject(wrappedValue: DockEditModeService.shared)
    }

    private func contextActions(modifierFlags: NSEvent.ModifierFlags) -> [ContextAction] {
        if lockedProductFeature != nil {
            return lockedContextActions()
        }

        if let catalogActions = MenuCatalogService.shared.contextActions(for: tile, modifierFlags: modifierFlags) {
            switch tile.content {
            case .app(let app):
                return appContextActions(for: app, modifierFlags: modifierFlags, baseActions: catalogActions)
            case .trash:
                return catalogActions
            case .launchpad:
                var actions = catalogActions
                if !customDockyTileActions.isEmpty {
                    actions.append(.divider)
                    actions.append(contentsOf: customDockyTileActions)
                }
                return actions
            case .folder:
                var actions = folderPresentationContextActions + [.divider] + catalogActions
                if isDockyTrailingTile {
                    actions.append(.divider)
                    actions.append(.action("Remove from Dock") {
                        removeDockyTile()
                    })
                }
                return actions
            case .minimizedWindow, .appFolder, .widget, .smartStack, .spacer, .divider:
                break
            }
        }

        switch tile.content {
        case .app(let app):
            return appContextActions(for: app, modifierFlags: modifierFlags)
        case .minimizedWindow(let window):
            return minimizedWindowContextActions(for: window, modifierFlags: modifierFlags)
        case .appFolder(let folder):
            return appFolderContextActions(for: folder)
        case .launchpad:
            var actions: [ContextAction] = []

            if preferences.enablesLaunchpadOverlay {
                actions.append(.action("Open Launchpad") {
                    LaunchpadOverlayService.shared.present()
                })
            }

            if !customDockyTileActions.isEmpty {
                if !actions.isEmpty {
                    actions.append(.divider)
                }
                actions.append(contentsOf: customDockyTileActions)
            }

            return actions
        case .widget(let widget):
            return widgetContextActions(for: widget)
        case .smartStack(let stack):
            return smartStackContextActions(for: stack)
        case .folder(let folder):
            var actions = folderPresentationContextActions + [.divider,
                .action("Open in Finder") {
                    Task {
                        _ = await AppleScriptService.shared.openFinderWindow(for: folder.url)
                    }
                },
                .action("Reveal in Finder") {
                    Task {
                        _ = await AppleScriptService.shared.revealInFinder(folder.url)
                    }
                }
            ]

            if isDockyTrailingTile {
                actions.append(.divider)
                actions.append(.action("Remove from Dock") {
                    removeDockyTile()
                })
            }

            return actions
        case .trash:
            return [
                .action("Open Trash") {
                    Task {
                        _ = await AppleScriptService.shared.openTrash()
                    }
                },
                .divider,
                .action("Empty Trash", isDestructive: true) {
                    Task {
                        _ = await AppleScriptService.shared.emptyTrash()
                    }
                }
            ]
        case .spacer, .divider:
            return customDockyTileActions
        }
    }

    private var folderPresentationContextActions: [ContextAction] {
        guard case .folder(let folder) = tile.content else {
            return []
        }

        return [
            .submenu("Display as", children: [
                .action("Folder", isOn: folderDisplayMode == .folder) {
                    TileStore.shared.setFolderDisplayMode(tileID: tile.id, folderURL: folder.url, mode: .folder)
                },
                .action("Contents", isOn: folderDisplayMode == .contents) {
                    TileStore.shared.setFolderDisplayMode(tileID: tile.id, folderURL: folder.url, mode: .contents)
                }
            ]),
            .submenu("View Content as", children: [
                .action("Grid", isOn: folderContentViewMode == .grid) {
                    TileStore.shared.setFolderContentViewMode(tileID: tile.id, folderURL: folder.url, mode: .grid)
                },
                .action("List", isOn: folderContentViewMode == .list) {
                    TileStore.shared.setFolderContentViewMode(tileID: tile.id, folderURL: folder.url, mode: .list)
                }
            ]),
            .submenu("Sort By", children: [
                .action("Name", isOn: folderSortMode == .name) {
                    TileStore.shared.setFolderSortMode(tileID: tile.id, folderURL: folder.url, mode: .name)
                },
                .action("Date Modified", isOn: folderSortMode == .dateModified) {
                    TileStore.shared.setFolderSortMode(tileID: tile.id, folderURL: folder.url, mode: .dateModified)
                }
            ])
        ]
    }

    private var folderDisplayMode: FolderTileDisplayMode {
        guard case .folder(let folder) = tile.content else {
            return .contents
        }
        return TileStore.shared.folderDisplayMode(tileID: tile.id, folderURL: folder.url)
    }

    private var folderContentViewMode: FolderTileContentViewMode {
        guard case .folder(let folder) = tile.content else {
            return .grid
        }

        return TileStore.shared.folderContentViewMode(tileID: tile.id, folderURL: folder.url)
    }

    private var appFolderContentViewMode: FolderTileContentViewMode {
        guard case .appFolder = tile.content else {
            return .grid
        }

        return TileStore.shared.appFolderContentViewMode(tileID: tile.id)
    }

    private var folderSortMode: FolderTileSortMode {
        guard case .folder(let folder) = tile.content else {
            return .dateModified
        }

        return TileStore.shared.folderSortMode(tileID: tile.id, folderURL: folder.url)
    }

    private var customDockyTileActions: [ContextAction] {
        guard isDockyPinnedTile || isDockyTrailingTile else {
            return []
        }

        var actions: [ContextAction] = [
            .action("Edit Dock...") {
                DockEditModeService.shared.enter()
            }
        ]

        if case .spacer = tile.content {
            actions.append(.divider)
            actions.append(.action("Remove from Dock") {
                removeDockyTile()
            })
        }

        if case .divider = tile.content {
            actions.append(.divider)
            actions.append(.action("Remove from Dock") {
                removeDockyTile()
            })
        }

        if case .widget = tile.content {
            actions.append(.divider)
            actions.append(.action("Remove from Dock") {
                removeDockyTile()
            })
        }

        if case .smartStack = tile.content {
            actions.append(.divider)
            actions.append(.action("Remove from Dock") {
                removeDockyTile()
            })
        }

        if case .appFolder = tile.content {
            actions.append(.divider)
            actions.append(.submenu("View Content as", children: [
                .action("Grid", isOn: appFolderContentViewMode == .grid) {
                    TileStore.shared.setAppFolderContentViewMode(tileID: tile.id, mode: .grid)
                },
                .action("List", isOn: appFolderContentViewMode == .list) {
                    TileStore.shared.setAppFolderContentViewMode(tileID: tile.id, mode: .list)
                },
                .action("Inline", isOn: appFolderContentViewMode == .inline) {
                    TileStore.shared.setAppFolderContentViewMode(tileID: tile.id, mode: .inline)
                }
            ]))
            actions.append(.divider)
            actions.append(.action("Rename Folder...") {
                TileStore.shared.presentRenameAppFolderPrompt(tileID: tile.id)
            })
            actions.append(.action("Ungroup Folder") {
                TileStore.shared.ungroupAppFolder(tileID: tile.id)
            })
        }

        if case .launchpad = tile.content {
            actions.append(.divider)
            actions.append(.action("Remove from Dock") {
                removeDockyTile()
            })
        }

        return actions
    }

    private var isDockyPinnedTile: Bool {
        tile.id.hasPrefix("pinned:")
    }

    private var isDockyTrailingTile: Bool {
        tile.id.hasPrefix("trailing:")
    }

    private func removeDockyTile() {
        if isDockyPinnedTile {
            TileStore.shared.removePinnedItem(tileID: tile.id)
        } else if isDockyTrailingTile {
            TileStore.shared.removeTrailingItem(tileID: tile.id)
        }
    }

    private var lockedProductFeature: ProductFeature? {
        if case .app(let app) = tile.content,
           let displayedWidget = app.displayedWidget,
           product.availability(for: displayedWidget.kind.productFeature, context: .existingPlacement) == .lockedExisting {
            return displayedWidget.kind.productFeature
        }

        switch tile.content {
        case .launchpad:
            let feature = ProductFeature.launchpad
            return product.availability(for: feature, context: .existingPlacement) == .lockedExisting ? feature : nil
        case .widget(let widget):
            let feature = widget.kind.productFeature
            return product.availability(for: feature, context: .existingPlacement) == .lockedExisting ? feature : nil
        case .smartStack:
            let feature = ProductFeature.smartStack
            return product.availability(for: feature, context: .existingPlacement) == .lockedExisting ? feature : nil
        case .app, .minimizedWindow, .appFolder, .folder, .spacer, .divider, .trash:
            return nil
        }
    }

    private var isLockedProductPlacement: Bool {
        lockedProductFeature != nil
    }

    private func lockedContextActions() -> [ContextAction] {
        var actions: [ContextAction] = [
            .action("Unlock Docky Pro") {
                openProductSettings()
            }
        ]

        switch tile.content {
        case .app(let app) where app.displayedWidget != nil:
            actions.append(.divider)
            actions.append(.action("Show App Icon") {
                TileStore.shared.removeAppWidgetDisplay(bundleIdentifier: app.bundleIdentifier)
            })
        case .launchpad, .widget, .smartStack:
            if isDockyPinnedTile || isDockyTrailingTile {
                actions.append(.divider)
                actions.append(.action("Remove from Dock") {
                    removeDockyTile()
                })
            }
        case .app, .minimizedWindow, .appFolder, .folder, .spacer, .divider, .trash:
            break
        }

        return actions
    }

    private func openProductSettings() {
        (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
    }

    var body: some View {
        laidOutContent
            .opacity(isLockedProductPlacement ? 0.38 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .overlay(alignment: runningIndicatorAlignment) {
                runningIndicator
                    .padding(runningIndicatorEdge, runningIndicatorInset)
                    .offset(y: -max((layout.scaled(preferences.tileVerticalPadding) / 2), 2))
            }
            .overlay {
                if isLockedProductPlacement {
                    LockedProductTileOverlay()
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if isExternalFileDropTargeted {
                    laidOutContent
                        .disabled(true)
                        .colorMultiply(.black.opacity(0.25))
                }
            }
            .contentShape(Rectangle())
            .onHover(perform: updateHoverState)
            .onTapGesture(perform: handleTap)
            .onDisappear {
                isHovering = false
                isTooltipPresented = false
                isFolderPopoverPresented = false
                isFolderListMenuPresented = false
                isAppFolderPopoverPresented = false
                isAppFolderListMenuPresented = false
                isContextMenuPresented = false
            }
            .onChange(of: isFolderPopoverPresented) { _, isPresented in
                updateTooltipPresentation()
                guard !isPresented else { return }
                lastFolderPopoverDismissedAt = Date.timeIntervalSinceReferenceDate
            }
            .onChange(of: isFolderListMenuPresented) { _, _ in
                updateTooltipPresentation()
            }
            .onChange(of: isAppFolderListMenuPresented) { _, _ in
                updateTooltipPresentation()
            }
            .background {
                ContextActionMenuPresenter(
                    actionProvider: contextActions(modifierFlags:),
                    preferredEdge: inwardMenuEdge,
                    onPresentationChanged: updateContextMenuPresentation
                )

                if let tooltipTitle {
                    TileTooltipPopoverPresenter(
                        title: tooltipTitle,
                        isPresented: isTooltipPresented,
                        preferredEdge: inwardPopoverEdge
                    )
                    .allowsHitTesting(false)
                }

                if case .folder(let folder) = tile.content {
                    if folderContentViewMode == .list {
                        FolderListMenuPresenter(
                            tile: FolderTile(
                                url: folder.url,
                                displayName: folder.displayName,
                                displayMode: folderDisplayMode,
                                contentViewMode: folderContentViewMode,
                                sortMode: folderSortMode
                            ),
                            isPresented: $isFolderListMenuPresented,
                            preferredEdge: inwardPopoverEdge
                        )
                    } else {
                        FolderPopoverPresenter(
                            tile: FolderTile(
                                url: folder.url,
                                displayName: folder.displayName,
                                displayMode: folderDisplayMode,
                                contentViewMode: folderContentViewMode,
                                sortMode: folderSortMode
                            ),
                            initialSnapshot: folderSnapshot,
                            isPresented: $isFolderPopoverPresented,
                            preferredEdge: inwardPopoverEdge
                        )
                    }
                }

                if case .appFolder(let folder) = tile.content {
                    let presentedFolder = AppFolderTile(
                        identifier: folder.identifier,
                        displayName: folder.displayName,
                        apps: folder.apps,
                        contentViewMode: appFolderContentViewMode
                    )

                    if appFolderContentViewMode == .list {
                        AppFolderListMenuPresenter(
                            tile: presentedFolder,
                            isPresented: $isAppFolderListMenuPresented,
                            preferredEdge: inwardPopoverEdge
                        )
                    } else if appFolderContentViewMode == .grid {
                        AppFolderPopoverPresenter(
                            tile: presentedFolder,
                            isPresented: $isAppFolderPopoverPresented,
                            preferredEdge: inwardPopoverEdge
                        )
                    }
                }
            }
    }

    @ViewBuilder
    private var laidOutContent: some View {
        switch tile.content {
        case .app(let app) where app.displayedWidget != nil:
            GeometryReader { proxy in
                displayedContent
                    .frame(
                        width: max(0, proxy.size.width - contentInsets.width * 2),
                        height: max(0, proxy.size.height - contentInsets.height * 2)
                    )
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        case .appFolder, .launchpad, .widget, .smartStack:
            GeometryReader { proxy in
                displayedContent
                    .frame(
                        width: max(0, proxy.size.width - contentInsets.width * 2),
                        height: max(0, proxy.size.height - contentInsets.height * 2)
                    )
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        case .folder, .trash:
            GeometryReader { _ in
                displayedContent
                    .padding(contentPaddingEdges, contentPadding)
            }
        case .app, .minimizedWindow, .spacer, .divider:
            displayedContent
                .padding(contentPaddingEdges, contentPadding)
        }
    }

    private var displayedContent: some View {
        content
            .allowsHitTesting(!isLockedProductPlacement)
    }

    @ViewBuilder
    private var runningIndicator: some View {
        if showsRunningIndicator {
            switch preferences.activeIndicatorShape {
            case .none:
                EmptyView()
            case .dot, .pill:
                runningIndicatorShape
                    .frame(width: runningIndicatorSize.width, height: runningIndicatorSize.height)
                    .foregroundStyle(Color(nsColor: preferences.effectiveActiveIndicatorColor).opacity(0.9))
            case .image:
                if let runningIndicatorImage {
                    Image(nsImage: runningIndicatorImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: runningIndicatorSize.width,
                            maxHeight: runningIndicatorSize.height
                        )
                }
            }
        }
    }

    private var showsRunningIndicator: Bool {
        switch tile.content {
        case .app(let app):
            workspace.isRunning(bundleIdentifier: app.bundleIdentifier)
        case .minimizedWindow:
            false
        case .appFolder(let folder):
            folder.apps.contains { app in
                workspace.isRunning(bundleIdentifier: app.bundleIdentifier)
            }
        case .launchpad, .widget, .smartStack, .folder, .spacer, .divider, .trash:
            false
        }
    }

    @ViewBuilder
    private var runningIndicatorShape: some View {
        switch preferences.activeIndicatorShape {
        case .none, .image:
            EmptyView()
        case .dot:
            Circle()
        case .pill:
            Capsule()
        }
    }

    private var runningIndicatorSize: CGSize {
        switch preferences.activeIndicatorShape {
        case .none:
            .zero
        case .dot:
            CGSize(width: runningIndicatorThickness, height: runningIndicatorThickness)
        case .pill:
            if position.isVertical {
                CGSize(width: runningIndicatorThickness, height: runningIndicatorLength)
            } else {
                CGSize(width: runningIndicatorLength, height: runningIndicatorThickness)
            }
        case .image:
            if position.isVertical {
                CGSize(width: runningIndicatorImageThickness, height: runningIndicatorImageLength)
            } else {
                CGSize(width: runningIndicatorImageLength, height: runningIndicatorImageThickness)
            }
        }
    }

    private var runningIndicatorThickness: CGFloat {
        4 * runningIndicatorScale
    }

    private var runningIndicatorLength: CGFloat {
        12 * runningIndicatorScale
    }

    private var runningIndicatorImageThickness: CGFloat {
        10 * runningIndicatorScale
    }

    private var runningIndicatorImageLength: CGFloat {
        20 * runningIndicatorScale
    }

    private var runningIndicatorInset: CGFloat {
        max(1, round(2 * runningIndicatorScale))
    }

    private var runningIndicatorScale: CGFloat {
        max(0.5, min(1, effectiveTileSize / 48))
    }

    private var runningIndicatorImage: NSImage? {
        guard let url = preferences.effectiveActiveIndicatorImageURL else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    private var contentPadding: CGFloat {
        switch tile.content {
        case .divider:
            0
        default:
            layout.scaled(preferences.tileVerticalPadding)
        }
    }

    private var contentPaddingEdges: Edge.Set {
        position.isVertical ? .horizontal : .vertical
    }

    private var nonAppContentPadding: CGFloat {
        switch tile.content {
        case .app(let app) where app.displayedWidget != nil:
            tileChromeInset
        case .appFolder, .widget, .smartStack, .folder, .trash:
            tileChromeInset
        case .app, .launchpad, .minimizedWindow, .spacer, .divider:
            0
        }
    }

    private var tileChromeInset: CGFloat {
        floor(effectiveTileSize * 3 / 32)
    }

    private var contentInsets: CGSize {
        CGSize(
            width: nonAppContentPadding + (position.isVertical ? contentPadding : 0),
            height: nonAppContentPadding + (position.isVertical ? 0 : contentPadding)
        )
    }

    private var effectiveTileSize: CGFloat {
        layout.scaled(dockSettings.magnification ? dockSettings.largeSize : dockSettings.tileSize)
    }

    private func renderedWidgetSpan(for span: TileSpan) -> TileSpan {
        if layout.compactsWidgetsForOverflow || position.isVertical || effectiveTileSize < 50 {
            return .one
        }

        return span
    }

    private var availableWidgetSpans: [TileSpan] {
        position.isVertical ? [.one] : TileSpan.allCases
    }

    private var nonAppTileCornerRadius: CGFloat {
        let maximumCornerRadius = max(0, (effectiveTileSize - nonAppContentPadding * 2) / 2)
        return preferences.tileClipShape.resolvedCornerRadius(
            base: effectiveTileSize * 0.225,
            maximum: maximumCornerRadius
        )
    }

    private var position: ResolvedDockWindowPosition {
        preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
    }

    private var runningIndicatorAlignment: Alignment {
        switch position {
        case .top:
            .top
        case .left:
            .leading
        case .right:
            .trailing
        case .bottom:
            .bottom
        }
    }

    private var runningIndicatorEdge: Edge.Set {
        switch position {
        case .top:
            .top
        case .left:
            .leading
        case .right:
            .trailing
        case .bottom:
            .bottom
        }
    }

    private var inwardPopoverEdge: NSRectEdge {
        switch position {
        case .top:
            .minY
        case .left:
            .maxX
        case .right:
            .minX
        case .bottom:
            .maxY
        }
    }

    private var inwardMenuEdge: NSRectEdge {
        inwardPopoverEdge
    }

    @ViewBuilder
    private var content: some View {
        switch tile.content {
        case .app(let app):
            if let displayedWidget = app.displayedWidget {
                WidgetTileView(
                    tile: displayedWidget,
                    cornerRadius: nonAppTileCornerRadius,
                    renderedSpan: renderedWidgetSpan(for: displayedWidget.effectiveSpan),
                    isWithinStack: false
                )
            } else {
                AppTileView(
                    tile: app,
                    clipShape: preferences.tileClipShape,
                    transparencyCompensationInset: tileChromeInset
                )
            }
        case .minimizedWindow(let window):
            MinimizedWindowTileView(tile: window)
        case .appFolder(let folder):
            AppFolderTileView(
                tile: folder,
                cornerRadius: nonAppTileCornerRadius,
                suppressesGroupedOpenedBackdrop: isDragging
            )
        case .launchpad(let launchpad):
            AppTileView(
                tile: AppTile(
                    bundleIdentifier: LaunchpadTile.spotlightBundleIdentifier,
                    displayName: launchpad.title
                ),
                clipShape: preferences.tileClipShape,
                transparencyCompensationInset: 0
            )
        case .widget(let widget):
            WidgetTileView(
                tile: widget,
                cornerRadius: nonAppTileCornerRadius,
                renderedSpan: renderedWidgetSpan(for: widget.effectiveSpan),
                isWithinStack: false
            )
        case .smartStack(let stack):
            SmartStackTileView(
                tile: stack,
                cornerRadius: nonAppTileCornerRadius,
                renderedSpan: renderedWidgetSpan(for: stack.span)
            )
        case .folder(let folder):
            FolderTileView(
                tile: FolderTile(
                    url: folder.url,
                    displayName: folder.displayName,
                    displayMode: folderDisplayMode,
                    contentViewMode: folderContentViewMode,
                    sortMode: folderSortMode
                ),
                isOpen: isFolderPopoverPresented,
            )
        case .spacer:
            SpacerTileView()
        case .divider:
            DividerTileView(tileID: tile.id)
        case .trash:
            TrashTileView()
        }
    }

    private var tooltipTitle: String? {
        switch tile.content {
        case .app(let app):
            app.displayName
        case .minimizedWindow(let window):
            window.windowTitle
        case .appFolder(let folder):
            folder.displayName
        case .launchpad(let launchpad):
            launchpad.title
        case .widget(let widget):
            widget.title
        case .smartStack(let stack):
            stack.title
        case .folder(let folder):
            folder.displayName
        case .trash:
            "Trash"
        case .spacer, .divider:
            nil
        }
    }

    private func updateHoverState(isHovering: Bool) {
        self.isHovering = isHovering
        updateTooltipPresentation()
    }

    private func updateContextMenuPresentation(isPresented: Bool) {
        isContextMenuPresented = isPresented
        updateTooltipPresentation()
    }

    private func updateTooltipPresentation() {
        isTooltipPresented = isHovering
            && tooltipTitle != nil
            && !isFolderPopoverPresented
            && !isFolderListMenuPresented
            && !isAppFolderPopoverPresented
            && !isAppFolderListMenuPresented
            && !isContextMenuPresented
    }

    private func handleTap() {
        if isLockedProductPlacement {
            isTooltipPresented = false
            openProductSettings()
            return
        }

        switch tile.content {
        case .app(let app):
            isTooltipPresented = false
            WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        case .minimizedWindow(let window):
            isTooltipPresented = false
            _ = WorkspaceService.shared.restoreMinimizedWindow(window)
        case .appFolder:
            isTooltipPresented = false

            if appFolderContentViewMode == .inline,
               case .appFolder(let folder) = tile.content {
                isAppFolderPopoverPresented = false
                isAppFolderListMenuPresented = false
                TileStore.shared.toggleInlineAppFolderExpansion(folderID: folder.identifier)
                return
            }

            if appFolderContentViewMode == .list {
                isAppFolderPopoverPresented = false
                guard !isAppFolderListMenuPresented else { return }
                isAppFolderListMenuPresented = true
                return
            }

            if isAppFolderPopoverPresented {
                isAppFolderPopoverPresented = false
                return
            }

            isAppFolderPopoverPresented = true
        case .launchpad:
            isTooltipPresented = false
            guard preferences.enablesLaunchpadOverlay else { return }
            LaunchpadOverlayService.shared.toggle()
        case .widget(let widget):
            isTooltipPresented = false
            handleWidgetTap(widget)
        case .smartStack:
            isTooltipPresented = false
            return
        case .folder(let folder):
            isTooltipPresented = false

            if folderContentViewMode == .list {
                isFolderPopoverPresented = false
                guard !isFolderListMenuPresented else { return }
                isFolderListMenuPresented = true
                return
            }

            if isFolderPopoverPresented {
                isFolderPopoverPresented = false
                return
            }

            let now = Date.timeIntervalSinceReferenceDate
            guard now - lastFolderPopoverDismissedAt > Self.folderPopoverRetapGuardInterval else {
                return
            }

            folderSnapshot = FolderAccessService.shared.snapshot(of: folder.url)
            isFolderPopoverPresented = true
        case .trash:
            isTooltipPresented = false
            Task {
                _ = await AppleScriptService.shared.openTrash()
            }
        case .spacer, .divider:
            return
        }
    }

    private func appFolderContextActions(for folder: AppFolderTile) -> [ContextAction] {
        var actions = customDockyTileActions

        if !folder.apps.isEmpty {
            if !actions.isEmpty {
                actions.append(.divider)
            }
            actions.append(.action("Open All") {
                for app in folder.apps {
                    WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
                }
            })
        }

        let appActions = folder.apps.map { app in
            ContextAction.submenu(app.displayName, children: [
                .action("Open") {
                    WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
                },
                .action("Remove from Folder") {
                    TileStore.shared.removeAppFromFolder(tileID: tile.id, bundleIdentifier: app.bundleIdentifier)
                }
            ])
        }

        if !appActions.isEmpty {
            if !actions.isEmpty {
                actions.append(.divider)
            }
            actions.append(.submenu("Apps", children: appActions))
        }

        return actions
    }

    private func appContextActions(
        for app: AppTile,
        modifierFlags: NSEvent.ModifierFlags,
        baseActions: [ContextAction]? = nil
    ) -> [ContextAction] {
        guard !app.bundleIdentifier.isEmpty else {
            return []
        }

        let workspace = WorkspaceService.shared
        let windows = workspace.appWindows(bundleIdentifier: app.bundleIdentifier)
        let actions = if let baseActions {
            injectingDockyAppOptions(into: baseActions, for: app)
        } else {
            fallbackAppContextActions(for: app, modifierFlags: modifierFlags)
        }
        return injectingAppWindowActions(windows, into: actions)
    }

    private func injectingDockyAppOptions(into actions: [ContextAction], for app: AppTile) -> [ContextAction] {
        var dockyOptions: [ContextAction] = []

        if let showAsWidgetAction = showAsWidgetAction(for: app) {
            dockyOptions.append(showAsWidgetAction)
        }

        if let hideInDockyAction = hideInDockyAction(for: app) {
            if !dockyOptions.isEmpty {
                dockyOptions.append(.divider)
            }
            dockyOptions.append(hideInDockyAction)
        }

        guard !dockyOptions.isEmpty else {
            return actions
        }

        var result = actions
        if let optionsIndex = result.firstIndex(where: {
            $0.kind == .submenu && $0.title == "Options"
        }) {
            var children = result[optionsIndex].children
            if !children.isEmpty, children.last?.kind != .divider {
                children.append(.divider)
            }
            children.append(contentsOf: dockyOptions)
            result[optionsIndex] = .submenu("Options", children: children)
            return result
        }

        if !result.isEmpty, result.last?.kind != .divider {
            result.append(.divider)
        }
        result.append(.submenu("Options", children: dockyOptions))
        return result
    }

    private func fallbackAppContextActions(
        for app: AppTile,
        modifierFlags: NSEvent.ModifierFlags
    ) -> [ContextAction] {
        let workspace = WorkspaceService.shared
        let isRunning = workspace.isRunning(bundleIdentifier: app.bundleIdentifier)
        let isPinned = tile.id.hasPrefix("pinned:")
        let canTogglePinned = app.bundleIdentifier != Self.finderBundleIdentifier
        let useForceQuit = modifierFlags.contains(.option)
        var actions: [ContextAction] = [
            .action("Open") {
                workspace.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
            }
        ]

        if isRunning {
            actions.append(.action("Show All Windows") {
                workspace.showAllWindows(bundleIdentifier: app.bundleIdentifier)
            })
        }

        actions.append(.divider)
        actions.append(.submenu("Options", children: appOptionsActions(for: app, isPinned: isPinned, canTogglePinned: canTogglePinned)))

        if isDockyPinnedTile || isDockyTrailingTile {
            actions.append(.divider)
            actions.append(.action("Remove from Dock") {
                removeDockyTile()
            })
        }

        if isRunning && app.bundleIdentifier != Self.finderBundleIdentifier {
            actions.append(.divider)
            actions.append(.action("Hide") {
                workspace.hide(bundleIdentifier: app.bundleIdentifier)
            })
            actions.append(.action(
                useForceQuit ? "Force Quit" : "Quit",
                isDestructive: useForceQuit
            ) {
                workspace.quit(bundleIdentifier: app.bundleIdentifier, force: useForceQuit)
            })
        }

        return actions
    }

    private func injectingAppWindowActions(_ windows: [AppWindow], into actions: [ContextAction]) -> [ContextAction] {
        guard !windows.isEmpty else {
            return actions
        }

        let windowActions = windows.map { window in
            ContextAction.action(appWindowMenuTitle(for: window)) {
                _ = WorkspaceService.shared.focus(window: window)
            }
        }

        var result = actions
        var insertionIndex = result.firstIndex { action in
            action.kind == .submenu && action.title == "Options"
        } ?? result.endIndex

        if insertionIndex > result.startIndex, result[insertionIndex - 1].kind != .divider {
            result.insert(.divider, at: insertionIndex)
            insertionIndex += 1
        }

        result.insert(contentsOf: windowActions, at: insertionIndex)

        let trailingDividerIndex = min(insertionIndex + windowActions.count, result.endIndex)
        if trailingDividerIndex < result.endIndex, result[trailingDividerIndex].kind != .divider {
            result.insert(.divider, at: trailingDividerIndex)
        }

        while result.first?.kind == .divider {
            result.removeFirst()
        }

        while result.last?.kind == .divider {
            result.removeLast()
        }

        return result.enumerated().compactMap { index, action in
            if action.kind == .divider,
               index > 0,
               result[index - 1].kind == .divider {
                return nil
            }

            return action
        }
    }

    private func appWindowMenuTitle(for window: AppWindow) -> String {
        guard window.isMinimized else {
            return window.windowTitle
        }

        return "\(window.windowTitle) (Minimized)"
    }

    private func minimizedWindowContextActions(
        for window: MinimizedWindowTile,
        modifierFlags _: NSEvent.ModifierFlags
    ) -> [ContextAction] {
        let workspace = WorkspaceService.shared
        return [
            .action("Restore Window") {
                _ = workspace.restoreMinimizedWindow(window)
            },
            .action("Close Window") {
                _ = workspace.closeMinimizedWindow(window)
            }
        ]
    }

    private func appOptionsActions(
        for app: AppTile,
        isPinned: Bool,
        canTogglePinned: Bool
    ) -> [ContextAction] {
        var actions: [ContextAction] = []

        if canTogglePinned {
            actions.append(.action("Keep in Dock", isOn: isPinned) {
                _ = TileStore.shared.setPinnedApp(
                    bundleIdentifier: app.bundleIdentifier,
                    pinned: !isPinned
                )
            })
        }

        if let showAsWidgetAction = showAsWidgetAction(for: app) {
            actions.append(showAsWidgetAction)
        }

        if let hideInDockyAction = hideInDockyAction(for: app) {
            actions.append(hideInDockyAction)
        }

        actions.append(.action("Show in Finder") {
            WorkspaceService.shared.revealApplicationInFinder(bundleIdentifier: app.bundleIdentifier)
        })

        return actions
    }

    private func hideInDockyAction(for app: AppTile) -> ContextAction? {
        guard app.bundleIdentifier != Self.finderBundleIdentifier,
              !preferences.isAppHiddenInDocky(bundleIdentifier: app.bundleIdentifier) else {
            return nil
        }

        return .action("Hide in Docky") {
            preferences.setAppHiddenInDocky(bundleIdentifier: app.bundleIdentifier, isHidden: true)
        }
    }

    private func showAsWidgetAction(for app: AppTile) -> ContextAction? {
        guard !TileStore.shared.isAppInFolder(bundleIdentifier: app.bundleIdentifier) else {
            return nil
        }

        let candidates = TileStore.shared.appWidgetCandidates(bundleIdentifier: app.bundleIdentifier)
        let configuredDisplay = TileStore.shared.appWidgetDisplay(bundleIdentifier: app.bundleIdentifier)
        let currentKind = configuredDisplay?.kind

        guard !candidates.isEmpty || currentKind != nil else {
            return nil
        }

        var actions: [ContextAction] = [
            .action("App Icon", isOn: currentKind == nil) {
                TileStore.shared.removeAppWidgetDisplay(bundleIdentifier: app.bundleIdentifier)
            }
        ]

        if !candidates.isEmpty {
            actions.append(.divider)
            actions.append(contentsOf: candidates.map { widget in
                .action(widget.title, isOn: currentKind == widget.kind) {
                    TileStore.shared.setAppWidgetDisplay(
                        bundleIdentifier: app.bundleIdentifier,
                        kind: widget.kind
                    )
                }
            })
        }

        if let configuredDisplay {
            let availableSpans = availableAppWidgetSpans(for: configuredDisplay.kind)
            if availableSpans.count > 1 {
                actions.append(.divider)
                actions.append(.submenu("Span", children: availableSpans.map { span in
                    .action(spanTitle(for: span), isOn: configuredDisplay.span == span) {
                        TileStore.shared.setAppWidgetDisplaySpan(
                            bundleIdentifier: app.bundleIdentifier,
                            span: span
                        )
                    }
                }))
            }
        }

        return .submenu("Show as Widget", children: actions)
    }

    private func widgetContextActions(for widget: WidgetTile) -> [ContextAction] {
        switch widget.kind {
        case .calendar:
            var actions: [ContextAction] = []

            if let quickJoinURL = CalendarService.shared.nextEvent?.quickJoinURL {
                actions.append(.action("Quick Join") {
                    NSWorkspace.shared.open(quickJoinURL)
                })
            }

            if let spanMenuAction = widgetSpanMenuAction(for: widget) {
                appendDividerIfNeeded(to: &actions)
                actions.append(spanMenuAction)
            }

            appendDividerIfNeeded(to: &actions)
            actions.append(.action("Refresh Calendar") {
                CalendarService.shared.refresh(force: true)
            })
            actions.append(.divider)
            actions.append(.action("Open Calendar") {
                WorkspaceService.shared.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.calendar)
            })
            actions.append(.divider)
            actions.append(widgetRemovalAction(for: widget))
            return actions
        case .calendarDate:
            return [
                .action("Open Calendar") {
                    WorkspaceService.shared.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.calendar)
                },
                .divider,
                widgetRemovalAction(for: widget)
            ]
        case .reminders:
            var actions: [ContextAction] = []

            let completionActions = RemindersService.shared.snapshot?.completionCandidates.map { item in
                ContextAction.action(reminderCompletionTitle(for: item, now: Date())) {
                    Task {
                        _ = await RemindersService.shared.completeReminder(identifier: item.identifier)
                    }
                }
            } ?? []

            if !completionActions.isEmpty {
                actions.append(.submenu("Complete", children: completionActions))
            }

            if let spanMenuAction = widgetSpanMenuAction(for: widget) {
                appendDividerIfNeeded(to: &actions)
                actions.append(spanMenuAction)
            }

            appendDividerIfNeeded(to: &actions)
            actions.append(.action("Refresh Reminders") {
                RemindersService.shared.refresh(force: true)
            })
            actions.append(.divider)
            actions.append(.action("Open Reminders") {
                WorkspaceService.shared.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.reminders)
            })
            actions.append(.divider)
            actions.append(widgetRemovalAction(for: widget))
            return actions
        case .batteries:
            var actions: [ContextAction] = [
                .action("Refresh Batteries") {
                    BatteriesService.shared.refresh(force: true)
                }
            ]

            if let spanMenuAction = widgetSpanMenuAction(for: widget) {
                actions.append(.divider)
                actions.append(spanMenuAction)
            }

            actions.append(.divider)
            actions.append(.action("Open Battery Settings") {
                BatteriesService.shared.openInBatterySettings()
            })
            actions.append(.divider)
            actions.append(widgetRemovalAction(for: widget))
            return actions
        case .systemStatus:
            var actions: [ContextAction] = [
                .action("Refresh Status") {
                    SystemStatusService.shared.refresh(force: true)
                }
            ]

            if let spanMenuAction = widgetSpanMenuAction(for: widget) {
                actions.append(.divider)
                actions.append(spanMenuAction)
            }

            actions.append(.divider)
            actions.append(.action("Open Activity Monitor") {
                SystemStatusService.shared.openInActivityMonitor()
            })
            actions.append(.divider)
            actions.append(widgetRemovalAction(for: widget))
            return actions
        case .nowPlaying:
            var actions: [ContextAction] = []

            if let bundleIdentifier = mediaPlayback.resolvedBundleIdentifier(for: widget.ownerBundleIdentifier) {
                actions.append(.action("Open App") {
                    WorkspaceService.shared.activateOrOpen(bundleIdentifier: bundleIdentifier)
                })
                actions.append(.divider)
            }

            actions.append(contentsOf: [
                .action("Play/Pause") {
                    Task {
                        await mediaPlayback.togglePlayPause(for: widget.ownerBundleIdentifier)
                    }
                },
                .action("Previous Track") {
                    Task {
                        await mediaPlayback.skipToPrevious(for: widget.ownerBundleIdentifier)
                    }
                },
                .action("Next Track") {
                    Task {
                        await mediaPlayback.skipToNext(for: widget.ownerBundleIdentifier)
                    }
                },
            ])

            if let playbackState = mediaPlayback.state(for: widget.ownerBundleIdentifier), playbackState.supportsFavorite {
                actions.append(.action(playbackState.isFavorite ? "Unfavorite" : "Favorite") {
                    Task {
                        await mediaPlayback.setFavorite(!playbackState.isFavorite, for: widget.ownerBundleIdentifier)
                    }
                })
            }

            if let spanMenuAction = widgetSpanMenuAction(for: widget) {
                actions.append(.divider)
                actions.append(spanMenuAction)
            }

            actions.append(.divider)
            actions.append(widgetRemovalAction(for: widget, nonDockyTitle: "Remove Stack"))
            return actions
        case .weather:
            var actions: [ContextAction] = [
                .action("Refresh Weather") {
                    WeatherService.shared.refresh(force: true)
                }
            ]

            if let spanMenuAction = widgetSpanMenuAction(for: widget) {
                actions.append(.divider)
                actions.append(spanMenuAction)
            }

            actions.append(.divider)
            actions.append(.action("Open Weather") {
                WeatherService.shared.openInWeatherApp()
            })
            actions.append(.divider)
            actions.append(widgetRemovalAction(for: widget))
            return actions
        }
    }

    private func widgetSpanMenuAction(for widget: WidgetTile) -> ContextAction? {
        guard isDockyPinnedTile || isDockyTrailingTile else {
            return nil
        }

        let availableSpans = availableWidgetSpans(for: widget)
        guard availableSpans.count > 1 else {
            return nil
        }

        return .submenu("Span", children: availableSpans.map { span in
            ContextAction.action(spanTitle(for: span), isOn: widget.span == span) {
                applyWidgetSpan(span)
            }
        })
    }

    private func availableWidgetSpans(for widget: WidgetTile) -> [TileSpan] {
        if position.isVertical {
            return [.one]
        }

        return widget.kind.supportedSpans
    }

    private func availableAppWidgetSpans(for kind: WidgetKind) -> [TileSpan] {
        if position.isVertical {
            return [.one]
        }

        return kind.supportedSpans
    }

    private func applyWidgetSpan(_ span: TileSpan) {
        if isDockyPinnedTile {
            TileStore.shared.setPinnedWidgetSpan(tileID: tile.id, span: span)
        } else if isDockyTrailingTile {
            TileStore.shared.setTrailingWidgetSpan(tileID: tile.id, span: span)
        }
    }

    private func widgetRemovalAction(for widget: WidgetTile, nonDockyTitle: String = "Remove Widget") -> ContextAction {
        if isDockyPinnedTile || isDockyTrailingTile {
            return .action("Remove from Dock") {
                removeDockyTile()
            }
        }

        return .action(nonDockyTitle) {
            TileStore.shared.removeWidget(
                kind: widget.kind,
                ownerBundleIdentifier: widget.ownerBundleIdentifier
            )
        }
    }

    private func appendDividerIfNeeded(to actions: inout [ContextAction]) {
        guard !actions.isEmpty, actions.last?.kind != .divider else {
            return
        }

        actions.append(.divider)
    }

    private func reminderCompletionTitle(for item: ReminderItemSnapshot, now: Date) -> String {
        let detail = reminderCompletionDetail(for: item, now: now)
        return detail.isEmpty ? item.title : "\(item.title) - \(detail)"
    }

    private func reminderCompletionDetail(for item: ReminderItemSnapshot, now: Date) -> String {
        switch item.timingCategory(relativeTo: now) {
        case .overdue:
            return "overdue"
        case .today:
            return "today"
        case .upcoming:
            return "upcoming"
        case .unscheduled:
            return item.listTitle
        }
    }

    private func smartStackContextActions(for stack: SmartStackTile) -> [ContextAction] {
        var actions: [ContextAction] = []
        let widgetVisibilityActions = TileStore.shared.smartStackWidgetCandidates(tileID: tile.id).map { widget in
            ContextAction.action(
                widget.title,
                isOn: TileStore.shared.isSmartStackWidgetVisible(
                    tileID: tile.id,
                    ownerBundleIdentifier: widget.ownerBundleIdentifier
                )
            ) {
                let isVisible = TileStore.shared.isSmartStackWidgetVisible(
                    tileID: tile.id,
                    ownerBundleIdentifier: widget.ownerBundleIdentifier
                )
                TileStore.shared.setSmartStackWidgetVisibility(
                    tileID: tile.id,
                    ownerBundleIdentifier: widget.ownerBundleIdentifier,
                    isVisible: !isVisible
                )
            }
        }

        if !widgetVisibilityActions.isEmpty {
            actions.append(.submenu("Widgets", children: widgetVisibilityActions))
        }

        if isDockyPinnedTile || isDockyTrailingTile {
            if !actions.isEmpty {
                actions.append(.divider)
            }
            actions.append(.action("Edit Dock...") {
                DockEditModeService.shared.enter()
            })
            actions.append(.action("Remove from Dock") {
                removeDockyTile()
            })
        }

        return actions
    }
    private func handleWidgetTap(_ widget: WidgetTile) {
        switch widget.kind {
        case .calendar:
            WorkspaceService.shared.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.calendar)
        case .calendarDate:
            WorkspaceService.shared.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.calendar)
        case .reminders:
            WorkspaceService.shared.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.reminders)
        case .batteries:
            BatteriesService.shared.openInBatterySettings()
        case .systemStatus:
            SystemStatusService.shared.openInActivityMonitor()
        case .nowPlaying:
            Task {
                await mediaPlayback.togglePlayPause(for: widget.ownerBundleIdentifier)
            }
        case .weather:
            WeatherService.shared.openInWeatherApp()
        }
    }

    private func spanTitle(for span: TileSpan) -> String {
        switch span {
        case .one:
            "1 Tile"
        case .two:
            "2 Tiles"
        case .three:
            "3 Tiles"
        }
    }

}

private struct LockedProductTileOverlay: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.callout.weight(.semibold))
            Text("Pro")
                .font(.caption.weight(.semibold))
                .offset(y: 1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.62), in: .capsule)
    }
}

private struct TileTooltipView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .fixedSize()
    }
}

private struct TileTooltipPopoverPresenter: NSViewRepresentable {
    let title: String
    let isPresented: Bool
    let preferredEdge: NSRectEdge

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title, preferredEdge: preferredEdge)
    }

    func makeNSView(context: Context) -> TooltipAnchorView {
        TooltipAnchorView()
    }

    func updateNSView(_ nsView: TooltipAnchorView, context: Context) {
        context.coordinator.update(title: title, preferredEdge: preferredEdge)

        if isPresented {
            context.coordinator.show(relativeTo: nsView)
        } else {
            context.coordinator.close()
        }
    }

    static func dismantleNSView(_ nsView: TooltipAnchorView, coordinator: Coordinator) {
        coordinator.close()
    }

    final class Coordinator {
        private let hostingController = NSHostingController(rootView: TileTooltipView(title: ""))
        private let popover = NSPopover()
        private var preferredEdge: NSRectEdge

        init(title: String, preferredEdge: NSRectEdge) {
            self.preferredEdge = preferredEdge
            hostingController.rootView = TileTooltipView(title: title)
            popover.contentViewController = hostingController
            popover.animates = false
            popover.behavior = .applicationDefined
            updateContentSize()
        }

        func update(title: String, preferredEdge: NSRectEdge) {
            self.preferredEdge = preferredEdge
            hostingController.rootView = TileTooltipView(title: title)
            updateContentSize()
        }

        func show(relativeTo view: NSView) {
            guard view.window != nil, !popover.isShown else { return }
            let anchorRect = anchorRect(in: view.bounds)
            popover.show(relativeTo: anchorRect, of: view, preferredEdge: preferredEdge)
        }

        func close() {
            popover.performClose(nil)
        }

        private func updateContentSize() {
            let view = hostingController.view
            view.layoutSubtreeIfNeeded()
            let size = view.fittingSize
            hostingController.preferredContentSize = size
            popover.contentSize = size
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

private final class TooltipAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct FolderListMenuPresenter: NSViewRepresentable {
    let tile: FolderTile
    @Binding var isPresented: Bool
    let preferredEdge: NSRectEdge

    func makeCoordinator() -> Coordinator {
        Coordinator(tile: tile, isPresented: $isPresented, preferredEdge: preferredEdge)
    }

    func makeNSView(context: Context) -> FolderListMenuAnchorView {
        FolderListMenuAnchorView()
    }

    func updateNSView(_ nsView: FolderListMenuAnchorView, context: Context) {
        context.coordinator.update(tile: tile, isPresented: $isPresented, preferredEdge: preferredEdge)

        if isPresented {
            DispatchQueue.main.async {
                context.coordinator.show(relativeTo: nsView)
            }
        } else {
            context.coordinator.close()
        }
    }

    static func dismantleNSView(_ nsView: FolderListMenuAnchorView, coordinator: Coordinator) {
        coordinator.close()
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        private var tile: FolderTile
        private var isPresented: Binding<Bool>
        private var preferredEdge: NSRectEdge
        private weak var anchorView: NSView?
        private var isShowing = false
        private var isInterruptingAutohide = false
        private var folderURLByMenuID: [ObjectIdentifier: URL] = [:]

        init(tile: FolderTile, isPresented: Binding<Bool>, preferredEdge: NSRectEdge) {
            self.tile = tile
            self.isPresented = isPresented
            self.preferredEdge = preferredEdge
            super.init()
        }

        func update(tile: FolderTile, isPresented: Binding<Bool>, preferredEdge: NSRectEdge) {
            self.tile = tile
            self.isPresented = isPresented
            self.preferredEdge = preferredEdge
        }

        func show(relativeTo view: NSView) {
            guard view.window != nil, !isShowing else { return }

            anchorView = view
            isShowing = true
            beginAutohideInterruption(for: view)
            folderURLByMenuID.removeAll()
            let menu = buildMenu(for: tile.url, title: tile.displayName)
            popUp(menu: menu, in: view)
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
            folderURLByMenuID.removeAll()
        }

        private func buildMenu(for folderURL: URL, title: String) -> NSMenu {
            let menu = NSMenu(title: title)
            populate(menu: menu, for: folderURL)
            return menu
        }

        private func populate(menu: NSMenu, for folderURL: URL) {
            menu.removeAllItems()

            switch FolderAccessService.shared.snapshot(of: folderURL) {
            case .loaded(let itemURLs):
                let sortedItemURLs = FolderAccessService.shared.sortedItems(in: itemURLs, sortMode: tile.sortMode)
                if sortedItemURLs.isEmpty {
                    let emptyItem = NSMenuItem(title: "No visible items", action: nil, keyEquivalent: "")
                    emptyItem.isEnabled = false
                    menu.addItem(emptyItem)
                } else {
                    for itemURL in sortedItemURLs {
                        menu.addItem(menuItem(for: itemURL))
                    }
                }
            case .unreadable:
                let unreadableItem = NSMenuItem(title: "Can't read folder contents", action: nil, keyEquivalent: "")
                unreadableItem.isEnabled = false
                menu.addItem(unreadableItem)
            }

            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }

            let openInFinderItem = NSMenuItem(title: "Open in Finder", action: #selector(openInFinder(_:)), keyEquivalent: "")
            openInFinderItem.target = self
            openInFinderItem.representedObject = folderURL
            menu.addItem(openInFinderItem)
        }

        private func menuItem(for itemURL: URL) -> NSMenuItem {
            let item = NSMenuItem(title: displayName(for: itemURL), action: nil, keyEquivalent: "")
            item.image = listMenuIcon(for: itemURL)

            if isNavigableFolder(itemURL) {
                let submenu = NSMenu(title: item.title)
                submenu.delegate = self
                folderURLByMenuID[ObjectIdentifier(submenu)] = itemURL
                item.submenu = submenu
            } else {
                item.action = #selector(openFile(_:))
                item.target = self
                item.representedObject = itemURL
            }

            return item
        }

        private func listMenuIcon(for itemURL: URL) -> NSImage {
            let icon = IconCacheService.shared.icon(forFileURL: itemURL).copy() as? NSImage
                ?? IconCacheService.shared.icon(forFileURL: itemURL)
            icon.size = NSSize(width: 16, height: 16)
            return icon
        }

        @objc private func openFile(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            _ = NSWorkspace.shared.open(url)
        }

        @objc private func openInFinder(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            Task {
                _ = await AppleScriptService.shared.openFinderWindow(for: url)
            }
        }

        private func displayName(for itemURL: URL) -> String {
            (try? itemURL.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? itemURL.lastPathComponent
        }

        private func isNavigableFolder(_ itemURL: URL) -> Bool {
            let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return values?.isDirectory == true && values?.isPackage != true
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let folderURL = folderURLByMenuID[ObjectIdentifier(menu)] else { return }
            populate(menu: menu, for: folderURL)
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
            let anchorRect = view.bounds
            let anchor: NSPoint
            switch preferredEdge {
            case .minX:
                anchor = NSPoint(x: anchorRect.minX, y: anchorRect.midY)
            case .maxX:
                anchor = NSPoint(x: anchorRect.maxX, y: anchorRect.midY)
            case .minY:
                anchor = NSPoint(x: anchorRect.midX - menu.size.width / 2, y: anchorRect.minY)
            case .maxY:
                anchor = NSPoint(x: anchorRect.midX - menu.size.width / 2, y: anchorRect.maxY)
            @unknown default:
                anchor = NSPoint(x: anchorRect.midX - menu.size.width / 2, y: anchorRect.maxY)
            }

            menu.popUp(positioning: nil, at: anchor, in: view)
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

private final class FolderListMenuAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct FolderPopoverPresenter: NSViewRepresentable {
    let tile: FolderTile
    let initialSnapshot: FolderContentsSnapshot
    @Binding var isPresented: Bool
    let preferredEdge: NSRectEdge

    func makeCoordinator() -> Coordinator {
        Coordinator(
            tile: tile,
            initialSnapshot: initialSnapshot,
            isPresented: $isPresented,
            preferredEdge: preferredEdge
        )
    }

    func makeNSView(context: Context) -> FolderPopoverAnchorView {
        FolderPopoverAnchorView()
    }

    func updateNSView(_ nsView: FolderPopoverAnchorView, context: Context) {
        context.coordinator.update(
            tile: tile,
            initialSnapshot: initialSnapshot,
            isPresented: $isPresented,
            preferredEdge: preferredEdge
        )

        if isPresented {
            context.coordinator.show(relativeTo: nsView)
        } else {
            context.coordinator.close()
        }
    }

    static func dismantleNSView(_ nsView: FolderPopoverAnchorView, coordinator: Coordinator) {
        coordinator.close()
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        private let popover = NSPopover()
        private let hostingController = NSHostingController(
            rootView: FolderPopoverView(
                tile: FolderTile(
                    url: URL(fileURLWithPath: "/"),
                    displayName: "",
                    displayMode: .contents,
                    contentViewMode: .grid
                ),
                initialSnapshot: .loaded([]),
                isPresented: .constant(false)
            )
        )
        private var isPresented: Binding<Bool>
        private var preferredEdge: NSRectEdge
        private var lastContentSize = NSSize(width: 320, height: 240)
        private weak var anchorView: NSView?
        private var isInterruptingAutohide = false

        init(
            tile: FolderTile,
            initialSnapshot: FolderContentsSnapshot,
            isPresented: Binding<Bool>,
            preferredEdge: NSRectEdge
        ) {
            self.isPresented = isPresented
            self.preferredEdge = preferredEdge
            super.init()
            popover.contentViewController = hostingController
            popover.animates = true
            popover.behavior = .transient
            popover.delegate = self
            update(
                tile: tile,
                initialSnapshot: initialSnapshot,
                isPresented: isPresented,
                preferredEdge: preferredEdge
            )
        }

        func update(
            tile: FolderTile,
            initialSnapshot: FolderContentsSnapshot,
            isPresented: Binding<Bool>,
            preferredEdge: NSRectEdge
        ) {
            self.isPresented = isPresented
            self.preferredEdge = preferredEdge
            hostingController.rootView = FolderPopoverView(
                tile: tile,
                initialSnapshot: initialSnapshot,
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
            updateContentSize(lastContentSize)
            popover.show(relativeTo: anchorRect(in: view.bounds), of: view, preferredEdge: preferredEdge)
        }

        func close() {
            endAutohideInterruption()
            popover.performClose(nil)
        }

        func popoverDidClose(_ notification: Notification) {
            endAutohideInterruption()
            guard isPresented.wrappedValue else { return }
            DispatchQueue.main.async { [isPresented] in
                isPresented.wrappedValue = false
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
            lastContentSize = contentSize
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

private final class FolderPopoverAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
