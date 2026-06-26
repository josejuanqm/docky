//
//  TileView.swift
//  Docky
//
//  Generic tile wrapper. Picks a concrete content view based on the tile's
//  case and applies any chrome shared across all tile types (hover, etc).
//

import AppKit
import Combine
import OSLog
import QuickLookThumbnailing
import SwiftUI

struct TileView: View {
    private static let logger = Logger(subsystem: "gt.quintero.Docky", category: "TileTap")

    let tile: Tile
    let isDragging: Bool
    let isDocumentDropTarget: Bool
    let isAppFolderDropTarget: Bool
    let isTrashDropTarget: Bool
    /// Caller-supplied icon extent, set when magnification is active so
    /// proportional metrics (corner radius, content padding) scale with
    /// the rendered frame instead of staying at the resting tile size.
    /// `nil` falls back to the shared `DockLayoutService` size.
    let renderedTileSize: CGFloat?
    private let dockSettings = DockSettingsService.shared
    @ObservedObject private var layout = DockLayoutService.shared
    @Bindable private var preferences = DockyPreferences.shared
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
    @ObservedObject private var dockBadges = DockBadgeService.shared

    private static let finderBundleIdentifier = "com.apple.finder"
    private static let folderPopoverRetapGuardInterval: TimeInterval = 0.25

    init(
        tile: Tile,
        isDragging: Bool = false,
        isDocumentDropTarget: Bool = false,
        isAppFolderDropTarget: Bool = false,
        isTrashDropTarget: Bool = false,
        renderedTileSize: CGFloat? = nil
    ) {
        self.tile = tile
        self.isDragging = isDragging
        self.isDocumentDropTarget = isDocumentDropTarget
        self.isAppFolderDropTarget = isAppFolderDropTarget
        self.isTrashDropTarget = isTrashDropTarget
        self.renderedTileSize = renderedTileSize
        self._layout = ObservedObject(wrappedValue: DockLayoutService.shared)
        self._preferences = Bindable(wrappedValue: DockyPreferences.shared)
        self._workspace = ObservedObject(wrappedValue: WorkspaceService.shared)
        self._mediaPlayback = ObservedObject(wrappedValue: MediaPlaybackService.shared)
        self._editMode = ObservedObject(wrappedValue: DockEditModeService.shared)
        self._widgetExpansion = ObservedObject(wrappedValue: WidgetExpansionWindowController.shared)
        self._dockDrag = ObservedObject(wrappedValue: DockDragService.shared)
        self._dockBadges = ObservedObject(wrappedValue: DockBadgeService.shared)
    }

