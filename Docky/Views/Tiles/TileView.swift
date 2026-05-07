//
//  TileView.swift
//  Docky
//
//  Generic tile wrapper. Picks a concrete content view based on the tile's
//  case and applies any chrome shared across all tile types (hover, etc).
//

import AppKit
import Combine
import QuickLookThumbnailing
import SwiftUI

struct TileView: View {
    let tile: Tile
    let isDragging: Bool
    let isDocumentDropTarget: Bool
    let isAppFolderDropTarget: Bool
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var layout = DockLayoutService.shared
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared
    @ObservedObject private var workspace = WorkspaceService.shared
    @ObservedObject private var mediaPlayback = MediaPlaybackService.shared
    @ObservedObject private var editMode = DockEditModeService.shared
    @ObservedObject private var widgetExpansion = WidgetExpansionWindowController.shared
    @ObservedObject private var dockDrag = DockDragService.shared
    @State private var isHovering = false
    @State private var isTooltipPresented = false
    @State private var tooltipDelayTask: Task<Void, Never>?
    @State private var globalTileFrame: CGRect = .zero
    @State private var isFolderPopoverPresented = false
    @State private var isFolderListMenuPresented = false
    @State private var isAppFolderPopoverPresented = false
    @State private var isAppFolderListMenuPresented = false
    @State private var isContextMenuPresented = false
    @State private var widgetExpansionTask: Task<Void, Never>?
    @State private var folderSnapshot: FolderContentsSnapshot = .loaded([])
    @State private var lastFolderPopoverDismissedAt: TimeInterval = 0
    @State private var windowPreviewDelayTask: Task<Void, Never>?
    @ObservedObject private var windowPreview = WindowPreviewWindowController.shared
    @ObservedObject private var tilePress = TilePressService.shared

    private static let finderBundleIdentifier = "com.apple.finder"
    private static let folderPopoverRetapGuardInterval: TimeInterval = 0.25

