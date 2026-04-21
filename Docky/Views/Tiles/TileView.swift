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
    @State private var isContextMenuPresented = false
    @State private var folderSnapshot: FolderContentsSnapshot = .loaded([])
    @State private var lastFolderPopoverDismissedAt: TimeInterval = 0

    private static let finderBundleIdentifier = "com.apple.finder"
    private static let folderPopoverRetapGuardInterval: TimeInterval = 0.25

    private func contextActions(modifierFlags: NSEvent.ModifierFlags) -> [ContextAction] {
        if let catalogActions = MenuCatalogService.shared.contextActions(for: tile, modifierFlags: modifierFlags) {
            switch tile.content {
            case .app, .folder, .trash:
                return catalogActions
            case .widget, .smartStack, .spacer, .divider:
                break
            }
        }

        switch tile.content {
        case .app(let app):
            return appContextActions(for: app, modifierFlags: modifierFlags)
        case .widget(let widget):
            return widgetContextActions(for: widget)
        case .smartStack:
            return []
        case .folder(let folder):
            return [
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
            return customPinnedTileActions
        }
    }

    private var customPinnedTileActions: [ContextAction] {
        guard tile.id.hasPrefix("pinned:") else {
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
                TileStore.shared.removePinnedItem(tileID: tile.id)
            })
        }

        if case .divider = tile.content {
            actions.append(.divider)
            actions.append(.action("Remove from Dock") {
                TileStore.shared.removePinnedItem(tileID: tile.id)
            })
        }

        return actions
    }

    var body: some View {
        content
            .padding(contentPaddingEdges, contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .overlay(alignment: runningIndicatorAlignment) {
                runningIndicator
                    .padding(runningIndicatorEdge, 2)
            }
            .contentShape(Rectangle())
            .onHover(perform: updateHoverState)
            .onTapGesture(perform: handleTap)
            .onDisappear {
                isHovering = false
                isTooltipPresented = false
                isFolderPopoverPresented = false
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
            }
    }

    @ViewBuilder
    private var runningIndicator: some View {
        if case .app(let app) = tile.content,
           workspace.isRunning(bundleIdentifier: app.bundleIdentifier) {
            runningIndicatorShape
                .frame(width: runningIndicatorSize.width, height: runningIndicatorSize.height)
                .foregroundStyle(.primary.opacity(0.9))
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
            CGSize(width: 4, height: 4)
        case .pill:
            if position.isVertical {
                CGSize(width: 4, height: 12)
            } else {
                CGSize(width: 12, height: 4)
            }
        }
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
        case .widget(let widget):
            WidgetTileView(tile: widget)
        case .smartStack(let stack):
            SmartStackTileView(tile: stack)
        case .folder(let folder):
            FolderTileView(tile: folder, isOpen: isFolderPopoverPresented)
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
            && !isContextMenuPresented
    }

    private func handleTap() {
        switch tile.content {
        case .app(let app):
            isTooltipPresented = false
            WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
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

            actions.append(.divider)
            actions.append(.action("Remove Stack") {
                TileStore.shared.removeWidget(
                    kind: widget.kind,
                    ownerBundleIdentifier: widget.ownerBundleIdentifier
                )
            })
            return actions
        }
    }

    private func handleWidgetTap(_ widget: WidgetTile) {
        switch widget.kind {
        case .nowPlaying:
            Task {
                await mediaPlayback.togglePlayPause(for: widget.ownerBundleIdentifier)
            }
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
                tile: FolderTile(url: URL(fileURLWithPath: "/"), displayName: ""),
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