    private func contextActions(modifierFlags: NSEvent.ModifierFlags) -> [ContextAction] {

        if let catalogActions = MenuCatalogService.shared.contextActions(for: tile, modifierFlags: modifierFlags) {
            switch tile.content {
            case .app(let app):
                return appContextActions(for: app, modifierFlags: modifierFlags, baseActions: catalogActions)
            case .trash:
                return catalogActions
            case .launchpad, .startMenu:
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
                    actions.append(.action(String(localized: "Remove from Dock")) {
                        removeDockyTile()
                    })
                }
                return actions
            case .minimizedWindow, .appFolder, .widget, .smartStack, .spacer, .flexibleSpacer, .divider:
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
                actions.append(.action(String(localized: "Open Launchpad")) {
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
        case .startMenu:
            var actions: [ContextAction] = []

            if preferences.enablesStartMenuOverlay {
                actions.append(.action(String(localized: "Open Start Menu")) {
                    StartMenuService.shared.present()
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
                .action(String(localized: "Open in Finder")) {
                    Task {
                        _ = await AppleScriptService.shared.openFinderWindow(for: folder.url)
                    }
                },
                .action(String(localized: "Reveal in Finder")) {
                    Task {
                        _ = await AppleScriptService.shared.revealInFinder(folder.url)
                    }
                }
            ]

            if isDockyTrailingTile {
                actions.append(.divider)
                actions.append(.action(String(localized: "Remove from Dock")) {
                    removeDockyTile()
                })
            }

            return actions
        case .trash:
            return [
                .action(String(localized: "Open Trash")) {
                    Task {
                        _ = await AppleScriptService.shared.openTrash()
                    }
                },
                .divider,
                .action(String(localized: "Empty Trash"), isDestructive: true) {
                    Task {
                        _ = await AppleScriptService.shared.emptyTrash()
                    }
                }
            ]
        case .spacer, .flexibleSpacer, .divider:
            return customDockyTileActions
        }
    }

    private var folderPresentationContextActions: [ContextAction] {
        guard case .folder(let folder) = tile.content else {
            return []
        }

        return [
            .submenu(String(localized: "Display as"), children: [
                .action(String(localized: "Folder"), isOn: folderDisplayMode == .folder) {
                    TileStore.shared.setFolderDisplayMode(tileID: tile.id, folderURL: folder.url, mode: .folder)
                },
                .action(String(localized: "Contents"), isOn: folderDisplayMode == .contents) {
                    TileStore.shared.setFolderDisplayMode(tileID: tile.id, folderURL: folder.url, mode: .contents)
                }
            ]),
            .submenu(String(localized: "View Content as"), children: viewContentSubmenuChildren(folder: folder)),
            .submenu(String(localized: "Sort By"), children: FolderTileSortMode.allCases.map { mode in
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
            .action(String(localized: "Edit Dock...")) {
                DockEditModeService.shared.enter()
            }
        ]

        if case .spacer = tile.content {
            actions.append(.divider)
            actions.append(.action(String(localized: "Remove from Dock")) {
                removeDockyTile()
            })
        }

        if case .flexibleSpacer = tile.content {
            actions.append(.divider)
            actions.append(.action(String(localized: "Remove from Dock")) {
                removeDockyTile()
            })
        }

        if case .divider = tile.content {
            actions.append(.divider)
            actions.append(.action(String(localized: "Remove from Dock")) {
                removeDockyTile()
            })
        }

        if case .widget = tile.content {
            actions.append(.divider)
            actions.append(.action(String(localized: "Remove from Dock")) {
                removeDockyTile()
            })
        }

        if case .smartStack = tile.content {
            actions.append(.divider)
            actions.append(.action(String(localized: "Remove from Dock")) {
                removeDockyTile()
            })
        }

        if case .appFolder = tile.content {
            actions.append(.divider)
            actions.append(.submenu(String(localized: "Display As"), children: [
                .action(String(localized: "Grid"), isOn: appFolderDisplayMode == .grid) {
                    TileStore.shared.setAppFolderDisplayMode(tileID: tile.id, mode: .grid)
                },
                .action(String(localized: "Stack"), isOn: appFolderDisplayMode == .stack) {
                    TileStore.shared.setAppFolderDisplayMode(tileID: tile.id, mode: .stack)
                }
            ]))
            actions.append(.submenu(String(localized: "View Content as"), children: [
                .action(String(localized: "Grid"), isOn: appFolderContentViewMode == .grid) {
                    TileStore.shared.setAppFolderContentViewMode(tileID: tile.id, mode: .grid)
                },
                .action(String(localized: "List"), isOn: appFolderContentViewMode == .list) {
                    TileStore.shared.setAppFolderContentViewMode(tileID: tile.id, mode: .list)
                },
                .action(String(localized: "Inline"), isOn: appFolderContentViewMode == .inline) {
                    TileStore.shared.setAppFolderContentViewMode(tileID: tile.id, mode: .inline)
                }
            ]))
            actions.append(.divider)
            actions.append(.action(String(localized: "Rename Folder...")) {
                TileStore.shared.presentRenameAppFolderPrompt(tileID: tile.id)
            })
            actions.append(.action(String(localized: "Ungroup Folder")) {
                TileStore.shared.ungroupAppFolder(tileID: tile.id)
            })
        }

        switch tile.content {
        case .launchpad, .startMenu:
            actions.append(.divider)
            actions.append(.action(String(localized: "Remove from Dock")) {
                removeDockyTile()
            })
        default:
            break
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

    private var isAppContent: Bool {
        if case .app = tile.content { return true }
        return false
    }

    /// Content types that participate in the press/drop-target darken.
    /// Apps, folders (both kinds), and trash are launchable/drop targets
    /// where the darken communicates "this is the thing you're acting
    /// on"; widgets/spacers/dividers don't need the affordance.
    private var participatesInPressDarken: Bool {
        switch tile.content {
        case .app, .appFolder, .folder, .trash:
            return true
        case .minimizedWindow, .spacer, .flexibleSpacer, .divider, .launchpad, .startMenu, .widget, .smartStack:
            return false
        }
    }

    /// Combined darken trigger: pressed (mouse-down before release,
    /// tracked by `TilePressService`'s NSEvent monitor) or active
    /// drop-target. Drives the `.brightness` darken below.
    private var pressDarkenSignal: Bool {
        participatesInPressDarken && (tilePress.pressedTileID == tile.id || isDocumentDropTarget)
    }

    private var showsAppFolderDropBackdrop: Bool {
        isAppContent && isAppFolderDropTarget
    }

    private var tileBodyOpacity: Double {
        1
    }

    /// `brightness(-0.35)` darkens icons in place without thinning them
    /// out the way a 0.5 opacity dim would (since opacity also makes the
    /// background show through, which on a transparent dock reads as
    /// "fading away" rather than "being pressed").
    private var pressDarkenAmount: Double {
        pressDarkenSignal ? -0.35 : 0
    }

    /// Background drawn behind the tile when the cursor is over it.
    /// Drives the Win10-style "lighten on hover" treatment; respects
    /// the theme/user-supplied color, image, opacity, and clip radius.
    /// `EmptyView` when no source is set so the tile stays transparent.
    @ViewBuilder
    private var hoverBackground: some View {
        if isHovering, hasHoverBackground {
            let cornerRadius = preferences.effectiveTileHoverBackgroundCornerRadius
            let opacity = preferences.effectiveTileHoverBackgroundOpacity
            ZStack {
                if let url = preferences.effectiveTileHoverBackgroundImageURL,
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let color = preferences.effectiveTileHoverBackgroundColor {
                    Color(nsColor: color)
                }
            }
            .opacity(opacity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
        }
    }

    private var hasHoverBackground: Bool {
        guard supportsHoverBackground else { return false }
        return preferences.effectiveTileHoverBackgroundImageURL != nil
            || preferences.effectiveTileHoverBackgroundColor != nil
    }

    /// Only "tappable" tiles (icons that act like apps or files) get
    /// the hover treatment. Widgets, smart stacks, and structural
    /// fixtures (dividers, spacers) stay flat, a hover halo on a
    /// widget reads as a misfire.
    private var supportsHoverBackground: Bool {
        switch tile.content {
        case .app, .appFolder, .folder, .trash, .launchpad, .startMenu:
            true
        case .widget, .smartStack, .divider, .spacer, .flexibleSpacer,
             .minimizedWindow:
            false
        }
    }

    /// Background drawn under the *foreground* (frontmost) app's tile.
    /// Independent of hover, both can stack, with hover painted on top.
    /// Updates live via `WorkspaceService.frontmostBundleIdentifier`.
    @ViewBuilder
    private var activeBackground: some View {
        if isFrontmostTile, hasActiveBackground {
            let cornerRadius = preferences.effectiveTileActiveBackgroundCornerRadius
            let opacity = preferences.effectiveTileActiveBackgroundOpacity
            ZStack {
                if let url = preferences.effectiveTileActiveBackgroundImageURL,
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let color = preferences.effectiveTileActiveBackgroundColor {
                    Color(nsColor: color)
                }
            }
            .opacity(opacity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
        }
    }

    private var hasActiveBackground: Bool {
        preferences.effectiveTileActiveBackgroundImageURL != nil
            || preferences.effectiveTileActiveBackgroundColor != nil
    }

    /// True when this tile represents the currently foreground app
    /// (or any app inside a grouped folder is foreground).
    private var isFrontmostTile: Bool {
        switch tile.content {
        case .app(let app):
            return workspace.isFrontmost(bundleIdentifier: app.bundleIdentifier)
        case .appFolder(let folder):
            return folder.apps.contains { app in
                workspace.isFrontmost(bundleIdentifier: app.bundleIdentifier)
            }
        case .folder, .launchpad, .startMenu, .widget, .smartStack, .spacer, .flexibleSpacer, .divider, .trash, .minimizedWindow:
            return false
        }
    }

    /// Notification badge text to paint over this tile, or `nil` when the
    /// feature is off or the app has no badge. App folders show the summed
    /// numeric badge of the apps they contain (mirroring how the count rolls
    /// up when running apps collapse into a folder).
    private var badgeText: String? {
        guard preferences.showsAppBadges else { return nil }
        switch tile.content {
        case .app(let app):
            return dockBadges.badge(forBundleIdentifier: app.bundleIdentifier)
        case .appFolder(let folder):
            let total = folder.apps.reduce(0) { sum, app in
                sum + (dockBadges.badge(forBundleIdentifier: app.bundleIdentifier).flatMap(Int.init) ?? 0)
            }
            return total > 0 ? String(total) : nil
        case .folder, .launchpad, .startMenu, .widget, .smartStack, .spacer, .flexibleSpacer, .divider, .trash, .minimizedWindow:
            return nil
        }
    }

    /// Effective drop shadow applied behind the tile's icon content.
    /// Returns `Color.clear` when no shadow color is set, combined
    /// with a 0 radius below, that makes `.shadow(...)` a true no-op.
    private var iconShadowColor: Color {
        guard let nsColor = preferences.effectiveIconShadowColor else {
            return Color.clear
        }
        return Color(nsColor: nsColor)
            .opacity(preferences.effectiveIconShadowOpacity)
    }

    private var iconShadowRadius: CGFloat {
        preferences.effectiveIconShadowColor == nil ? 0 : preferences.effectiveIconShadowRadius
    }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        tileBody
    }

    private var tileBody: some View {
        laidOutContent
            // Icon-only padding: shrinks the rendered icon without
            // touching the tile's layout box. Sized per theme/user.
            .padding(appliedTileIconPadding)
            .scaleEffect(isHovering ? preferences.effectiveTileHoverScale : 1)
            .shadow(color: iconShadowColor, radius: iconShadowRadius)
            .opacity(tileBodyOpacity * (isHovering ? preferences.effectiveTileHoverOpacity : 1))
            .brightness(pressDarkenAmount)
            .animation(.easeInOut(duration: 0.12), value: pressDarkenSignal)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(hoverBackground)
            .background(activeBackground)
            .overlay(alignment: runningIndicatorAlignment) {
                runningIndicator
                    .padding(runningIndicatorEdge, runningIndicatorInset)
                    .offset(x: runningIndicatorOffsetVector.width, y: runningIndicatorOffsetVector.height)
            }
            .overlay(alignment: .topTrailing) {
                if let badgeText {
                    DockBadgeView(text: badgeText)
                        .padding(appliedTileIconPadding)
                }
            }
            .contentShape(Rectangle())
            .onHover(perform: updateHoverState)
            .onTapGesture(perform: handleTap)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { newFrame in
                globalTileFrame = newFrame
            }
            .onChange(of: isHovering) { isHovering in
                TilePressService.shared.registerHover(tileID: tile.id, isHovering: isHovering)
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
                TilePressService.shared.clearHover(tileID: tile.id)
            }
            .onChange(of: isFolderPopoverPresented) { isPresented in
                updateTooltipPresentation()
                guard !isPresented else { return }
                lastFolderPopoverDismissedAt = Date.timeIntervalSinceReferenceDate
            }
            .onChange(of: isFolderListMenuPresented) { _ in
                updateTooltipPresentation()
            }
            .onChange(of: isAppFolderListMenuPresented) { _ in
                updateTooltipPresentation()
            }
            .onChange(of: editMode.isActive) { isActive in
                guard isActive else { return }
                widgetExpansionTask?.cancel()
                widgetExpansionTask = nil
                WidgetExpansionWindowController.shared.dismiss(sourceTileID: tile.id)
            }
            .onChange(of: windowPreview.activeSourceTileID) { _ in
                updateTooltipPresentation()
            }
            .onChange(of: dockDrag.springLoadedTileID) { springLoaded in
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
                        preferredEdge: inwardPopoverEdge,
                        repositionKey: effectiveTileSize
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
                    } else if folderContentViewMode == .fan,
                              position == .bottom,
                              case .loaded(let snapshotItems) = folderSnapshot,
                              snapshotItems.count <= FolderFanView.maximumItemCount {
                        // Fan mode: bottom-anchored parabolic overlay,
                        // only when the folder fits in a single bow.
                        // Larger folders silently fall through to the
                        // grid popover below — `>10 items → grid` is
                        // intentional per spec.
                        // Keep the sort order as-is. The fan curve
                        // already places item 0 at the bottom of the
                        // arc (closest to the tile) and the last item
                        // at the top — so the newest entry (sorted
                        // first) sits near the tile and the oldest
                        // ends up at the top of the fan naturally.
                        let fanItems = FolderAccessService.shared.sortedItems(
                            in: snapshotItems,
                            sortMode: folderSortMode
                        )
                        FolderFanPresenter(
                            folderURL: folder.url,
                            items: fanItems,
                            isPresented: $isFolderPopoverPresented
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
                            tileID: tile.id,
                            isPresented: $isAppFolderListMenuPresented,
                            preferredEdge: inwardPopoverEdge
                        )
                    } else if appFolderContentViewMode == .grid {
                        AppFolderPopoverPresenter(
                            tile: presentedFolder,
                            tileID: tile.id,
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
        case .appFolder, .launchpad, .startMenu, .widget, .smartStack:
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
        case .app, .minimizedWindow, .spacer, .flexibleSpacer, .divider:
            displayedContent
                .background(appFolderDropTargetBackdrop)
                .padding(contentPaddingEdges, contentPadding)
                .animation(.bouncy(duration: 0.4, extraBounce: 0.05), value: showsAppFolderDropBackdrop)
        }
    }

    private var displayedContent: some View {
        content
    }

    @ViewBuilder
    private var runningIndicator: some View {
        if showsRunningIndicator {
            switch preferences.effectiveActiveIndicatorShape {
            case .none:
                EmptyView()
            case .dot, .pill, .underline:
                runningIndicatorShape
                    .frame(width: runningIndicatorSize.width, height: runningIndicatorSize.height)
                    .foregroundStyle(Color(nsColor: preferences.effectiveActiveIndicatorColor).opacity(0.9))
            case .image:
                if let runningIndicatorImage {
                    // Render the artwork in its natural (horizontal)
                    // orientation, rotate, then claim the post-rotation
                    // bounding box. Without the rotation the outer frame
                    // is tall+narrow on vertical docks but aspect-fit
                    // letterboxes the wide artwork into a sliver.
                    Image(nsImage: runningIndicatorImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: runningIndicatorImageLength,
                            maxHeight: runningIndicatorImageThickness
                        )
                        .rotationEffect(runningIndicatorImageRotation)
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
        case .launchpad, .startMenu, .widget, .smartStack, .folder, .spacer, .flexibleSpacer, .divider, .trash:
            false
        }
    }

    @ViewBuilder
    private var runningIndicatorShape: some View {
        switch preferences.effectiveActiveIndicatorShape {
        case .none, .image:
            EmptyView()
        case .dot:
            Circle()
        case .pill:
            Capsule()
        case .underline:
            // Sharp-cornered rectangle that spans the icon edge ,
            // Windows 10-style accent line under running apps.
            Rectangle()
        }
    }

    private var runningIndicatorSize: CGSize {
        switch preferences.effectiveActiveIndicatorShape {
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
        case .underline:
            // Span the icon's full extent along the dock axis; stay
            // thin along the screen-facing axis. The overlay alignment +
            // existing offset keep it flush against the screen-facing
            // edge.
            if position.isVertical {
                CGSize(width: runningIndicatorThickness, height: effectiveTileSize)
            } else {
                CGSize(width: effectiveTileSize, height: runningIndicatorThickness)
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

    private var runningIndicatorImageRotation: Angle {
        position.isVertical ? .degrees(90) : .zero
    }

    private var runningIndicatorInset: CGFloat {
        max(1, round(2 * runningIndicatorScale))
    }

    private var runningIndicatorScale: CGFloat {
        let baseScale = max(0.5, min(1, effectiveTileSize / 48))
        return baseScale * max(0.25, preferences.effectiveActiveIndicatorScale)
    }

    private var runningIndicatorOffsetVector: CGSize {
        let baseInward = max((layout.scaled(preferences.effectiveTileVerticalPadding) / 2), 2)
        let totalInward = baseInward + preferences.effectiveActiveIndicatorOffset

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
            layout.scaled(preferences.effectiveTileVerticalPadding)
        }
    }

    private var contentPaddingEdges: Edge.Set {
        position.isVertical ? .horizontal : .vertical
    }

    private var nonAppContentPadding: CGFloat {
        // Per-span widget override wins for widget-hosting tiles ,
        // a theme/user can collapse padding to 0 on 2x/3x widgets for
        // an edge-to-edge taskbar look without touching 1x.
        if let span = widgetRenderedSpan,
           let override = preferences.effectiveWidgetContentPadding(for: span) {
            return override
        }
        switch tile.content {
        case .app(let app) where app.displayedWidget != nil:
            return tileChromeInset
        case .appFolder, .widget, .smartStack, .folder, .trash:
            return tileChromeInset
        case .app, .launchpad, .startMenu, .minimizedWindow, .spacer, .flexibleSpacer, .divider:
            return 0
        }
    }

    /// Resolved tile icon padding. Widget tiles whose span opts out
    /// (via the theme's `ignoresAddedPaddings` escape hatch) collapse
    /// to zero so the widget can fill its tile box, needed when a
    /// theme adds icon padding for chunky app tiles but wants 2x/3x
    /// widgets edge-to-edge.
    private var appliedTileIconPadding: CGFloat {
        if let span = widgetRenderedSpan,
           preferences.effectiveWidgetIgnoresAddedPaddings(for: span) {
            return 0
        }
        return layout.scaled(preferences.effectiveTileIconPadding)
    }

    /// Returns the widget's *rendered* span (compressed to .one when
    /// overflow compaction or vertical orientation forces it) for any
    /// tile that hosts a widget. `nil` for non-widget tiles.
    private var widgetRenderedSpan: TileSpan? {
        switch tile.content {
        case .widget(let widget):
            return renderedWidgetSpan(for: widget.effectiveSpan)
        case .smartStack(let stack):
            return renderedWidgetSpan(for: stack.span)
        case .app(let app) where app.displayedWidget != nil:
            return renderedWidgetSpan(for: app.displayedWidget?.effectiveSpan ?? .one)
        default:
            return nil
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
        renderedTileSize ?? layout.scaled(dockSettings.displayTileSize)
    }

    private func renderedWidgetSpan(for span: TileSpan) -> TileSpan {
        if layout.compactsWidgetsForOverflow || position.isVertical {
            return .one
        }

        return span
    }

    private var availableWidgetSpans: [TileSpan] {
        // `.four` is theme-only: it can be injected via
        // `layout.insertions` but is not surfaced in the user's "Span"
        // submenu / palette so the widget editor stays focused on the
        // three user-facing sizes.
        let userFacing = TileSpan.allCases.filter { $0 != .four }
        return position.isVertical ? [.one] : userFacing
    }

    private var nonAppTileCornerRadius: CGFloat {
        let maximumCornerRadius = max(0, (effectiveTileSize - nonAppContentPadding * 2) / 2)
        // Per-span override wins for widget tiles. Clamp to the
        // maximum so a theme that sets `cornerRadius: 999` doesn't
        // produce a malformed clip when the tile is small.
        if let span = widgetRenderedSpan,
           let override = preferences.effectiveWidgetCornerRadius(for: span) {
            return min(override, maximumCornerRadius)
        }
        return preferences.effectiveTileClipShape.resolvedCornerRadius(
            base: effectiveTileSize * 0.225,
            maximum: maximumCornerRadius
        )
    }

    /// Corner radius used when painting the app-folder-drop intent backdrop
    /// behind a plain `.app` tile. Mirrors `AppFolderTileView.iconGrid`'s
    /// container so the in-progress folder visually matches a finished one.
    private var appFolderDropTargetCornerRadius: CGFloat {
        let maximumCornerRadius = max(0, effectiveTileSize / 2)
        return preferences.effectiveTileClipShape.resolvedCornerRadius(
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
                    clipShape: preferences.effectiveTileClipShape,
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
                clipShape: preferences.effectiveTileClipShape,
                transparencyCompensationInset: 0,
                iconOverrideURL: preferences.effectiveLaunchpadIconOverrideURL,
                iconOverridePaddingFraction: preferences.launchpadIconPaddingFraction
            )
        case .startMenu(let menu):
            AppTileView(
                tile: AppTile(
                    bundleIdentifier: StartMenuTile.iconBundleIdentifier,
                    displayName: menu.title
                ),
                clipShape: preferences.effectiveTileClipShape,
                transparencyCompensationInset: 0,
                iconOverrideURL: preferences.effectiveStartMenuIconOverrideURL,
                iconOverridePaddingFraction: preferences.effectiveStartMenuIconOverridePadding
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
        case .spacer, .flexibleSpacer:
            SpacerTileView()
        case .divider:
            DividerTileView(tileID: tile.id)
        case .trash:
            TrashTileView(isDropTarget: isTrashDropTarget)
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
        case .startMenu(let menu):
            menu.title
        case .widget(let widget):
            widget.title
        case .smartStack(let stack):
            stack.title
        case .folder(let folder):
            folder.displayName
        case .trash:
            "Trash"
        case .spacer, .flexibleSpacer, .divider:
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
    /// and `.appFolder` tiles participate, the app-folder case aggregates
    /// windows from every contained app.
    private func updateWindowPreviewPresentation(isHovering: Bool) {
        // Freeze preview state while a context menu is open on this tile ,
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
        let candidate: WidgetTile?
        switch tile.content {
        case .widget(let widget):
            candidate = widget
        case .app(let app) where app.displayedWidget != nil:
            candidate = app.displayedWidget
        default:
            candidate = nil
        }
        guard let candidate, candidate.kind.isExpandable else { return nil }
        return candidate
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
            // already on screen, the context menu takes over input and
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

    private var tileContentKindDescription: String {
        switch tile.content {
        case .app: return "app"
        case .minimizedWindow: return "minimizedWindow"
        case .appFolder: return "appFolder"
        case .folder: return "folder"
        case .launchpad: return "launchpad"
        case .startMenu: return "startMenu"
        case .widget: return "widget"
        case .smartStack: return "smartStack"
        case .trash: return "trash"
        case .spacer: return "spacer"
        case .flexibleSpacer: return "flexibleSpacer"
        case .divider: return "divider"
        }
    }

    private func handleTap() {
        Self.logger.info("handleTap tileID=\(tile.id, privacy: .public) contentKind=\(tileContentKindDescription, privacy: .public)")
        // Tap-to-act always supersedes the hover preview.
        windowPreviewDelayTask?.cancel()
        windowPreviewDelayTask = nil
        WindowPreviewWindowController.shared.dismiss(sourceTileID: tile.id)

        // If the Start menu is open, taps on other tiles should dismiss
        // it (the dock-window event monitor stays out of the way so the
        // tile's own logic can run). Skip the tiles that own the toggle:
        // start-menu tile, and Finder when the override is enabled.
        if StartMenuService.shared.isPresented {
            let ownsStartMenuToggle: Bool
            switch tile.content {
            case .startMenu:
                ownsStartMenuToggle = true
            case .app(let app) where app.bundleIdentifier == "com.apple.finder"
                 && preferences.opensStartMenuFromFinderTile
                 && preferences.enablesStartMenuOverlay:
                ownsStartMenuToggle = true
            default:
                ownsStartMenuToggle = false
            }
            if !ownsStartMenuToggle {
                StartMenuService.shared.dismiss()
            }
        }

        switch tile.content {
        case .app(let app):
            isTooltipPresented = false
            // Finder override: when the preference is on, clicking the
            // Finder tile opens the Start menu instead of activating
            // Finder. Gated on the Start menu being enabled so flipping
            // that toggle off keeps the tile behaving normally.
            if app.bundleIdentifier == "com.apple.finder",
               preferences.opensStartMenuFromFinderTile,
               preferences.enablesStartMenuOverlay {
                StartMenuService.shared.toggle()
                return
            }
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
        case .startMenu:
            isTooltipPresented = false
            guard preferences.enablesStartMenuOverlay else { return }
            StartMenuService.shared.toggle()
        case .widget(let widget):
            isTooltipPresented = false
            handleWidgetTap(widget)
        case .smartStack:
            isTooltipPresented = false
            return
        case .folder(let folder):
            isTooltipPresented = false

            if folderContentViewMode == .finder {
                isFolderPopoverPresented = false
                Task {
                    _ = await AppleScriptService.shared.openFinderWindow(for: folder.url)
                }
                return
            }

            if folderContentViewMode == .list {
                isFolderPopoverPresented = false
                guard !isFolderListMenuPresented else { return }
                isFolderListMenuPresented = true
                return
            }

            if isFolderPopoverPresented {
                // In fan mode the dismissal is animated by the fan
                // window's own click-away monitor, which has already
                // fired by the time this tap reaches `handleTap`.
                // Flipping the binding here would race that animation
                // — the tile's `isOpen` would go false and reveal
                // the preview stack underneath while the fan items
                // are still sliding back to the tile. Bail out and
                // let the fan's `tearDown` flip the binding when the
                // close animation finishes.
                if folderContentViewMode == .fan {
                    return
                }

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
        case .spacer, .flexibleSpacer, .divider:
            return
        }
    }

    /// Children for the "View Content as" submenu on a folder tile.
    /// Always shows Grid and List; only shows Fan when the dock is at
    /// the bottom edge, since Fan rendering is hard-coded to sweep
    /// upward from the tile and only works visually for `.bottom`.
    private func viewContentSubmenuChildren(folder: FolderTile) -> [ContextAction] {
        var children: [ContextAction] = [
            .action(String(localized: "Grid"), isOn: folderContentViewMode == .grid) {
                TileStore.shared.setFolderContentViewMode(tileID: tile.id, folderURL: folder.url, mode: .grid)
            },
            .action(String(localized: "List"), isOn: folderContentViewMode == .list) {
                TileStore.shared.setFolderContentViewMode(tileID: tile.id, folderURL: folder.url, mode: .list)
            }
        ]

        if position == .bottom {
            children.append(
                .action(String(localized: "Fan"), isOn: folderContentViewMode == .fan) {
                    TileStore.shared.setFolderContentViewMode(tileID: tile.id, folderURL: folder.url, mode: .fan)
                }
            )
        }

        children.append(.divider)
        children.append(
            .action(String(localized: "Finder Window"), isOn: folderContentViewMode == .finder) {
                TileStore.shared.setFolderContentViewMode(tileID: tile.id, folderURL: folder.url, mode: .finder)
            }
        )

        return children
    }

    private func appFolderContextActions(for folder: AppFolderTile) -> [ContextAction] {
        var actions = customDockyTileActions

        if !folder.apps.isEmpty {
            if !actions.isEmpty {
                actions.append(.divider)
            }
            actions.append(.action(String(localized: "Open All")) {
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
                .action(String(localized: "Open")) {
                    WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
                },
                .action(String(localized: "Remove from Folder")) {
                    TileStore.shared.removeAppFromFolder(tileID: tile.id, bundleIdentifier: app.bundleIdentifier)
                }
            ])
        }

        if !appActions.isEmpty {
            if !actions.isEmpty {
                actions.append(.divider)
            }
            actions.append(.submenu(String(localized: "Apps"), children: appActions))
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

        return .submenu(String(localized: "Windows"), children: children)
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
        let withFinder = injectingFinderHomeNavigation(into: withWindows, for: app)
        return injectingRemoveFromFolder(into: withFinder, for: app)
    }

    /// Tile id format for inline / grouped-opened children of an app folder:
    /// `folder-running:<folderID>:<bundleIdentifier>`. When the tile under
    /// the cursor matches this shape, surface a "Remove from Folder" action
    /// so the user has a non-drag path to detach the app from its folder.
    private func injectingRemoveFromFolder(
        into actions: [ContextAction],
        for app: AppTile
    ) -> [ContextAction] {
        let prefix = "folder-running:"
        let suffix = ":\(app.bundleIdentifier)"
        guard tile.id.hasPrefix(prefix),
              tile.id.hasSuffix(suffix),
              tile.id.count > prefix.count + suffix.count else {
            return actions
        }
        // Inline-child tile ids embed the folder's raw identifier; the
        // store looks folders up by their pinned-tile id ("pinned:<id>"),
        // so re-prefix before calling removeAppFromFolder.
        let rawFolderID = String(tile.id.dropFirst(prefix.count).dropLast(suffix.count))
        let folderTileID = "pinned:\(rawFolderID)"
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
                tileID: folderTileID,
                bundleIdentifier: bundleIdentifier
            )
        })
        return result
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

        // Touch the singleton so its Spotlight query is running by the
        // time the user opens the menu. First-ever right-click may still
        // produce an empty list until the initial gather finishes.
        _ = RecentFilesService.shared
        let recentEntries = recentFilesContextActions()

        var result: [ContextAction] = [homeSubmenu]
        if !recentEntries.isEmpty {
            result.append(.divider)
            result.append(contentsOf: recentEntries)
        }
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
            result[optionsIndex] = .submenu(String(localized: "Options"), children: children)
            return result
        }

        if !result.isEmpty, result.last?.kind != .divider {
            result.append(.divider)
        }
        result.append(.submenu(String(localized: "Options"), children: dockyOptions))
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
            .action(String(localized: "Open")) {
                workspace.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
            }
        ]

        if isRunning {
            actions.append(.action(String(localized: "Show All Windows")) {
                workspace.showAllWindows(bundleIdentifier: app.bundleIdentifier)
            })
        }

        actions.append(.divider)
        actions.append(.submenu(String(localized: "Options"), children: appOptionsActions(for: app, isPinned: isPinned, canTogglePinned: canTogglePinned)))

        if isDockyPinnedTile || isDockyTrailingTile {
            actions.append(.divider)
            actions.append(.action(String(localized: "Remove from Dock")) {
                removeDockyTile()
            })
        }

        if isRunning && app.bundleIdentifier != Self.finderBundleIdentifier {
            actions.append(.divider)
            actions.append(.action(String(localized: "Hide")) {
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
            .action(String(localized: "Restore Window")) {
                _ = workspace.restoreMinimizedWindow(window)
            },
            .action(String(localized: "Close Window")) {
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
            actions.append(.action(String(localized: "Keep in Dock"), isOn: isPinned) {
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

        actions.append(.action(String(localized: "Show in Finder")) {
            WorkspaceService.shared.revealApplicationInFinder(bundleIdentifier: app.bundleIdentifier)
        })

        return actions
    }

    private func hideInDockyAction(for app: AppTile) -> ContextAction? {
        guard app.bundleIdentifier != Self.finderBundleIdentifier,
              !preferences.isAppHiddenInDocky(bundleIdentifier: app.bundleIdentifier) else {
            return nil
        }

        return .action(String(localized: "Hide in Docky")) {
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
            .action(String(localized: "App Icon"), isOn: currentKind == nil) {
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
                actions.append(.submenu(String(localized: "Span"), children: availableSpans.map { span in
                    .action(spanTitle(for: span), isOn: configuredDisplay.span == span) {
                        TileStore.shared.setAppWidgetDisplaySpan(
                            bundleIdentifier: app.bundleIdentifier,
                            span: span
                        )
                    }
                }))
            }
        }

        return .submenu(String(localized: "Show as Widget"), children: actions)
    }

    private func widgetContextActions(for widget: WidgetTile) -> [ContextAction] {
        switch widget.kind {
        case .calendar:
            var actions: [ContextAction] = []

            if let quickJoinURL = CalendarService.shared.nextEvent?.quickJoinURL {
                actions.append(.action(String(localized: "Quick Join")) {
                    NSWorkspace.shared.open(quickJoinURL)
                })
            }

            if let spanMenuAction = widgetSpanMenuAction(for: widget) {
                appendDividerIfNeeded(to: &actions)
                actions.append(spanMenuAction)
            }

            appendDividerIfNeeded(to: &actions)
            actions.append(.action(String(localized: "Refresh Calendar")) {
                CalendarService.shared.refresh(force: true)
            })
            actions.append(.divider)
            actions.append(.action(String(localized: "Open Calendar")) {
                WorkspaceService.shared.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.calendar)
            })
            actions.append(.divider)
            actions.append(widgetRemovalAction(for: widget))
            return actions
        case .calendarDate:
            return [
                .action(String(localized: "Open Calendar")) {
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
                actions.append(.submenu(String(localized: "Complete"), children: completionActions))
            }

            if let spanMenuAction = widgetSpanMenuAction(for: widget) {
                appendDividerIfNeeded(to: &actions)
                actions.append(spanMenuAction)
            }

            appendDividerIfNeeded(to: &actions)
            actions.append(.action(String(localized: "Refresh Reminders")) {
                RemindersService.shared.refresh(force: true)
            })
            actions.append(.divider)
            actions.append(.action(String(localized: "Open Reminders")) {
                WorkspaceService.shared.activateOrOpen(bundleIdentifier: WidgetOwnerBundleIdentifiers.reminders)
            })
            actions.append(.divider)
            actions.append(widgetRemovalAction(for: widget))
            return actions
        case .batteries:
            var actions: [ContextAction] = [
                .action(String(localized: "Refresh Batteries")) {
                    BatteriesService.shared.refresh(force: true)
                }
            ]

            if let spanMenuAction = widgetSpanMenuAction(for: widget) {
                actions.append(.divider)
                actions.append(spanMenuAction)
            }

            actions.append(.divider)
            actions.append(.action(String(localized: "Open Battery Settings")) {
                BatteriesService.shared.openInBatterySettings()
            })
            actions.append(.divider)
            actions.append(widgetRemovalAction(for: widget))
            return actions
        case .systemStatus:
            var actions: [ContextAction] = [
                .action(String(localized: "Refresh Status")) {
                    SystemStatusService.shared.refresh(force: true)
                }
            ]

            if let spanMenuAction = widgetSpanMenuAction(for: widget) {
                actions.append(.divider)
                actions.append(spanMenuAction)
            }

            actions.append(.divider)
            actions.append(.action(String(localized: "Open Activity Monitor")) {
                SystemStatusService.shared.openInActivityMonitor()
            })
            actions.append(.divider)
            actions.append(widgetRemovalAction(for: widget))
            return actions
        case .nowPlaying:
            var actions: [ContextAction] = []

            if let bundleIdentifier = mediaPlayback.resolvedBundleIdentifier(for: widget.ownerBundleIdentifier) {
                actions.append(.action(String(localized: "Open App")) {
                    WorkspaceService.shared.activateOrOpen(bundleIdentifier: bundleIdentifier)
                })
                actions.append(.divider)
            }

            actions.append(contentsOf: [
                .action(String(localized: "Play/Pause")) {
                    Task {
                        await mediaPlayback.togglePlayPause(for: widget.ownerBundleIdentifier)
                    }
                },
                .action(String(localized: "Previous Track")) {
                    Task {
                        await mediaPlayback.skipToPrevious(for: widget.ownerBundleIdentifier)
                    }
                },
                .action(String(localized: "Next Track")) {
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
                .action(String(localized: "Refresh Weather")) {
                    WeatherService.shared.refresh(force: true)
                }
            ]

            if let spanMenuAction = widgetSpanMenuAction(for: widget) {
                actions.append(.divider)
                actions.append(spanMenuAction)
            }

            actions.append(.divider)
            actions.append(.action(String(localized: "Open Weather")) {
                WeatherService.shared.openInWeatherApp()
            })
            actions.append(.divider)
            actions.append(widgetRemovalAction(for: widget))
            return actions
        case .search:
            var actions: [ContextAction] = []
            if let spanMenuAction = widgetSpanMenuAction(for: widget) {
                actions.append(spanMenuAction)
                actions.append(.divider)
            }
            actions.append(.action(String(localized: "Open Google")) {
                if let url = URL(string: "https://www.google.com") {
                    NSWorkspace.shared.open(url)
                }
            })
            actions.append(.divider)
            actions.append(widgetRemovalAction(for: widget))
            return actions
        case .external:
            var actions: [ContextAction] = []
            if let spanMenuAction = widgetSpanMenuAction(for: widget) {
                actions.append(spanMenuAction)
                actions.append(.divider)
            }
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

        return .submenu(String(localized: "Span"), children: availableSpans.map { span in
            ContextAction.action(spanTitle(for: span), isOn: widget.span == span) {
                applyWidgetSpan(span)
            }
        })
    }

    private func availableWidgetSpans(for widget: WidgetTile) -> [TileSpan] {
        if position.isVertical {
            return [.one]
        }

        return widget.kind.supportedSpans.filter { $0 != .four }
    }

    private func availableAppWidgetSpans(for kind: WidgetKind) -> [TileSpan] {
        if position.isVertical {
            return [.one]
        }

        return kind.supportedSpans.filter { $0 != .four }
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
            return .action(String(localized: "Remove from Dock")) {
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
            actions.append(.submenu(String(localized: "Widgets"), children: widgetVisibilityActions))
        }

        if isDockyPinnedTile || isDockyTrailingTile {
            if !actions.isEmpty {
                actions.append(.divider)
            }
            actions.append(.action(String(localized: "Edit Dock...")) {
                DockEditModeService.shared.enter()
            })
            actions.append(.action(String(localized: "Remove from Dock")) {
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
        case .search:
            // 2x / 3x widgets render an inline text field, clicks there
            // should focus the field, not open Google. Only the 1x form
            // (no text input fits) acts as a one-click Google launcher.
            if widget.effectiveSpan == .one,
               let url = URL(string: "https://www.google.com") {
                NSWorkspace.shared.open(url)
            }
        case .external:
            break
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
        case .four:
            "4 Tiles"
        }
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
    /// Changes whenever the anchor view's bounds change (e.g., magnification
    /// reshaping the tile under the cursor). Forces `updateNSView` to fire
    /// so the popover can resync `positioningRect` to the new bounds ,
    /// otherwise it stays pinned to the resting bounds captured at show
    /// time and ends up under the magnified icon.
    let repositionKey: CGFloat

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
            // NSPopover does not reliably recenter its pointer arrow when
            // contentSize changes on a live popover, leaving the arrow
            // offset from the (resized) bubble when the title width changes
            // (e.g. folder rename). Close so the next show() reopens with
            // the arrow correctly centered against the new bubble width.
            if popover.isShown {
                popover.close()
            }
        }

        func show(relativeTo view: NSView) {
            guard view.window != nil else { return }
            let anchorRect = anchorRect(in: view.bounds)
            if popover.isShown {
                popover.positioningRect = anchorRect
            } else {
                popover.show(relativeTo: anchorRect, of: view, preferredEdge: preferredEdge)
            }
        }

        func close() {
            popover.performClose(nil)
        }

        private func updateContentSize() {
            // sizeThatFits asks SwiftUI to measure the rootView for the given
            // proposed size and works whether or not the hosting view is in a
            // window. view.fittingSize is unreliable when the popover is
            // hidden (e.g. while the grid popover is open), so a rename in
            // that state would leave contentSize stale, and the next hover
            // would show a bubble whose width didn't match its arrow.
            let size = hostingController.sizeThatFits(
                in: NSSize(width: CGFloat.greatestFiniteMagnitude,
                           height: CGFloat.greatestFiniteMagnitude)
            )
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
        /// Estimated height (pt) per NSMenuItem row that carries a 16x16 image
        /// + single-line title. Used to derive how many items fit in the
        /// menu's screen before macOS would force scroll arrows.
        private static let menuRowHeight: CGFloat = 22
        /// Vertical padding reserved for: menu top/bottom inset, the
        /// "Open in Finder" item + separator, the "Show More" item itself.
        private static let reservedMenuChrome: CGFloat = 72
        /// Hard floor so we never collapse the menu absurdly small even on
        /// a tiny external display.
        private static let minimumInlineItemLimit: Int = 20
        /// Extra rows shaved off the fits-on-screen count so the menu
        /// doesn't kiss the screen edge — keeps the "Show More" item
        /// comfortably above the bottom of the visible area.
        private static let inlineItemSafetyMargin: Int = 5

        private var tile: FolderTile
        private var isPresented: Binding<Bool>
        private var preferredEdge: NSRectEdge
        private weak var anchorView: NSView?
        private var isShowing = false
        private var isInterruptingAutohide = false
        private var folderURLByMenuID: [ObjectIdentifier: URL] = [:]
        private var inlineItemLimit: Int = 60

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
            inlineItemLimit = Self.computeInlineItemLimit(
                for: view.window?.screen ?? NSScreen.main,
                dockWindowFrame: view.window?.frame
            )
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
                } else if sortedItemURLs.count > inlineItemLimit {
                    for itemURL in sortedItemURLs.prefix(inlineItemLimit) {
                        menu.addItem(menuItem(for: itemURL))
                    }
                    let overflowCount = sortedItemURLs.count - inlineItemLimit
                    let showMoreItem = NSMenuItem(title: "Show More (\(overflowCount))", action: nil, keyEquivalent: "")
                    let overflowMenu = NSMenu(title: showMoreItem.title)
                    for itemURL in sortedItemURLs.dropFirst(inlineItemLimit) {
                        overflowMenu.addItem(menuItem(for: itemURL))
                    }
                    showMoreItem.submenu = overflowMenu
                    menu.addItem(showMoreItem)
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

        private static func computeInlineItemLimit(for screen: NSScreen?, dockWindowFrame: CGRect?) -> Int {
            let visibleHeight = screen?.visibleFrame.height ?? 800
            // Only subtract dock chrome when Docky is horizontal (top/bottom) —
            // a vertical dock spans the screen's height and doesn't shrink
            // the menu's vertical headroom.
            let dockChromeHeight: CGFloat = {
                guard let dockWindowFrame else { return 0 }
                return dockWindowFrame.width > dockWindowFrame.height ? dockWindowFrame.height : 0
            }()
            let usableHeight = max(0, visibleHeight - reservedMenuChrome - dockChromeHeight)
            let fittedCount = Int((usableHeight / menuRowHeight).rounded(.down))
            return max(minimumInlineItemLimit, fittedCount - inlineItemSafetyMargin)
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
        /// the drag ends, drop on us, drop elsewhere, or cancel.
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
        return [.action(String(localized: "Can't read folder")) {}]
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
    actions.append(.action(String(localized: "Open in Finder"), image: contextMenuSymbol("folder")) {
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
        .action(String(localized: "Open"), image: contextMenuSymbol("arrow.up.forward.app")) {
            NSWorkspace.shared.open(url)
        },
        .lazySubmenu(String(localized: "Open With"), image: contextMenuSymbol("app.badge")) {
            openWithApplicationActions(for: url)
        },
        .action(String(localized: "Reveal in Finder"), image: contextMenuSymbol("folder")) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        },
        .divider,
        .action(String(localized: "Copy"), image: contextMenuSymbol("doc.on.doc")) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
        },
        .lazySubmenu(String(localized: "Share"), image: contextMenuSymbol("square.and.arrow.up")) {
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

@MainActor
func recentFilesContextActions() -> [ContextAction] {
    let urls = RecentFilesService.shared.recentURLs
    Logger(subsystem: "gt.quintero.Docky", category: "RecentFiles")
        .info("menu requested urls.count=\(urls.count, privacy: .public)")
    guard !urls.isEmpty else { return [] }

    let visibleLimit = 10
    let visible = urls.prefix(visibleLimit)
    let overflow = Array(urls.dropFirst(visibleLimit))

    var actions: [ContextAction] = visible.map(recentFileContextAction)

    if !overflow.isEmpty {
        actions.append(.lazySubmenu(String(localized: "More"), image: contextMenuSymbol("ellipsis")) {
            overflow.map(recentFileContextAction)
        })
    }

    return actions
}

@MainActor
private func recentFileContextAction(for url: URL) -> ContextAction {
    let displayName = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
        ?? url.lastPathComponent
    let icon = IconCacheService.shared.icon(forFileURL: url)
    return .lazySubmenu(displayName, image: icon) {
        fileContextActions(for: url)
    }
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

    var result = windowActions
    if !actions.isEmpty {
        result.append(.divider)
        result.append(contentsOf: actions)
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
        return [.action(String(localized: "No Applications Available")) {}]
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
        return [.action(String(localized: "No Sharing Options")) {}]
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