    init(
        tile: Tile,
        isDragging: Bool = false,
        isDocumentDropTarget: Bool = false,
        isAppFolderDropTarget: Bool = false
    ) {
        self.tile = tile
        self.isDragging = isDragging
        self.isDocumentDropTarget = isDocumentDropTarget
        self.isAppFolderDropTarget = isAppFolderDropTarget
        self._dockSettings = ObservedObject(wrappedValue: DockSettingsService.shared)
        self._layout = ObservedObject(wrappedValue: DockLayoutService.shared)
        self._preferences = ObservedObject(wrappedValue: DockyPreferences.shared)
        self._product = ObservedObject(wrappedValue: ProductService.shared)
        self._workspace = ObservedObject(wrappedValue: WorkspaceService.shared)
        self._mediaPlayback = ObservedObject(wrappedValue: MediaPlaybackService.shared)
        self._editMode = ObservedObject(wrappedValue: DockEditModeService.shared)
        self._widgetExpansion = ObservedObject(wrappedValue: WidgetExpansionWindowController.shared)
        self._dockDrag = ObservedObject(wrappedValue: DockDragService.shared)
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
            .submenu("Sort By", children: FolderTileSortMode.allCases.map { mode in
                .action(mode.title, isOn: folderSortMode == mode) {
                    TileStore.shared.setFolderSortMode(tileID: tile.id, folderURL: folder.url, mode: mode)
                }
            })
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

    private var appFolderDisplayMode: AppFolderTileDisplayMode {
        guard case .appFolder = tile.content else {
            return .grid
        }

        return TileStore.shared.appFolderDisplayMode(tileID: tile.id)
    }

    private var folderSortMode: FolderTileSortMode {
        guard case .folder(let folder) = tile.content else {
            return .dateAdded
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
            actions.append(.submenu("Display As", children: [
                .action("Grid", isOn: appFolderDisplayMode == .grid) {
                    TileStore.shared.setAppFolderDisplayMode(tileID: tile.id, mode: .grid)
                },
                .action("Stack", isOn: appFolderDisplayMode == .stack) {
                    TileStore.shared.setAppFolderDisplayMode(tileID: tile.id, mode: .stack)
                }
            ]))
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

    private var isAppContent: Bool {
        if case .app = tile.content { return true }
        return false
    }

    /// Combined dim trigger for app icons: pressed (mouse-down before
    /// release, tracked by `TilePressService`'s NSEvent monitor) or active
    /// drag-over target. Folders/widgets/etc. don't dim — only `.app`
    /// content participates.
    private var appTileDimSignal: Bool {
        isAppContent && (tilePress.pressedTileID == tile.id || isDocumentDropTarget)
    }

    private var showsAppFolderDropBackdrop: Bool {
        isAppContent && isAppFolderDropTarget
    }

    private var tileBodyOpacity: Double {
        if isLockedProductPlacement { return 0.38 }
        if appTileDimSignal { return 0.5 }
        return 1
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
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        tileBody
    }

    private var tileBody: some View {
        laidOutContent
            .opacity(tileBodyOpacity)
            .animation(.easeInOut(duration: 0.12), value: appTileDimSignal)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .overlay(alignment: runningIndicatorAlignment) {
                runningIndicator
                    .padding(runningIndicatorEdge, runningIndicatorInset)
                    .offset(x: runningIndicatorOffsetVector.width, y: runningIndicatorOffsetVector.height)
            }
            .overlay {
                if isLockedProductPlacement {
                    LockedProductTileOverlay()
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onHover(perform: updateHoverState)
            .onTapGesture(perform: handleTap)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { newFrame in
                globalTileFrame = newFrame
                TilePressService.shared.registerFrame(tileID: tile.id, globalFrame: newFrame)
            }
            .onChange(of: isHovering) { _, isHovering in
                updateWidgetExpansionPresentation(isHovering: isHovering, sourceFrame: globalTileFrame)
            }
            .onDisappear {
                widgetExpansionTask?.cancel()
                widgetExpansionTask = nil
                windowPreviewDelayTask?.cancel()
                windowPreviewDelayTask = nil
                isHovering = false
                WidgetExpansionWindowController.shared.dismiss(sourceTileID: tile.id)
                isTooltipPresented = false
                isFolderPopoverPresented = false
                isFolderListMenuPresented = false
                isAppFolderPopoverPresented = false
                isAppFolderListMenuPresented = false
                isContextMenuPresented = false
                WindowPreviewWindowController.shared.dismiss(sourceTileID: tile.id)
                TilePressService.shared.unregisterFrame(tileID: tile.id)
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
            .onChange(of: editMode.isActive) { _, isActive in
                guard isActive else { return }
                widgetExpansionTask?.cancel()
                widgetExpansionTask = nil
                WidgetExpansionWindowController.shared.dismiss(sourceTileID: tile.id)
            }
            .onChange(of: windowPreview.activeSourceTileID) { _, _ in
                updateTooltipPresentation()
            }
            .onChange(of: dockDrag.springLoadedTileID) { _, springLoaded in
                guard springLoaded == tile.id else { return }
                switch tile.content {
                case .appFolder:
                    if !isAppFolderPopoverPresented {
                        isAppFolderPopoverPresented = true
                    }
                case .folder:
                    if !isFolderPopoverPresented {
                        isFolderPopoverPresented = true
                    }
                default:
                    return
                }
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
                        displayMode: appFolderDisplayMode,
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
            displayedContent
                .padding(contentPaddingEdges, contentPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .app, .minimizedWindow, .spacer, .divider:
            displayedContent
                .background(appFolderDropTargetBackdrop)
                .padding(contentPaddingEdges, contentPadding)
                .animation(.bouncy(duration: 0.4, extraBounce: 0.05), value: showsAppFolderDropBackdrop)
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
        let baseScale = max(0.5, min(1, effectiveTileSize / 48))
        return baseScale * max(0.25, preferences.activeIndicatorScale)
    }

    private var runningIndicatorOffsetVector: CGSize {
        let baseInward = max((layout.scaled(preferences.tileVerticalPadding) / 2), 2)
        let totalInward = baseInward + preferences.activeIndicatorOffset

        switch position {
        case .top:
            return CGSize(width: 0, height: totalInward)
        case .bottom:
            return CGSize(width: 0, height: -totalInward)
        case .left:
            return CGSize(width: totalInward, height: 0)
        case .right:
            return CGSize(width: -totalInward, height: 0)
        }
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
        layout.scaled(dockSettings.displayTileSize)
    }

    private func renderedWidgetSpan(for span: TileSpan) -> TileSpan {
        if layout.compactsWidgetsForOverflow || position.isVertical {
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

    /// Corner radius used when painting the app-folder-drop intent backdrop
    /// behind a plain `.app` tile. Mirrors `AppFolderTileView.iconGrid`'s
    /// container so the in-progress folder visually matches a finished one.
    private var appFolderDropTargetCornerRadius: CGFloat {
        let maximumCornerRadius = max(0, effectiveTileSize / 2)
        return preferences.tileClipShape.resolvedCornerRadius(
            base: effectiveTileSize * 0.225,
            maximum: maximumCornerRadius
        )
    }

    @ViewBuilder
    private var appFolderDropTargetBackdrop: some View {
        if isAppFolderDropTarget && isAppContent {
            RoundedRectangle(
                cornerRadius: appFolderDropTargetCornerRadius,
                style: .continuous
            )
            .fill(Color.black.opacity(0.18))
            .allowsHitTesting(false)
            .transition(.scale)
        }
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
                    isWithinStack: false,
                    isExpanded: false,
                    isExpandedPreviewOpen: widgetExpansion.activeSourceTileID == tile.id
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
                transparencyCompensationInset: 0,
                iconOverrideURL: preferences.effectiveLaunchpadIconOverrideURL,
                iconOverridePaddingFraction: preferences.launchpadIconPaddingFraction
            )
        case .widget(let widget):
            WidgetTileView(
                tile: widget,
                cornerRadius: nonAppTileCornerRadius,
                renderedSpan: renderedWidgetSpan(for: widget.effectiveSpan),
                isWithinStack: false,
                isExpanded: false,
                isExpandedPreviewOpen: widgetExpansion.activeSourceTileID == tile.id
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

    private func updateHoverState(isHovering newValue: Bool) {
        guard expandableWidget != nil else {
            applyHoverState(newValue)
            return
        }

        if newValue {
            applyHoverState(true)
            return
        }

        applyHoverState(false)
    }

    private func applyHoverState(_ isHovering: Bool) {
        self.isHovering = isHovering
        updateTooltipPresentation()
        updateWindowPreviewPresentation(isHovering: isHovering)
    }

    /// Hover-dwell trigger for the per-tile window preview window. Mirrors
    /// the widget expansion contract: present after a delay on hover-in,
    /// requestDismiss on hover-out (with a short grace so the cursor can
    /// transition into the preview window without dropping it). Both `.app`
    /// and `.appFolder` tiles participate — the app-folder case aggregates
    /// windows from every contained app.
    private func updateWindowPreviewPresentation(isHovering: Bool) {
        // Freeze preview state while a context menu is open on this tile —
        // the menu's mouse handling can drop us out of hover and prematurely
        // dismiss, or restart the dwell once the user moves off. The
        // preview's own hover monitor still keeps it alive if the cursor is
        // over it; we just don't react from the tile side.
        if isContextMenuPresented { return }

        windowPreviewDelayTask?.cancel()
        windowPreviewDelayTask = nil

        let bundleIDs = windowPreviewBundleIdentifiers
        guard !bundleIDs.isEmpty,
              !editMode.isActive,
              !isAppFolderPopoverPresented,
              !isAppFolderListMenuPresented
        else {
            WindowPreviewWindowController.shared.requestDismiss(sourceTileID: tile.id)
            return
        }

        if !isHovering {
            WindowPreviewWindowController.shared.requestDismiss(sourceTileID: tile.id)
            return
        }

        let workspace = WorkspaceService.shared
        let hasAnyWindow = bundleIDs.contains { id in
            !workspace.appWindows(bundleIdentifier: id).isEmpty
        }
        guard hasAnyWindow else {
            WindowPreviewWindowController.shared.requestDismiss(sourceTileID: tile.id)
            return
        }

        let delay = max(0, preferences.windowPreviewHoverDelay)
        windowPreviewDelayTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, self.isHovering else { return }
            WindowPreviewWindowController.shared.present(
                forBundleIdentifiers: bundleIDs,
                sourceTileID: tile.id,
                sourceFrame: globalTileFrame,
                preferredEdge: inwardPopoverEdge
            )
        }
    }

    /// Bundle identifiers whose windows should be merged into the hover
    /// preview for this tile. `.app` returns its single bundle; `.appFolder`
    /// returns every contained app's bundle.
    private var windowPreviewBundleIdentifiers: [String] {
        switch tile.content {
        case .app(let app) where app.displayedWidget == nil:
            return app.bundleIdentifier.isEmpty ? [] : [app.bundleIdentifier]
        case .appFolder(let folder):
            return folder.apps
                .map(\.bundleIdentifier)
                .filter { !$0.isEmpty }
        default:
            return []
        }
    }

    private var expandableWidget: WidgetTile? {
        switch tile.content {
        case .widget(let widget):
            return widget
        case .app(let app) where app.displayedWidget != nil:
            return app.displayedWidget
        default:
            return nil
        }
    }

    private var expandableWidgetRenderedSpan: TileSpan {
        switch tile.content {
        case .widget(let widget):
            return renderedWidgetSpan(for: widget.effectiveSpan)
        case .app(let app):
            return renderedWidgetSpan(for: app.displayedWidget?.effectiveSpan ?? .one)
        default:
            return .one
        }
    }

    private func updateWidgetExpansionPresentation(isHovering: Bool, sourceFrame: CGRect) {
        widgetExpansionTask?.cancel()
        widgetExpansionTask = nil

        guard preferences.enablesWidgetHoverPreview,
              preferences.widgetHoverPreviewSpans.contains(expandableWidgetRenderedSpan),
              isHovering,
              let widget = expandableWidget,
              !isContextMenuPresented,
              !editMode.isActive
        else {
            WidgetExpansionWindowController.shared.requestDismiss(sourceTileID: tile.id)
            return
        }

        widgetExpansionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0, preferences.widgetHoverPreviewDelay)))
            guard !Task.isCancelled else { return }
            guard self.isHovering, !self.isContextMenuPresented, !self.editMode.isActive else { return }
            WidgetExpansionWindowController.shared.present(
                widget: widget,
                sourceTileID: tile.id,
                sourceFrame: sourceFrame,
                cornerRadius: nonAppTileCornerRadius,
                renderedSpan: expandableWidgetRenderedSpan
            )
        }
    }

    private func updateContextMenuPresentation(isPresented: Bool) {
        isContextMenuPresented = isPresented
        updateTooltipPresentation()

        if isPresented {
            // Cancel any in-flight preview dwell and dismiss whatever is
            // already on screen — the context menu takes over input and
            // the preview shouldn't sit underneath it.
            windowPreviewDelayTask?.cancel()
            windowPreviewDelayTask = nil
            WindowPreviewWindowController.shared.dismiss(sourceTileID: tile.id)

            if expandableWidget != nil {
                widgetExpansionTask?.cancel()
                widgetExpansionTask = nil
                WidgetExpansionWindowController.shared.dismiss(sourceTileID: tile.id)
            }
        }
    }

    private func updateTooltipPresentation() {
        tooltipDelayTask?.cancel()
        tooltipDelayTask = nil

        let shouldShow = isHovering
            && tooltipTitle != nil
            && !isFolderPopoverPresented
            && !isFolderListMenuPresented
            && !isAppFolderPopoverPresented
            && !isAppFolderListMenuPresented
            && !isContextMenuPresented
            && windowPreview.activeSourceTileID != tile.id

        guard shouldShow else {
            isTooltipPresented = false
            return
        }

        isTooltipPresented = true
    }

    private func handleTap() {
        if isLockedProductPlacement {
            isTooltipPresented = false
            openProductSettings()
            return
        }

        // Tap-to-act always supersedes the hover preview.
        windowPreviewDelayTask?.cancel()
        windowPreviewDelayTask = nil
        WindowPreviewWindowController.shared.dismiss(sourceTileID: tile.id)

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

        if let windowsSubmenu = appFolderWindowsSubmenu(for: folder) {
            if !actions.isEmpty {
                actions.append(.divider)
            }
            actions.append(windowsSubmenu)
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

    /// "Windows" submenu for the folder tile: lists every visible (non-
    /// minimized) window across the folder's apps in WindowRegistry MRU
    /// order, each focusable, plus a Tile sub-section for arranging the top
    /// two (or four) windows side-by-side / stacked / in quarters. Returns
    /// nil when there are no visible windows so the submenu doesn't appear.
    private func appFolderWindowsSubmenu(for folder: AppFolderTile) -> ContextAction? {
        let bundleIDs = Set(folder.apps.map(\.bundleIdentifier))
        guard !bundleIDs.isEmpty else { return nil }

        let windows = WindowRegistry.shared.windows.filter { window in
            bundleIDs.contains(window.bundleIdentifier) && !window.isMinimized
        }
        guard !windows.isEmpty else { return nil }

        var children: [ContextAction] = windows.map { window in
            .action(appWindowMenuTitle(for: window)) {
                _ = WorkspaceService.shared.focus(window: window)
            }
        }

        if windows.count >= 2 {
            let workspace = WorkspaceService.shared
            children.append(.divider)
            children.append(contentsOf: [
                .action(
                    "Left and Right",
                    image: contextMenuSymbol("rectangle.lefthalf.filled")
                ) { _ = workspace.tile(windows: windows, layout: .leftRight) },
                .action(
                    "Right and Left",
                    image: contextMenuSymbol("rectangle.righthalf.filled")
                ) { _ = workspace.tile(windows: windows, layout: .rightLeft) },
                .action(
                    "Top and Bottom",
                    image: contextMenuSymbol("rectangle.tophalf.filled")
                ) { _ = workspace.tile(windows: windows, layout: .topBottom) },
                .action(
                    "Bottom and Top",
                    image: contextMenuSymbol("rectangle.bottomhalf.filled")
                ) { _ = workspace.tile(windows: windows, layout: .bottomTop) },
            ])
            if windows.count >= 3 {
                children.append(
                    .action(
                        "Quarters",
                        image: contextMenuSymbol("rectangle.split.2x2")
                    ) { _ = workspace.tile(windows: windows, layout: .quarters) }
                )
            }
        }

        return .submenu("Windows", children: children)
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
        let withWindows = injectingAppWindowActions(windows, into: actions)
        return injectingFinderHomeNavigation(into: withWindows, for: app)
    }

    private func injectingFinderHomeNavigation(
        into actions: [ContextAction],
        for app: AppTile
    ) -> [ContextAction] {
        guard app.bundleIdentifier == Self.finderBundleIdentifier else {
            return actions
        }

        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let homeName = (try? homeURL.resourceValues(forKeys: [.localizedNameKey]).localizedName)
            ?? homeURL.lastPathComponent
        let homeIcon = IconCacheService.shared.icon(forFileURL: homeURL)

        let homeSubmenu = ContextAction.lazySubmenu(homeName, image: homeIcon) {
            folderNavigationContextActions(for: homeURL)
        }

        var result: [ContextAction] = [homeSubmenu]
        if let first = actions.first, first.kind != .divider {
            result.append(.divider)
        }
        result.append(contentsOf: actions)
        return result
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


    private func minimizedWindowContextActions(
        for window: AppWindow,
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
        private var currentTitle: String

        init(title: String, preferredEdge: NSRectEdge) {
            self.preferredEdge = preferredEdge
            self.currentTitle = title
            hostingController.rootView = TileTooltipView(title: title)
            popover.contentViewController = hostingController
            popover.animates = false
            popover.behavior = .applicationDefined
            updateContentSize()
        }

        func update(title: String, preferredEdge: NSRectEdge) {
            self.preferredEdge = preferredEdge
            guard title != currentTitle else { return }
            currentTitle = title
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
            let icon = IconCacheService.shared.previewIcon(forFileURL: itemURL).copy() as? NSImage
                ?? IconCacheService.shared.previewIcon(forFileURL: itemURL)
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
        private var globalClickMonitor: Any?
        private var localClickMonitor: Any?
        private var dragEndSubscription: AnyCancellable?

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

        /// Mirrors AppFolderPopoverPresenter: when the popover opens during
        /// an active drag, watch DockDragService so the popover closes when
        /// the drag ends — drop on us, drop elsewhere, or cancel.
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, isPresented] in
                guard let self else { return }
                if isPresented.wrappedValue {
                    self.popover.performClose(nil)
                    isPresented.wrappedValue = false
                }
            }
        }

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

private func folderNavigationContextActions(for folderURL: URL) -> [ContextAction] {
    let snapshot = FolderAccessService.shared.snapshot(of: folderURL)
    guard case .loaded(let items) = snapshot else {
        return [.action("Can't read folder") {}]
    }

    let sortedItems = FolderAccessService.shared.sortedItems(in: items, sortMode: .name)

    var actions: [ContextAction] = sortedItems.map { url in
        let resources = try? url.resourceValues(forKeys: [
            .localizedNameKey,
            .isDirectoryKey,
            .isPackageKey
        ])
        let displayName = resources?.localizedName ?? url.lastPathComponent
        let isNavigableFolder = (resources?.isDirectory == true) && (resources?.isPackage != true)
        let icon = IconCacheService.shared.icon(forFileURL: url)

        if isNavigableFolder {
            return .lazySubmenu(displayName, image: icon) {
                folderNavigationContextActions(for: url)
            }
        }

        return .lazySubmenu(displayName, image: icon) {
            fileContextActions(for: url)
        }
    }

    if !actions.isEmpty {
        actions.append(.divider)
    }
    actions.append(.action("Open in Finder", image: contextMenuSymbol("folder")) {
        Task {
            _ = await AppleScriptService.shared.openFinderWindow(for: folderURL)
        }
    })

    return actions
}

func fileContextActions(for url: URL) -> [ContextAction] {
    [
        .customView(FilePreviewMenuItemView(url: url)),
        .divider,
        .action("Open", image: contextMenuSymbol("arrow.up.forward.app")) {
            NSWorkspace.shared.open(url)
        },
        .lazySubmenu("Open With", image: contextMenuSymbol("app.badge")) {
            openWithApplicationActions(for: url)
        },
        .divider,
        .action("Copy", image: contextMenuSymbol("doc.on.doc")) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
        },
        .lazySubmenu("Share", image: contextMenuSymbol("square.and.arrow.up")) {
            shareApplicationActions(for: url)
        },
        .divider,
        .action(
            "Move to Trash",
            image: contextMenuSymbol("trash"),
            isDestructive: true
        ) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ]
}

func contextMenuSymbol(_ name: String) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)
}

/// Inserts a "running windows" section into a catalog-driven app menu.
/// Each window becomes a top-level action that focuses the window when
/// chosen. Inserted before any "Options" submenu, falling back to the end
/// when none is present. Called from both the dock tile path and the app
/// folder grid path so menus stay in sync.
func injectingAppWindowActions(
    _ windows: [AppWindow],
    into actions: [ContextAction]
) -> [ContextAction] {
    guard !windows.isEmpty else { return actions }

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

func appWindowMenuTitle(for window: AppWindow) -> String {
    guard window.isMinimized else {
        return window.windowTitle
    }

    return "\(window.windowTitle) (Minimized)"
}

private func openWithApplicationActions(for url: URL) -> [ContextAction] {
    let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: url)
    guard !appURLs.isEmpty else {
        return [.action("No Applications Available") {}]
    }

    return appURLs.map { appURL in
        let appName = (try? appURL.resourceValues(forKeys: [.localizedNameKey]).localizedName)
            ?? appURL.deletingPathExtension().lastPathComponent
        let icon = IconCacheService.shared.icon(forFileURL: appURL)
        return .action(appName, image: icon) {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: appURL,
                configuration: configuration,
                completionHandler: nil
            )
        }
    }
}

private func shareApplicationActions(for url: URL) -> [ContextAction] {
    let services = NSSharingService.sharingServices(forItems: [url])
    guard !services.isEmpty else {
        return [.action("No Sharing Options") {}]
    }

    return services.map { service in
        .action(service.title, image: service.image) {
            service.perform(withItems: [url])
        }
    }
}

final class FilePreviewMenuItemView: NSView, NSDraggingSource {
    private static let viewSize = CGSize(width: 240, height: 160)
    private static let dragThresholdSquared: CGFloat = 16

    private let imageView: NSImageView
    private let url: URL
    private var mouseDownLocation: NSPoint?

    init(url: URL) {
        self.url = url
        let frame = NSRect(origin: .zero, size: Self.viewSize)
        let inset = NSRect(
            x: 12,
            y: 8,
            width: frame.width - 24,
            height: frame.height - 16
        )

        let imageView = NSImageView(frame: inset)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.image = IconCacheService.shared.previewIcon(forFileURL: url)
        imageView.autoresizingMask = [.width, .height]
        self.imageView = imageView

        super.init(frame: frame)
        addSubview(imageView)
        loadPreview(for: url)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downLocation = mouseDownLocation else { return }
        let dx = event.locationInWindow.x - downLocation.x
        let dy = event.locationInWindow.y - downLocation.y
        guard (dx * dx + dy * dy) >= Self.dragThresholdSquared else { return }
        mouseDownLocation = nil

        let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        let dragImage = imageView.image ?? IconCacheService.shared.icon(forFileURL: url)
        draggingItem.setDraggingFrame(imageView.frame, contents: dragImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
        enclosingMenuItem?.menu?.cancelTracking()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        [.copy, .link, .generic]
    }

    private func loadPreview(for url: URL) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: Self.viewSize,
            scale: scale,
            representationTypes: .all
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            guard let nsImage = thumbnail?.nsImage else { return }
            DispatchQueue.main.async {
                self?.imageView.image = nsImage
            }
        }
    }
}
