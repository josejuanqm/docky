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
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var workspace = WorkspaceService.shared
    @ObservedObject private var mediaPlayback = MediaPlaybackService.shared
    @State private var isHovering = false
    @State private var isTooltipPresented = false
    @State private var isFolderPopoverPresented = false
    @State private var isAppFolderPopoverPresented = false
    @State private var isContextMenuPresented = false
    @State private var folderSnapshot: FolderContentsSnapshot = .loaded([])
    @State private var lastFolderPopoverDismissedAt: TimeInterval = 0

    private static let finderBundleIdentifier = "com.apple.finder"
    private static let folderPopoverRetapGuardInterval: TimeInterval = 0.25

    private func contextActions(modifierFlags: NSEvent.ModifierFlags) -> [ContextAction] {
        if let catalogActions = MenuCatalogService.shared.contextActions(for: tile, modifierFlags: modifierFlags) {
            switch tile.content {
            case .app, .trash:
                return catalogActions
            case .folder:
                var actions = folderDisplayContextActions + [.divider] + catalogActions
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
        case .widget(let widget):
            return widgetContextActions(for: widget)
        case .smartStack(let stack):
            return smartStackContextActions(for: stack)
        case .folder(let folder):
            var actions = folderDisplayContextActions + [.divider,
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

    private var folderDisplayContextActions: [ContextAction] {
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
            ])
        ]
    }

    private var folderDisplayMode: FolderTileDisplayMode {
        guard case .folder(let folder) = tile.content else {
            return .contents
        }
        return TileStore.shared.folderDisplayMode(tileID: tile.id, folderURL: folder.url)
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
            actions.append(.action("Rename Folder...") {
                TileStore.shared.presentRenameAppFolderPrompt(tileID: tile.id)
            })
            actions.append(.action("Ungroup Folder") {
                TileStore.shared.ungroupAppFolder(tileID: tile.id)
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

    var body: some View {
        laidOutContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .overlay(alignment: runningIndicatorAlignment) {
                runningIndicator
                    .padding(runningIndicatorEdge, runningIndicatorInset)
                    .offset(y: -2)
            }
            .contentShape(Rectangle())
            .onHover(perform: updateHoverState)
            .onTapGesture(perform: handleTap)
            .onDisappear {
                isHovering = false
                isTooltipPresented = false
                isFolderPopoverPresented = false
                isAppFolderPopoverPresented = false
                isContextMenuPresented = false
            }
            .onChange(of: isFolderPopoverPresented) { _, isPresented in
                guard !isPresented else { return }
                lastFolderPopoverDismissedAt = Date.timeIntervalSinceReferenceDate
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
                    FolderPopoverPresenter(
                        tile: folder,
                        initialSnapshot: folderSnapshot,
                        isPresented: $isFolderPopoverPresented,
                        preferredEdge: inwardPopoverEdge
                    )
                }

                if case .appFolder(let folder) = tile.content {
                    AppFolderPopoverPresenter(
                        tile: folder,
                        isPresented: $isAppFolderPopoverPresented,
                        preferredEdge: inwardPopoverEdge
                    )
                }
            }
    }

    @ViewBuilder
    private var laidOutContent: some View {
        switch tile.content {
        case .appFolder, .widget, .smartStack:
            GeometryReader { proxy in
                content
                    .frame(
                        width: max(0, proxy.size.width - contentInsets.width * 2),
                        height: max(0, proxy.size.height - contentInsets.height * 2)
                    )
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        case .folder, .trash:
            GeometryReader { _ in
                content
                    .padding(contentPaddingEdges, contentPadding)
            }
        case .app, .minimizedWindow, .spacer, .divider:
            content
                .padding(contentPaddingEdges, contentPadding)
        }
    }

    @ViewBuilder
    private var runningIndicator: some View {
        if showsRunningIndicator {
            runningIndicatorShape
                .frame(width: runningIndicatorSize.width, height: runningIndicatorSize.height)
                .foregroundStyle(.primary.opacity(0.9))
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
        case .widget, .smartStack, .folder, .spacer, .divider, .trash:
            false
        }
    }

    @ViewBuilder
    private var runningIndicatorShape: some View {
        switch preferences.activeIndicatorShape {
        case .dot:
            Circle()
        case .pill:
            Capsule()
        }
    }

    private var runningIndicatorSize: CGSize {
        switch preferences.activeIndicatorShape {
        case .dot:
            CGSize(width: runningIndicatorThickness, height: runningIndicatorThickness)
        case .pill:
            if position.isVertical {
                CGSize(width: runningIndicatorThickness, height: runningIndicatorLength)
            } else {
                CGSize(width: runningIndicatorLength, height: runningIndicatorThickness)
            }
        }
    }

    private var runningIndicatorThickness: CGFloat {
        4 * runningIndicatorScale
    }

    private var runningIndicatorLength: CGFloat {
        12 * runningIndicatorScale
    }

    private var runningIndicatorInset: CGFloat {
        max(1, round(2 * runningIndicatorScale))
    }

    private var runningIndicatorScale: CGFloat {
        max(0.5, min(1, effectiveTileSize / 48))
    }

    private var contentPadding: CGFloat {
        switch tile.content {
        case .divider:
            0
        default:
            preferences.tileVerticalPadding
        }
    }

    private var contentPaddingEdges: Edge.Set {
        position.isVertical ? .horizontal : .vertical
    }

    private var nonAppContentPadding: CGFloat {
        switch tile.content {
        case .appFolder, .widget, .smartStack, .folder, .trash:
            floor(effectiveTileSize * 3 / 32)
        case .app, .minimizedWindow, .spacer, .divider:
            0
        }
    }

    private var contentInsets: CGSize {
        CGSize(
            width: nonAppContentPadding + (position.isVertical ? contentPadding : 0),
            height: nonAppContentPadding + (position.isVertical ? 0 : contentPadding)
        )
    }

    private var effectiveTileSize: CGFloat {
        dockSettings.magnification ? dockSettings.largeSize : dockSettings.tileSize
    }

    private func renderedWidgetSpan(for span: TileSpan) -> TileSpan {
        effectiveTileSize < 50 ? .one : span
    }

    private var nonAppTileCornerRadius: CGFloat {
        effectiveTileSize * 0.225
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
            AppTileView(tile: app)
        case .minimizedWindow(let window):
            MinimizedWindowTileView(tile: window)
        case .appFolder(let folder):
            AppFolderTileView(
                tile: folder,
                cornerRadius: nonAppTileCornerRadius
            )
        case .widget(let widget):
            WidgetTileView(
                tile: widget,
                cornerRadius: nonAppTileCornerRadius,
                renderedSpan: renderedWidgetSpan(for: widget.span),
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
                    displayMode: folderDisplayMode
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
            && !isAppFolderPopoverPresented
            && !isContextMenuPresented
    }

    private func handleTap() {
        switch tile.content {
        case .app(let app):
            isTooltipPresented = false
            WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        case .minimizedWindow(let window):
            isTooltipPresented = false
            _ = WorkspaceService.shared.restoreMinimizedWindow(window)
        case .appFolder:
            isTooltipPresented = false

            if isAppFolderPopoverPresented {
                isAppFolderPopoverPresented = false
                return
            }

            isAppFolderPopoverPresented = true
        case .widget(let widget):
            isTooltipPresented = false
            handleWidgetTap(widget)
        case .smartStack:
            isTooltipPresented = false
            return
        case .folder(let folder):
            isTooltipPresented = false

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
        modifierFlags: NSEvent.ModifierFlags
    ) -> [ContextAction] {
        guard !app.bundleIdentifier.isEmpty else {
            return []
        }

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
        for window: MinimizedWindowTile,
        modifierFlags: NSEvent.ModifierFlags
    ) -> [ContextAction] {
        let workspace = WorkspaceService.shared
        let app = AppTile(bundleIdentifier: window.bundleIdentifier, displayName: window.appDisplayName)
        let isPinned = TileStore.shared.isPinned(bundleIdentifier: window.bundleIdentifier)
        let canTogglePinned = window.bundleIdentifier != Self.finderBundleIdentifier
        let useForceQuit = modifierFlags.contains(.option)
        var actions: [ContextAction] = [
            .action("Restore Window") {
                _ = workspace.restoreMinimizedWindow(window)
            },
            .action("Show All Windows") {
                workspace.showAllWindows(bundleIdentifier: window.bundleIdentifier)
            },
            .divider,
            .submenu("Options", children: appOptionsActions(for: app, isPinned: isPinned, canTogglePinned: canTogglePinned))
        ]

        if workspace.isRunning(bundleIdentifier: window.bundleIdentifier)
            && window.bundleIdentifier != Self.finderBundleIdentifier {
            actions.append(.divider)
            actions.append(.action("Hide") {
                workspace.hide(bundleIdentifier: window.bundleIdentifier)
            })
            actions.append(.action(
                useForceQuit ? "Force Quit" : "Quit",
                isDestructive: useForceQuit
            ) {
                workspace.quit(bundleIdentifier: window.bundleIdentifier, force: useForceQuit)
            })
        }

        return actions
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

        actions.append(.action("Show in Finder") {
            WorkspaceService.shared.revealApplicationInFinder(bundleIdentifier: app.bundleIdentifier)
        })

        let widgetActions = widgetManagementActions(for: app.bundleIdentifier)
        if !widgetActions.isEmpty {
            actions.append(.submenu("Widgets", children: widgetActions))
        }

        return actions
    }

    private func widgetManagementActions(for ownerBundleIdentifier: String) -> [ContextAction] {
        guard MediaPlaybackService.shared.supportsWidget(bundleIdentifier: ownerBundleIdentifier) else {
            return []
        }

        let existingPlacement = TileStore.shared.widgetPlacement(
            kind: .nowPlaying,
            ownerBundleIdentifier: ownerBundleIdentifier
        )

        if existingPlacement != nil {
            let actions: [ContextAction] = [
                .action("Now Playing Stack", isOn: true) {},
                .divider,
                .action("Remove Now Playing Stack") {
                    TileStore.shared.removeWidget(
                        kind: .nowPlaying,
                        ownerBundleIdentifier: ownerBundleIdentifier
                    )
                },
            ]

            return actions
        }

        return [
            .action("Add Now Playing Stack") {
                TileStore.shared.setWidget(
                    kind: .nowPlaying,
                    ownerBundleIdentifier: ownerBundleIdentifier,
                    span: .three
                )
            }
        ]
    }

    private func widgetContextActions(for widget: WidgetTile) -> [ContextAction] {
        switch widget.kind {
        case .nowPlaying:
            var actions: [ContextAction] = [
                .action("Open App") {
                    WorkspaceService.shared.activateOrOpen(bundleIdentifier: widget.ownerBundleIdentifier)
                },
                .divider,
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
            ]

            if let playbackState = mediaPlayback.state(for: widget.ownerBundleIdentifier), playbackState.supportsFavorite {
                actions.append(.action(playbackState.isFavorite ? "Unfavorite" : "Favorite") {
                    Task {
                        await mediaPlayback.setFavorite(!playbackState.isFavorite, for: widget.ownerBundleIdentifier)
                    }
                })
            }

            if isDockyPinnedTile || isDockyTrailingTile {
                actions.append(.divider)
                actions.append(.submenu("Span", children: TileSpan.allCases.map { span in
                    ContextAction.action(spanTitle(for: span), isOn: widget.span == span) {
                        if isDockyPinnedTile {
                            TileStore.shared.setPinnedWidgetSpan(tileID: tile.id, span: span)
                        } else if isDockyTrailingTile {
                            TileStore.shared.setTrailingWidgetSpan(tileID: tile.id, span: span)
                        }
                    }
                }))
            }

            actions.append(.divider)
            if isDockyPinnedTile || isDockyTrailingTile {
                actions.append(.action("Remove from Dock") {
                    removeDockyTile()
                })
            } else {
                actions.append(.action("Remove Stack") {
                    TileStore.shared.removeWidget(
                        kind: widget.kind,
                        ownerBundleIdentifier: widget.ownerBundleIdentifier
                    )
                })
            }
            return actions
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
        case .nowPlaying:
            Task {
                await mediaPlayback.togglePlayPause(for: widget.ownerBundleIdentifier)
            }
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
                tile: FolderTile(url: URL(fileURLWithPath: "/"), displayName: "", displayMode: .contents),
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
