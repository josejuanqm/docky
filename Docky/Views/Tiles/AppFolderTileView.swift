//
//  AppFolderTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct AppFolderTileView: View {
    let tile: AppFolderTile
    let cornerRadius: CGFloat
    let suppressesGroupedOpenedBackdrop: Bool
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var layout = DockLayoutService.shared
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var store = TileStore.shared
    @ObservedObject private var workspace = WorkspaceService.shared

    init(
        tile: AppFolderTile,
        cornerRadius: CGFloat,
        suppressesGroupedOpenedBackdrop: Bool = false
    ) {
        self.tile = tile
        self.cornerRadius = cornerRadius
        self.suppressesGroupedOpenedBackdrop = suppressesGroupedOpenedBackdrop
        self._dockSettings = ObservedObject(wrappedValue: DockSettingsService.shared)
        self._layout = ObservedObject(wrappedValue: DockLayoutService.shared)
        self._preferences = ObservedObject(wrappedValue: DockyPreferences.shared)
        self._store = ObservedObject(wrappedValue: TileStore.shared)
        self._workspace = ObservedObject(wrappedValue: WorkspaceService.shared)
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
        layout.scaled(dockSettings.tileSize)
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
        groupedOpenedBackdropOffset + (position == .bottom ? 2 : 0)
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

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        GeometryReader { geo in
            iconGrid(in: geo.size)
                .background(
                    Color.primary.opacity(openedAppCount > 0 ? 0.2 : 0)
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

    private func iconGrid(in size: CGSize) -> some View {
        let displayedApps = Array(tile.apps.prefix(4))
        let side = min(size.width, size.height) * 0.36
        let gap = min(size.width, size.height) * (preferences.tileClipShape == .circle ? 0 : 0.06)

        return ZStack {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
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
                                    if preferences.tileClipShape == .circle {
                                        let inset = preferences.tileClipShape == .circle ? floor(side * 3 / 32) : 0
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
    private func gridIcon(forBundleIdentifier bundleIdentifier: String, side: CGFloat) -> some View {
        if shouldApplyCircleClip(to: bundleIdentifier) {
            baseGridIcon(forBundleIdentifier: bundleIdentifier, side: side)
                .glassEffect(.regular, in: .circle)
                .clipShape(.circle)
        } else {
            baseGridIcon(forBundleIdentifier: bundleIdentifier, side: side)
        }
    }

    private func baseGridIcon(forBundleIdentifier bundleIdentifier: String, side: CGFloat) -> some View {
        let inset = shouldApplyCircleClip(to: bundleIdentifier) ? floor(side * 3 / 32) : 0

        return Image(nsImage: icon(forBundleIdentifier: bundleIdentifier))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: side + inset * 2, height: side + inset * 2)
            .frame(width: side - inset * 2, height: side - inset * 2)
    }

    private func shouldApplyCircleClip(to bundleIdentifier: String) -> Bool {
        preferences.tileClipShape == .circle
    }

    private func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        if let overrideURL = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: bundleIdentifier),
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return IconCacheService.shared.icon(forBundleIdentifier: bundleIdentifier)
    }
}

struct AppFolderPopoverView: View {
    let tile: AppFolderTile
    @Binding var isPresented: Bool
    let onPopoverSizeChange: (CGSize) -> Void
    @ObservedObject private var preferences = DockyPreferences.shared

    private let columns = 3
    private let itemWidth: CGFloat = 112
    private let itemHeight: CGFloat = 132
    private let itemSpacing: CGFloat = 12
    private let contentPadding: CGFloat = 20
    private let headerHeight: CGFloat = 42
    private let maxHeight: CGFloat = 620

    init(
        tile: AppFolderTile,
        isPresented: Binding<Bool>,
        onPopoverSizeChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.tile = tile
        _isPresented = isPresented
        self.onPopoverSizeChange = onPopoverSizeChange
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tile.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, contentPadding)
            .padding(.top, 16)
            .frame(height: headerHeight)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: gridColumns, spacing: itemSpacing) {
                    ForEach(tile.apps, id: \.bundleIdentifier) { app in
                        Button {
                            WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
                            isPresented = false
                        } label: {
                            VStack(spacing: 8) {
                                Image(nsImage: icon(forBundleIdentifier: app.bundleIdentifier))
                                    .resizable()
                                    .interpolation(.high)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 72, height: 72)

                                Text(app.displayName)
                                    .font(.callout)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.primary)
                            }
                            .frame(width: itemWidth, height: itemHeight)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(contentPadding)
            }
        }
        .frame(width: popoverSize.width, height: popoverSize.height)
        .background(.ultraThinMaterial)
        .onAppear {
            onPopoverSizeChange(popoverSize)
        }
        .onChange(of: tile.apps.count) { _, _ in
            onPopoverSizeChange(popoverSize)
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(itemWidth), spacing: itemSpacing, alignment: .top), count: columns)
    }

    private var rowCount: Int {
        max(Int(ceil(Double(tile.apps.count) / Double(columns))), 1)
    }

    private var popoverSize: CGSize {
        let width = CGFloat(columns) * itemWidth + CGFloat(columns - 1) * itemSpacing + contentPadding * 2
        let gridHeight = CGFloat(rowCount) * itemHeight + CGFloat(max(rowCount - 1, 0)) * itemSpacing
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
}

