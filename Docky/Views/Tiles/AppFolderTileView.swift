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
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var layout = DockLayoutService.shared
    @Bindable private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared
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
        self._preferences = Bindable(wrappedValue: DockyPreferences.shared)
        self._product = ObservedObject(wrappedValue: ProductService.shared)
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

        guard product.isUnlocked(.groupedAppFolders), preferences.showsGroupedOpenedAppsInDock else {
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
        if shouldApplyCircleClip(to: bundleIdentifier) {
            baseGridIcon(forBundleIdentifier: bundleIdentifier, side: side)
                .dockyGlass(in: Circle())
                .clipShape(Circle())
        } else {
            baseGridIcon(forBundleIdentifier: bundleIdentifier, side: side)
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

struct AppFolderPopoverView: View {
    let tile: AppFolderTile
    @Binding var isPresented: Bool
    let onPopoverSizeChange: (CGSize) -> Void
    @Bindable private var preferences = DockyPreferences.shared
    @State private var hoveredBundleIdentifier: String?

    private let columns = 3
    private let itemWidth: CGFloat = 96
    private let itemHeight: CGFloat = 96
    private let itemSpacing: CGFloat = 12
    private let contentPadding: CGFloat = 20
    private let headerHeight: CGFloat = 42
    private let maxHeight: CGFloat = 620
    // At rest the ring is inset 8pt from the cell edge so it sits inside
    // the visible icon squircle. On hover the inset goes negative, pushing
    // the ring `hoverOverflow` past the cell on each side for a clear pop.
    // The radius matches Docky's widget tile shape (`tileSize * 0.225`).
    private let iconChromeInset: CGFloat = 8
    private let hoverOverflow: CGFloat = 4
    private var iconBorderRadius: CGFloat { itemWidth * 0.225 }

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
        #if DEBUG
        let _ = Self._printChanges()
        #endif

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
                        let isHovered = hoveredBundleIdentifier == app.bundleIdentifier
                        Button {
                            WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
                            isPresented = false
                        } label: {
                            Image(nsImage: icon(forBundleIdentifier: app.bundleIdentifier))
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: itemWidth, height: itemHeight)
                                .padding(overrideIconPadding(for: app.bundleIdentifier, side: itemWidth))
                                .background {
                                    // Border lives in an overlay whose inset
                                    // tracks hover state — at rest the ring
                                    // hugs the visible icon squircle, on hover
                                    // it pushes `hoverOverflow` past the cell
                                    // edge for a clear pop.
                                    RoundedRectangle(cornerRadius: iconBorderRadius, style: .continuous)
                                        .fill(Color.primary.opacity(0.35))
                                        .padding(isHovered ? -hoverOverflow : iconChromeInset)
                                }
                                .animation(.easeInOut(duration: 0.15), value: isHovered)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                hoveredBundleIdentifier = app.bundleIdentifier
                            } else if hoveredBundleIdentifier == app.bundleIdentifier {
                                hoveredBundleIdentifier = nil
                            }
                        }
                        .onDrop(
                            of: [UTType.fileURL.identifier],
                            isTargeted: dropTargetBinding(for: app),
                            perform: { providers in
                                openDroppedFiles(providers: providers, with: app)
                                return true
                            }
                        )
                        .background {
                            ContextActionMenuPresenter { modifierFlags in
                                appContextActions(for: app, modifierFlags: modifierFlags)
                            }
                        }
                    }
                }
                .padding(contentPadding)
            }
        }
        .frame(width: popoverSize.width, height: popoverSize.height)
        .onAppear {
            onPopoverSizeChange(popoverSize)
        }
        .onChange(of: tile.apps.count) { _ in
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
        return injectingAppWindowActions(windows, into: baseActions)
    }

    /// Reuses the hover state for drop-target highlighting so the ring pops
    /// out the same way it does on mouse hover when a drag is over the icon.
    private func dropTargetBinding(for app: AppTile) -> Binding<Bool> {
        Binding(
            get: { hoveredBundleIdentifier == app.bundleIdentifier },
            set: { newValue in
                if newValue {
                    hoveredBundleIdentifier = app.bundleIdentifier
                } else if hoveredBundleIdentifier == app.bundleIdentifier {
                    hoveredBundleIdentifier = nil
                }
            }
        )
    }

    private func openDroppedFiles(providers: [NSItemProvider], with app: AppTile) {
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
        private var globalClickMonitor: Any?
        private var localClickMonitor: Any?
        private var dragEndSubscription: AnyCancellable?

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