struct AppFolderListMenuPresenter: NSViewRepresentable {
    let tile: AppFolderTile
    @Binding var isPresented: Bool
    let preferredEdge: NSRectEdge

    func makeCoordinator() -> Coordinator {
        Coordinator(tile: tile, isPresented: $isPresented, preferredEdge: preferredEdge)
    }

    func makeNSView(context: Context) -> AppFolderPopoverAnchorView {
        AppFolderPopoverAnchorView()
    }

    func updateNSView(_ nsView: AppFolderPopoverAnchorView, context: Context) {
        context.coordinator.update(tile: tile, isPresented: $isPresented, preferredEdge: preferredEdge)

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
        private var isPresented: Binding<Bool>
        private var preferredEdge: NSRectEdge
        private weak var anchorView: NSView?
        private var isShowing = false
        private var isInterruptingAutohide = false

        init(tile: AppFolderTile, isPresented: Binding<Bool>, preferredEdge: NSRectEdge) {
            self.tile = tile
            self.isPresented = isPresented
            self.preferredEdge = preferredEdge
            super.init()
        }

        func update(tile: AppFolderTile, isPresented: Binding<Bool>, preferredEdge: NSRectEdge) {
            self.tile = tile
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

            for app in tile.apps {
                let item = NSMenuItem(title: app.displayName, action: #selector(openApp(_:)), keyEquivalent: "")
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
    @Binding var isPresented: Bool
    let preferredEdge: NSRectEdge

    func makeCoordinator() -> Coordinator {
        Coordinator(tile: tile, isPresented: $isPresented, preferredEdge: preferredEdge)
    }

    func makeNSView(context: Context) -> AppFolderPopoverAnchorView {
        AppFolderPopoverAnchorView()
    }

    func updateNSView(_ nsView: AppFolderPopoverAnchorView, context: Context) {
        context.coordinator.update(tile: tile, isPresented: $isPresented, preferredEdge: preferredEdge)

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
                isPresented: .constant(false)
            )
        )
        private var isPresented: Binding<Bool>
        private var preferredEdge: NSRectEdge
        private var lastContentSize = NSSize(width: 384, height: 240)
        private weak var anchorView: NSView?
        private var isInterruptingAutohide = false

        init(tile: AppFolderTile, isPresented: Binding<Bool>, preferredEdge: NSRectEdge) {
            self.isPresented = isPresented
            self.preferredEdge = preferredEdge
            super.init()
            popover.contentViewController = hostingController
            popover.animates = true
            popover.behavior = .transient
            popover.delegate = self
            update(tile: tile, isPresented: isPresented, preferredEdge: preferredEdge)
        }

        func update(tile: AppFolderTile, isPresented: Binding<Bool>, preferredEdge: NSRectEdge) {
            self.isPresented = isPresented
            self.preferredEdge = preferredEdge
            hostingController.rootView = AppFolderPopoverView(
                tile: tile,
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

final class AppFolderPopoverAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
