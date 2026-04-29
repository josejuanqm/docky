//
//  TileContainerView.swift
//  Docky
//

import SwiftUI
import UniformTypeIdentifiers
import OSLog

struct TileContainerView: View {
    static let edgePadding: CGFloat = 8
    private let tileMutationAnimation: Animation = .easeInOut(duration: 0.18)
    private static let logger = Logger(subsystem: "gt.quintero.Docky", category: "TileDrag")

    @ObservedObject private var store = TileStore.shared
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var layout = DockLayoutService.shared
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var editMode = DockEditModeService.shared
    @ObservedObject private var product = ProductService.shared

    @State private var draggedTileID: String?
    @State private var draggedTileOffset: CGFloat = 0
    @State private var draggedTileInitialFrame: CGRect?
    @State private var draggedPinnedTileDestinationIndex: Int?
    @State private var draggedTrailingTileDestinationIndex: Int?
    @State private var draggedAppFolderTargetTileID: String?
    @State private var draggedAdditionalTileIDs: [String] = []
    @State private var draggedPickupCandidateTileID: String?
    @State private var externalAppDropDestinationIndex: Int?
    @State private var externalFolderDropDestinationIndex: Int?
    @State private var externalDocumentDropTargetTileID: String?
    @State private var lastExternalFileDropLocation: CGPoint?
    @State private var tileFrames: [String: CGRect] = [:]

    var body: some View {
        GeometryReader { proxy in
            overflowWrappedContent(in: proxy)
            .onPreferenceChange(TileFramePreferenceKey.self) { tileFrames = $0 }
            .onChange(of: editMode.paletteDrag) { _, paletteDrag in
                guard paletteDrag != nil else {
                    editMode.paletteDropDestination = nil
                    return
                }
            }
            .onDrop(of: [UTType.plainText, UTType.fileURL], delegate: PaletteInsertDropDelegate(
                updateLocation: { info in
                    let globalLocation = CGPoint(
                        x: proxy.frame(in: .global).minX + info.location.x,
                        y: proxy.frame(in: .global).minY + info.location.y
                    )
                    updatePalettePreviewDestination(info: info, at: globalLocation)
                },
                clearPreview: {
                    editMode.endPaletteDrag()
                    clearExternalFileDropState()
                },
                performInsert: { providers in
                    if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
                        let documentTargetBundleIdentifier = externalDocumentDropTargetTileID.flatMap(appDocumentDropBundleIdentifier(forTileID:))
                        let appDestinationIndex = externalAppDropDestinationIndex ?? inferredExternalAppDropDestinationIndex()
                        let folderDestinationIndex = externalFolderDropDestinationIndex

                        resolveDroppedURLs(from: providers) { itemURLs in
                            let droppedAppBundleIdentifiers = itemURLs.compactMap(bundleIdentifierForDroppedApp(from:))
                            let containsOnlyApps = !itemURLs.isEmpty && droppedAppBundleIdentifiers.count == itemURLs.count

                            DispatchQueue.main.async {
                                if containsOnlyApps {
                                    guard let destinationIndex = appDestinationIndex,
                                          !droppedAppBundleIdentifiers.isEmpty else {
                                        clearExternalFileDropState()
                                        return
                                    }

                                    var insertionIndex = destinationIndex
                                    for bundleIdentifier in droppedAppBundleIdentifiers {
                                        _ = TileStore.shared.pinApp(bundleIdentifier: bundleIdentifier, at: insertionIndex)
                                        insertionIndex += 1
                                    }
                                    clearExternalFileDropState()
                                    return
                                }

                                if let bundleIdentifier = documentTargetBundleIdentifier {
                                    let openableURLs = itemURLs.filter { !isDroppableApp($0) }
                                    guard !openableURLs.isEmpty else {
                                        clearExternalFileDropState()
                                        return
                                    }

                                    WorkspaceService.shared.open(fileURLs: openableURLs, withApplicationBundleIdentifier: bundleIdentifier)
                                    clearExternalFileDropState()
                                    return
                                }

                                guard let destinationIndex = folderDestinationIndex else {
                                    clearExternalFileDropState()
                                    return
                                }

                                let folderItems = itemURLs.compactMap(makeTrailingFolderItem(from:))
                                guard !folderItems.isEmpty else {
                                    clearExternalFileDropState()
                                    return
                                }

                                var insertionIndex = destinationIndex
                                for folderItem in folderItems {
                                    TileStore.shared.insertTrailingItem(folderItem, at: insertionIndex)
                                    insertionIndex += 1
                                }
                                clearExternalFileDropState()
                            }
                        }
                        return true
                    }

                    guard let paletteDrag = editMode.paletteDrag,
                          let destination = editMode.paletteDropDestination else {
                        editMode.endPaletteDrag()
                        return false
                    }

                    switch destination.section {
                    case .pinned:
                        guard let pinnedItem = makePinnedItem(from: paletteDrag) else {
                            editMode.endPaletteDrag()
                            return false
                        }
                        TileStore.shared.insertPinnedItem(pinnedItem, at: destination.index)
                    case .trailing:
                        guard let trailingItem = makeTrailingItem(from: paletteDrag) else {
                            editMode.endPaletteDrag()
                            return false
                        }
                        TileStore.shared.insertTrailingItem(trailingItem, at: destination.index)
                    }
                    editMode.endPaletteDrag()
                    return true
                }
            ))
            .animation(tileMutationAnimation, value: displayTiles)
        }
    }

    @ViewBuilder
    private func overflowWrappedContent(in proxy: GeometryProxy) -> some View {
        tileCanvas(in: proxy)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tileCanvas(in proxy: GeometryProxy) -> some View {
        let scrollableSectionLayout = scrollableSectionLayout(in: proxy)

        return ZStack(alignment: .topLeading) {
            contentStack(scrollableSectionLayout: scrollableSectionLayout)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: contentAlignment(in: proxy, scrollableSectionLayout: scrollableSectionLayout)
                )

            draggedTileOverlay
        }
        .background(TileDragKeyMonitor(keyDownHandler: handleDragKeyDown))
    }

    @ViewBuilder
    private func contentStack(scrollableSectionLayout: ScrollableSectionLayout?) -> some View {
        if position.isVertical {
            VStack(spacing: effectiveTileSpacing) {
                contentComponents(scrollableSectionLayout: scrollableSectionLayout)
            }
            .padding(.vertical, effectiveEdgePadding)
        } else {
            HStack(spacing: effectiveTileSpacing) {
                contentComponents(scrollableSectionLayout: scrollableSectionLayout)
            }
            .padding(.horizontal, effectiveEdgePadding)
        }
    }

    private func contentAlignment(in proxy: GeometryProxy, scrollableSectionLayout: ScrollableSectionLayout?) -> Alignment {
        shouldCenterContent(in: proxy, scrollableSectionLayout: scrollableSectionLayout) ? .center : .topLeading
    }

    private func shouldCenterContent(in proxy: GeometryProxy, scrollableSectionLayout: ScrollableSectionLayout?) -> Bool {
        guard scrollableSectionLayout == nil,
              layout.contentScale >= 0.999,
              !layout.compactsWidgetsForOverflow else {
            return false
        }

        return totalAxisLength(for: layoutComponents) <= projected(size: proxy.size) + 0.5
    }

    @ViewBuilder
    private func contentComponents(scrollableSectionLayout: ScrollableSectionLayout?) -> some View {
        ForEach(layoutComponents) { component in
            componentView(component, scrollableSectionLayout: scrollableSectionLayout)
        }
    }

    @ViewBuilder
    private func componentView(_ component: TileLayoutComponent, scrollableSectionLayout: ScrollableSectionLayout?) -> some View {
        switch component {
        case .divider(let tile):
            tileView(for: tile)
        case .section(let section):
            if let scrollableSectionLayout, scrollableSectionLayout.id == section.id {
                scrollableSectionView(section, axisLength: scrollableSectionLayout.axisLength)
            } else {
                sectionTilesView(section.tiles)
            }
        }
    }

    @ViewBuilder
    private func scrollableSectionView(_ section: TileLayoutSection, axisLength: CGFloat) -> some View {
        let leadingScrollInset = scrollContentLeadingInset(for: section)
        let trailingScrollInset = scrollContentTrailingInset(for: section)

        ScrollViewReader { scrollProxy in
            ScrollView(scrollAxes, showsIndicators: false) {
                if position.isVertical {
                    sectionTilesView(section.tiles)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.top, leadingScrollInset)
                        .padding(.bottom, trailingScrollInset)
                } else {
                    sectionTilesView(section.tiles)
                        .padding(.leading, leadingScrollInset)
                        .padding(.trailing, trailingScrollInset)
                }
            }
            .padding(position.isVertical ? .bottom : .trailing, -trailingScrollInset)
            .padding(position.isVertical ? .top : .leading, -leadingScrollInset)
            .frame(
                width: position.isVertical ? nil : axisLength,
                height: position.isVertical ? axisLength : nil
            )
            .onAppear {
                scrollSectionToEnd(section, using: scrollProxy)
            }
            .onChange(of: section.tiles.map(\.id)) { _, _ in
                scrollSectionToEnd(section, using: scrollProxy)
            }
        }
    }

    @ViewBuilder
    private func sectionTilesView(_ tiles: [Tile]) -> some View {
        if position.isVertical {
            VStack(spacing: effectiveTileSpacing) {
                ForEach(tiles) { tile in
                    tileView(for: tile)
                }
            }
        } else {
            HStack(spacing: effectiveTileSpacing) {
                ForEach(tiles) { tile in
                    tileView(for: tile)
                }
            }
        }
    }

    @ViewBuilder
    private func tileView(for tile: Tile) -> some View {
        let size = Self.size(
            for: tile,
            tileSize: effectiveTileSize,
            tileHeight: tileHeight,
            tileSpacing: effectiveTileSpacing,
            position: position,
            compactWidgets: layout.compactsWidgetsForOverflow
        )
        TileView(tile: tile, isExternalFileDropTargeted: externalDocumentDropTargetTileID == tile.id)
            .frame(width: size.width, height: size.height)
            .opacity(isHiddenForActiveDrag(tileID: tile.id) ? 0 : 1)
            .background(alignment: .topLeading) {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TileFramePreferenceKey.self,
                        value: [tile.id: proxy.frame(in: .global)]
                    )
                }
            }
            .gesture(reorderGesture(for: tile), including: isTileDraggable(tile) ? .gesture : .subviews)
            .transition(tileTransition)
    }

    @ViewBuilder
    private var draggedTileOverlay: some View {
        if let draggedTile {
            let size = Self.size(
                for: draggedTile,
                tileSize: effectiveTileSize,
                tileHeight: tileHeight,
                tileSpacing: effectiveTileSpacing,
                position: position,
                compactWidgets: layout.compactsWidgetsForOverflow
            )
            ZStack {
                draggedSelectionStackPreview(size: size)

                TileView(tile: draggedTile, isDragging: true)
                    .frame(width: size.width, height: size.height)
            }
                .position(draggedTilePosition)
                .offset(axisSize(value: draggedTileOffset))
                .zIndex(10)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func draggedSelectionStackPreview(size: CGSize) -> some View {
        let additionalBundleIdentifiers = draggedPreviewAdditionalBundleIdentifiers
        if !additionalBundleIdentifiers.isEmpty {
            ForEach(Array(additionalBundleIdentifiers.enumerated()), id: \.element) { index, bundleIdentifier in
                let depth = additionalBundleIdentifiers.count - index
                AppTileView(
                    tile: AppTile(bundleIdentifier: bundleIdentifier, displayName: ""),
                    clipShape: preferences.tileClipShape,
                    transparencyCompensationInset: dragPreviewStackTileChromeInset
                )
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(dragPreviewStackRotationDegrees(for: depth)))
                .offset(
                    x: dragPreviewStackOffset(for: depth),
                    y: dragPreviewStackOffset(for: depth + 1)
                )
            }
        }
    }

    private var displayTiles: [Tile] {
        guard let finderTile = store.tiles.first else {
            return store.tiles
        }

        var result: [Tile] = [finderTile]
        result.append(contentsOf: previewPinnedTiles)
        var appendedTrailingSection = false

        for tile in store.tiles.dropFirst() {
            if appendedTrailingSection {
                continue
            }

            if groupedOpenedAppFolderID(for: tile.id) != nil {
                continue
            }

            if tile.id == "divider:trailing" {
                result.append(tile)
                result.append(contentsOf: previewTrailingSectionTiles)
                appendedTrailingSection = true
                continue
            }

            if isPinnedReorderable(tileID: tile.id)
                || isTrailingReorderable(tileID: tile.id) {
                continue
            }
            result.append(tile)
        }

        return result
    }

    private var pinnedTiles: [Tile] {
        store.tiles.filter { isPinnedReorderable(tileID: $0.id) }
    }

    private var pinnedTileIDs: [String] {
        pinnedTiles.map(\.id)
    }

    private var groupedOpenedAppTilesByFolderID: [String: [Tile]] {
        let groupedEntries: [(folderID: String, tile: Tile)] = store.tiles.compactMap { tile in
            guard case .app = tile.content,
                  let folderID = groupedOpenedAppFolderID(for: tile.id) else {
                return nil
            }
            return (folderID: folderID, tile: tile)
        }

        return Dictionary(grouping: groupedEntries, by: { $0.folderID }).mapValues { entries in
            entries.map { $0.tile }
        }
    }

    private var trailingTiles: [Tile] {
        store.tiles.filter { isTrailingReorderable(tileID: $0.id) }
    }

    private var trailingTileIDs: [String] {
        trailingTiles.map(\.id)
    }

    private var previewPinnedTiles: [Tile] {
        expandedPinnedTiles(from: previewPinnedBaseTiles)
    }

    private var draggedAppFolderIdentifier: String? {
        guard let draggedTile,
              case .appFolder(let folder) = draggedTile.content else {
            return nil
        }

        return folder.identifier
    }

    private var previewPinnedBaseTiles: [Tile] {
        var remainingPinnedTiles = pinnedTiles
        if !draggedAdditionalTileIDs.isEmpty {
            let hiddenTileIDs = Set(draggedAdditionalTileIDs)
            remainingPinnedTiles.removeAll { hiddenTileIDs.contains($0.id) }
        }

        guard let destinationIndex = activePinnedDropDestinationIndex else {
            return remainingPinnedTiles
        }

        if let draggedTileID {
            remainingPinnedTiles.removeAll { $0.id == draggedTileID }
        }
        let clampedDestinationIndex = min(max(destinationIndex, 0), remainingPinnedTiles.count)
        if let draggedTile, (isDraggingPinnedTile || store.makePinnedItem(from: draggedTile) != nil) {
            remainingPinnedTiles.insert(draggedTile, at: clampedDestinationIndex)
        } else if let palettePreviewTile {
            remainingPinnedTiles.insert(palettePreviewTile, at: clampedDestinationIndex)
        }
        return remainingPinnedTiles
    }

    private func expandedPinnedTiles(from baseTiles: [Tile]) -> [Tile] {
        var result: [Tile] = []

        for tile in baseTiles {
            result.append(tile)

            guard case .appFolder(let folder) = tile.content else {
                continue
            }

            guard folder.identifier != draggedAppFolderIdentifier else {
                continue
            }

            result.append(contentsOf: (groupedOpenedAppTilesByFolderID[folder.identifier] ?? []).filter {
                !isHiddenForActiveDrag(tileID: $0.id)
            })
        }

        return result
    }

    private var palettePreviewTile: Tile? {
        guard let paletteDrag = editMode.paletteDrag else {
            return nil
        }

        if let feature = paletteDrag.item.productFeature,
           !product.availability(for: feature, context: .newPlacement).allowsNewPlacement {
            return nil
        }

        switch paletteDrag.item {
        case .launchpad:
            return Tile(
                id: "editor-preview:launchpad",
                content: .launchpad(LaunchpadTile(identifier: "editor-preview:launchpad"))
            )
        case .spacer:
            return Tile(id: "editor-preview:spacer", content: .spacer)
        case .divider:
            return Tile(id: "editor-preview:divider", content: .divider)
        case .widget(let ownerBundleIdentifier, let kind):
            let span = resolvedPaletteWidgetSpan(
                ownerBundleIdentifier: ownerBundleIdentifier,
                kind: kind,
                requestedSpan: paletteDrag.widgetSpan
            )
            return Tile(
                id: "editor-preview:widget",
                content: .widget(WidgetTile(
                    identifier: "editor-preview:widget",
                    title: kind.title,
                    kind: kind,
                    ownerBundleIdentifier: ownerBundleIdentifier,
                    span: span
                ))
            )
        case .smartStack:
            return Tile(
                id: "editor-preview:smart-stack",
                content: .smartStack(SmartStackTile(
                    identifier: "editor-preview:smart-stack",
                    title: "Smart Stack",
                    widgets: WidgetCatalog.smartStackRegistrations.map { $0.makeTile() },
                    span: .three
                ))
            )
        }
    }

    private var previewTrailingTiles: [Tile] {
        var remainingTrailingTiles = trailingTiles
        if !draggedAdditionalTileIDs.isEmpty {
            let hiddenTileIDs = Set(draggedAdditionalTileIDs)
            remainingTrailingTiles.removeAll { hiddenTileIDs.contains($0.id) }
        }

        guard let destinationIndex = activeTrailingDropDestinationIndex else {
            return remainingTrailingTiles
        }

        if let draggedTileID {
            remainingTrailingTiles.removeAll { $0.id == draggedTileID }
        }
        let clampedDestinationIndex = min(max(destinationIndex, 0), remainingTrailingTiles.count)
        if let draggedTile, store.makeTrailingItem(from: draggedTile) != nil {
            remainingTrailingTiles.insert(draggedTile, at: clampedDestinationIndex)
        } else if let palettePreviewTile, makeTrailingItem(from: editMode.paletteDrag) != nil {
            remainingTrailingTiles.insert(palettePreviewTile, at: clampedDestinationIndex)
        }
        return remainingTrailingTiles
    }

    private var previewTrailingSectionTiles: [Tile] {
        let minimizedWindowTiles = store.tiles.compactMap { tile in
            if case .minimizedWindow = tile.content {
                return tile
            }
            return nil
        }

        guard !minimizedWindowTiles.isEmpty else {
            return previewTrailingTiles
        }

        var result: [Tile] = []
        var insertedMinimizedWindows = false

        for tile in previewTrailingTiles {
            if !insertedMinimizedWindows, case .trash = tile.content {
                result.append(contentsOf: minimizedWindowTiles)
                insertedMinimizedWindows = true
            }
            result.append(tile)
        }

        if !insertedMinimizedWindows {
            result.append(contentsOf: minimizedWindowTiles)
        }

        return result
    }

    private var draggedTile: Tile? {
        guard let draggedTileID else {
            return nil
        }

        return store.tiles.first { $0.id == draggedTileID }
    }

    private var orderedDraggedSelectionTileIDs: [String] {
        var result: [String] = []
        if let draggedTileID {
            result.append(draggedTileID)
        }

        for tileID in draggedAdditionalTileIDs where !result.contains(tileID) {
            result.append(tileID)
        }

        return result
    }

    private var draggedSelectionTileIDs: Set<String> {
        Set(orderedDraggedSelectionTileIDs)
    }

    private var draggedSelectionBundleIdentifiers: [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for tileID in orderedDraggedSelectionTileIDs {
            guard let bundleIdentifier = bundleIdentifier(forTileID: tileID),
                  seen.insert(bundleIdentifier).inserted else {
                continue
            }
            result.append(bundleIdentifier)
        }

        return result
    }

    private var draggedPreviewAdditionalBundleIdentifiers: [String] {
        Array(draggedSelectionBundleIdentifiers.dropFirst().suffix(3))
    }

    private var isCollectingAdditionalAppsDuringDrag: Bool {
        draggedBundleIdentifier != nil
    }

    private var hasCollectedAdditionalAppsDuringDrag: Bool {
        !draggedAdditionalTileIDs.isEmpty
    }

    private var draggedTilePosition: CGPoint {
        guard let frame = draggedTileInitialFrame else {
            return .zero
        }

        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private var activePinnedDropDestinationIndex: Int? {
        if draggedTileID == nil {
            if let externalAppDropDestinationIndex {
                return externalAppDropDestinationIndex
            }
            guard editMode.paletteDropDestination?.section == .pinned else {
                return nil
            }
            return editMode.paletteDropDestination?.index
        }
        return draggedPinnedTileDestinationIndex
    }

    private var activeTrailingDropDestinationIndex: Int? {
        if draggedTileID == nil {
            if let externalFolderDropDestinationIndex {
                return externalFolderDropDestinationIndex
            }
            guard editMode.paletteDropDestination?.section == .trailing else {
                return nil
            }
            return editMode.paletteDropDestination?.index
        }
        return draggedTrailingTileDestinationIndex
    }

    private var tileTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.9, anchor: tileScaleAnchor).combined(with: .opacity),
            removal: .scale(scale: 0.9, anchor: tileScaleAnchor).combined(with: .opacity)
        )
    }

    private var tileScaleAnchor: UnitPoint {
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

    private var scrollAxes: Axis.Set {
        position.isVertical ? .vertical : .horizontal
    }

    private var layoutComponents: [TileLayoutComponent] {
        var components: [TileLayoutComponent] = []
        var currentSectionID = "primary"
        var currentTiles: [Tile] = []

        func appendCurrentSection() {
            guard !currentTiles.isEmpty else { return }
            components.append(.section(TileLayoutSection(id: currentSectionID, tiles: currentTiles)))
            currentTiles = []
        }

        for tile in displayTiles {
            if tile.id == "divider:running" || tile.id == "divider:trailing" {
                appendCurrentSection()
                components.append(.divider(tile))
                currentSectionID = tile.id == "divider:running" ? "running" : "trailing"
                continue
            }

            currentTiles.append(tile)
        }

        appendCurrentSection()
        return components
    }

    private var layoutSections: [TileLayoutSection] {
        layoutComponents.compactMap { component in
            if case .section(let section) = component {
                return section
            }
            return nil
        }
    }

    private func scrollableSectionLayout(in proxy: GeometryProxy) -> ScrollableSectionLayout? {
        guard preferences.overflowBehavior == .scroll else {
            return nil
        }

        let components = layoutComponents
        let availableAxisLength = projected(size: proxy.size)
        guard totalAxisLength(for: components) > availableAxisLength else {
            return nil
        }

        let sections = components.compactMap { component -> TileLayoutSection? in
            if case .section(let section) = component {
                return section
            }
            return nil
        }
        guard let largestSection = sections.max(by: { axisLength(of: $0.tiles) < axisLength(of: $1.tiles) }) else {
            return nil
        }

        let viewportAxisLength = scrollableSectionAxisLength(
            for: largestSection.id,
            in: components,
            availableAxisLength: availableAxisLength
        )
        guard viewportAxisLength > 0 else {
            return nil
        }

        return ScrollableSectionLayout(id: largestSection.id, axisLength: viewportAxisLength)
    }

    private func totalAxisLength(for components: [TileLayoutComponent]) -> CGFloat {
        let componentLengths = components.reduce(CGFloat(0)) { partialResult, component in
            partialResult + axisLength(of: component)
        }
        let spacings = CGFloat(max(0, components.count - 1)) * effectiveTileSpacing
        return componentLengths + spacings + effectiveEdgePadding * 2
    }

    private func scrollableSectionAxisLength(
        for sectionID: String,
        in components: [TileLayoutComponent],
        availableAxisLength: CGFloat
    ) -> CGFloat {
        let innerAvailableAxisLength = max(0, availableAxisLength - effectiveEdgePadding * 2)
        let spacings = CGFloat(max(0, components.count - 1)) * effectiveTileSpacing
        let fixedAxisLength = components.reduce(CGFloat(0)) { partialResult, component in
            switch component {
            case .section(let section) where section.id == sectionID:
                partialResult
            default:
                partialResult + axisLength(of: component)
            }
        }
        return max(0, innerAvailableAxisLength - fixedAxisLength - spacings)
    }

    private func axisLength(of component: TileLayoutComponent) -> CGFloat {
        switch component {
        case .divider(let tile):
            let size = Self.size(
                for: tile,
                tileSize: effectiveTileSize,
                tileHeight: tileHeight,
                tileSpacing: effectiveTileSpacing,
                position: position,
                compactWidgets: layout.compactsWidgetsForOverflow
            )
            return projected(size: size)
        case .section(let section):
            return axisLength(of: section.tiles)
        }
    }

    private func axisLength(of tiles: [Tile]) -> CGFloat {
        let size = Self.contentSize(
            tiles: tiles,
            tileSize: effectiveTileSize,
            tileHeight: tileHeight,
            tileSpacing: effectiveTileSpacing,
            position: position,
            compactWidgets: layout.compactsWidgetsForOverflow,
            edgePadding: 0
        )
        return projected(size: size)
    }

    private func scrollSectionToEnd(_ section: TileLayoutSection, using scrollProxy: ScrollViewProxy) {
        guard draggedTileID == nil,
              editMode.paletteDrag == nil,
              let lastTileID = section.tiles.last?.id else {
            return
        }

        DispatchQueue.main.async {
            scrollProxy.scrollTo(lastTileID, anchor: sectionScrollAnchor)
        }
    }

    private var sectionScrollAnchor: UnitPoint {
        position.isVertical ? .bottom : .trailing
    }

    private func scrollContentLeadingInset(for section: TileLayoutSection) -> CGFloat {
        guard layoutSections.first?.id == section.id else {
            return 0
        }

        return effectiveEdgePadding
    }

    private func scrollContentTrailingInset(for section: TileLayoutSection) -> CGFloat {
        if layoutSections.last?.id == section.id {
            return effectiveEdgePadding
        }

        if preferences.showsActivePinnedSeparator, section.id == "primary" {
            return effectiveTileSize * 0.25
        }

        return 0
    }

    private var effectiveEdgePadding: CGFloat {
        layout.scaled(Self.edgePadding)
    }

    private var effectiveTileSize: CGFloat {
        layout.scaled(dockSettings.tileSize)
    }

    private var effectiveTileSpacing: CGFloat {
        layout.scaled(preferences.tileSpacing)
    }

    private var dragPreviewStackTileChromeInset: CGFloat {
        floor(effectiveTileSize * 3 / 32)
    }

    private func dragPreviewStackRotationDegrees(for depth: Int) -> Double {
        let magnitude = Double(depth) * 12.5
        return depth.isMultiple(of: 2) ? magnitude : -magnitude
    }
    
    private func dragPreviewStackOffset(for depth: Int) -> Double {
        let magnitude = Double(depth) * 2.5
        return depth.isMultiple(of: 2) ? magnitude : -magnitude
    }

    private var tileHeight: CGFloat {
        let iconHeight = layout.scaled(dockSettings.magnification ? dockSettings.largeSize : dockSettings.tileSize)
        return iconHeight + layout.scaled(preferences.tileVerticalPadding) * 2
    }

    private var position: ResolvedDockWindowPosition {
        preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
    }

    private func isPinnedReorderable(tileID: String) -> Bool {
        store.isPinnedReorderable(tileID: tileID)
    }

    private func isTrailingReorderable(tileID: String) -> Bool {
        store.isTrailingReorderable(tileID: tileID)
    }

    private func isTileDraggable(_ tile: Tile) -> Bool {
        switch tile.content {
        case .app(let app):
            return !app.bundleIdentifier.isEmpty && app.bundleIdentifier != "com.apple.finder"
        case .minimizedWindow:
            return false
        case .appFolder:
            return isPinnedReorderable(tileID: tile.id)
        case .launchpad, .widget, .smartStack, .spacer, .divider:
            return editMode.isActive && (isPinnedReorderable(tileID: tile.id) || isTrailingReorderable(tileID: tile.id))
        case .folder, .trash:
            return editMode.isActive && isTrailingReorderable(tileID: tile.id)
        }
    }

    private func makePinnedItem(from paletteDrag: DockEditPaletteDrag) -> PinnedTileItem? {
        makePinnedItem(from: paletteDrag.item, widgetSpan: paletteDrag.widgetSpan)
    }

    private func makePinnedItem(from paletteDrag: DockEditPaletteDrag?) -> PinnedTileItem? {
        guard let paletteDrag else {
            return nil
        }

        return makePinnedItem(from: paletteDrag)
    }

    private func makePinnedItem(from paletteItem: DockEditPaletteItem, widgetSpan: TileSpan?) -> PinnedTileItem? {
        if let feature = paletteItem.productFeature,
           !product.availability(for: feature, context: .newPlacement).allowsNewPlacement {
            return nil
        }

        return switch paletteItem {
        case .launchpad:
            PinnedTileItem.launchpad()
        case .spacer:
            PinnedTileItem.spacer()
        case .divider:
            PinnedTileItem.divider()
        case .widget(let ownerBundleIdentifier, let kind):
            PinnedTileItem.widget(
                kind: kind,
                ownerBundleIdentifier: ownerBundleIdentifier,
                span: resolvedPaletteWidgetSpan(
                    ownerBundleIdentifier: ownerBundleIdentifier,
                    kind: kind,
                    requestedSpan: widgetSpan
                )
            )
        case .smartStack:
            PinnedTileItem.smartStack()
        }
    }

    private func makeTrailingItem(from paletteDrag: DockEditPaletteDrag?) -> TrailingTileItem? {
        guard let paletteDrag else {
            return nil
        }

        if let feature = paletteDrag.item.productFeature,
           !product.availability(for: feature, context: .newPlacement).allowsNewPlacement {
            return nil
        }

        return switch paletteDrag.item {
        case .launchpad:
            nil
        case .spacer:
            TrailingTileItem.spacer()
        case .divider:
            TrailingTileItem.divider()
        case .widget(let ownerBundleIdentifier, let kind):
            TrailingTileItem.widget(
                kind: kind,
                ownerBundleIdentifier: ownerBundleIdentifier,
                span: resolvedPaletteWidgetSpan(
                    ownerBundleIdentifier: ownerBundleIdentifier,
                    kind: kind,
                    requestedSpan: paletteDrag.widgetSpan
                )
            )
        case .smartStack:
            TrailingTileItem.smartStack()
        }
    }

    private func resolvedPaletteWidgetSpan(
        ownerBundleIdentifier: String,
        kind: WidgetKind,
        requestedSpan: TileSpan?
    ) -> TileSpan {
        let supportedSpans = kind.supportedSpans
        if let requestedSpan, supportedSpans.contains(requestedSpan) {
            return requestedSpan
        }

        if let catalogSpan = WidgetCatalog.staticRegistrations.first(where: {
            $0.ownerBundleIdentifier == ownerBundleIdentifier && $0.kind == kind
        })?.defaultSpan,
           supportedSpans.contains(catalogSpan) {
            return catalogSpan
        }

        return supportedSpans.last ?? .one
    }

    private var isDraggingPinnedTile: Bool {
        guard let draggedTileID else {
            return false
        }
        return isPinnedReorderable(tileID: draggedTileID)
    }

    private var isDraggingTrailingTile: Bool {
        guard let draggedTileID else {
            return false
        }
        return isTrailingReorderable(tileID: draggedTileID)
    }

    private func isHiddenForActiveDrag(tileID: String) -> Bool {
        if draggedAdditionalTileIDs.contains(tileID) {
            return true
        }

        guard tileID == draggedTileID else {
            return false
        }

        return (!isDraggingPinnedTile && draggedPinnedTileDestinationIndex != nil)
            || (!isDraggingTrailingTile && draggedTrailingTileDestinationIndex != nil)
            || draggedTileID == tileID
    }

    private func shouldHideDraggedOriginalTile(tileID: String) -> Bool {
        isHiddenForActiveDrag(tileID: tileID)
    }

    private func canDropInPinnedSection(_ tile: Tile) -> Bool {
        isPinnedReorderable(tileID: tile.id) || store.makePinnedItem(from: tile) != nil || bundleIdentifier(for: tile) != nil
    }

    private func canDropInTrailingSection(_ tile: Tile) -> Bool {
        isTrailingReorderable(tileID: tile.id) || store.makeTrailingItem(from: tile) != nil
    }

    private func reorderGesture(for tile: Tile) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                updateDrag(for: tile, value: value)
            }
            .onEnded { value in
                endDrag(for: tile, value: value)
            }
    }

    private func updateDrag(for tile: Tile, value: DragGesture.Value) {
        guard isTileDraggable(tile) else {
            return
        }

        if draggedTileID == nil {
            draggedTileID = tile.id
            draggedAdditionalTileIDs = []
            draggedTileInitialFrame = tileFrames[tile.id]
            draggedPinnedTileDestinationIndex = isPinnedReorderable(tileID: tile.id) ? pinnedTileIDs.firstIndex(of: tile.id) : nil
            draggedTrailingTileDestinationIndex = isTrailingReorderable(tileID: tile.id) ? trailingTileIDs.firstIndex(of: tile.id) : nil
            Self.logger.info(
                "Drag started tile=\(tileLogDescription(tile), privacy: .public) pinnedSource=\(isPinnedReorderable(tileID: tile.id), privacy: .public) trailingSource=\(isTrailingReorderable(tileID: tile.id), privacy: .public) startPinnedIndex=\(optionalIndexDescription(draggedPinnedTileDestinationIndex), privacy: .public) startTrailingIndex=\(optionalIndexDescription(draggedTrailingTileDestinationIndex), privacy: .public)"
            )
        }

        guard draggedTileID == tile.id else {
            return
        }

        draggedTileOffset = projected(size: value.translation)
        draggedPickupCandidateTileID = dragPickupCandidateTileID(at: value.location)

        if draggedBundleIdentifier != nil,
           let groupTargetTileID = appFolderDropTargetTileID(
                at: value.location,
                selectedTileIDs: draggedSelectionTileIDs,
                selectedBundleIdentifiers: draggedSelectionBundleIdentifiers
             ) {
            if draggedAppFolderTargetTileID != groupTargetTileID {
                Self.logger.debug(
                    "Drag folder target tile=\(tileLogDescription(tile), privacy: .public) targetTileID=\(groupTargetTileID, privacy: .public) selectionCount=\(draggedSelectionBundleIdentifiers.count, privacy: .public)"
                )
            }
            draggedAppFolderTargetTileID = groupTargetTileID
            draggedPinnedTileDestinationIndex = nil
            draggedTrailingTileDestinationIndex = nil
            editMode.paletteDropDestination = nil
            return
        }

        if hasCollectedAdditionalAppsDuringDrag {
            clearDragPreviewDestinations()
            return
        }

        draggedAppFolderTargetTileID = nil
        updatePreviewDestination(
            at: projected(point: value.location),
            sourceTileID: tile.id,
            isTileDrag: true,
            isPinnedSource: isPinnedReorderable(tileID: tile.id),
            isTrailingSource: isTrailingReorderable(tileID: tile.id),
            canDropIntoPinned: canDropInPinnedSection(tile),
            canDropIntoTrailing: canDropInTrailingSection(tile)
        )
    }

    private func endDrag(for tile: Tile, value: DragGesture.Value) {
        updateDrag(for: tile, value: value)

        guard draggedTileID == tile.id else {
            Self.logger.info(
                "Drag ended without active source tile=\(tileLogDescription(tile), privacy: .public)"
            )
            clearDragState()
            return
        }

        if let groupTargetTileID = draggedAppFolderTargetTileID,
           draggedBundleIdentifier != nil {
            Self.logger.info(
                "Drag committing group tile=\(tileLogDescription(tile), privacy: .public) targetTileID=\(groupTargetTileID, privacy: .public) selectionCount=\(draggedSelectionBundleIdentifiers.count, privacy: .public)"
            )
            _ = store.groupApps(bundleIdentifiers: draggedSelectionBundleIdentifiers, intoTileID: groupTargetTileID)
        } else if hasCollectedAdditionalAppsDuringDrag {
            // Multi-app pickup is only used for grouping into an app or folder target.
            Self.logger.info(
                "Drag ended with collected apps tile=\(tileLogDescription(tile), privacy: .public) additionalTileIDs=\(self.draggedAdditionalTileIDs.joined(separator: ","), privacy: .public)"
            )
        } else if isPinnedReorderable(tileID: tile.id) {
            if let destinationIndex = draggedTrailingTileDestinationIndex,
               let trailingItem = draggedTile.flatMap(store.makeTrailingItem(from:)) {
                Self.logger.info(
                    "Drag moving pinned->trailing tile=\(tileLogDescription(tile), privacy: .public) destinationIndex=\(destinationIndex, privacy: .public)"
                )
                store.removePinnedItem(tileID: tile.id)
                store.insertTrailingItem(trailingItem, at: destinationIndex)
            } else {
                let finalPinnedTileIDs = previewPinnedBaseTiles.map(\.id)
                Self.logger.info(
                    "Drag reordering pinned tile=\(tileLogDescription(tile), privacy: .public) finalPinnedIDs=\(finalPinnedTileIDs.joined(separator: ","), privacy: .public)"
                )
                if finalPinnedTileIDs != pinnedTileIDs {
                    store.setPinnedTileOrder(ids: finalPinnedTileIDs)
                }
            }
        } else if isTrailingReorderable(tileID: tile.id) {
            if let destinationIndex = draggedPinnedTileDestinationIndex,
               let pinnedItem = draggedTile.flatMap(store.makePinnedItem(from:)) {
                Self.logger.info(
                    "Drag moving trailing->pinned tile=\(tileLogDescription(tile), privacy: .public) destinationIndex=\(destinationIndex, privacy: .public)"
                )
                store.removeTrailingItem(tileID: tile.id)
                store.insertPinnedItem(pinnedItem, at: destinationIndex)
            } else {
                let finalTrailingTileIDs = previewTrailingTiles.map(\.id)
                Self.logger.info(
                    "Drag reordering trailing tile=\(tileLogDescription(tile), privacy: .public) finalTrailingIDs=\(finalTrailingTileIDs.joined(separator: ","), privacy: .public)"
                )
                if finalTrailingTileIDs != trailingTileIDs {
                    store.setTrailingTileOrder(ids: finalTrailingTileIDs)
                }
            }
        } else if let destinationIndex = draggedPinnedTileDestinationIndex,
                  let bundleIdentifier = draggedBundleIdentifier {
            Self.logger.info(
                "Drag pinning app tile=\(tileLogDescription(tile), privacy: .public) bundleIdentifier=\(bundleIdentifier, privacy: .public) destinationIndex=\(destinationIndex, privacy: .public)"
            )
            _ = store.pinApp(bundleIdentifier: bundleIdentifier, at: destinationIndex)
        } else {
            Self.logger.info(
                "Drag ended with no mutation tile=\(tileLogDescription(tile), privacy: .public) pinnedDestination=\(optionalIndexDescription(draggedPinnedTileDestinationIndex), privacy: .public) trailingDestination=\(optionalIndexDescription(draggedTrailingTileDestinationIndex), privacy: .public) folderTarget=\(draggedAppFolderTargetTileID ?? "nil", privacy: .public)"
            )
        }

        withAnimation(tileMutationAnimation) {
            clearDragState()
        }
    }

    private var draggedBundleIdentifier: String? {
        guard let draggedTile, case .app(let app) = draggedTile.content else {
            return nil
        }
        return app.bundleIdentifier
    }

    private func handleDragKeyDown(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
              event.charactersIgnoringModifiers == " " else {
            return false
        }

        return grabPickupCandidateDuringActiveDrag()
    }

    private func grabPickupCandidateDuringActiveDrag() -> Bool {
        guard isCollectingAdditionalAppsDuringDrag,
              let pickupCandidateTileID = draggedPickupCandidateTileID,
              let bundleIdentifier = bundleIdentifier(forTileID: pickupCandidateTileID),
              !draggedSelectionTileIDs.contains(pickupCandidateTileID),
              !draggedSelectionBundleIdentifiers.contains(bundleIdentifier) else {
            return false
        }

        withAnimation(tileMutationAnimation) {
            draggedAdditionalTileIDs.append(pickupCandidateTileID)
            draggedPickupCandidateTileID = nil
            clearDragPreviewDestinations()
        }
        return true
    }

    private func clearDragPreviewDestinations() {
        draggedAppFolderTargetTileID = nil
        draggedPinnedTileDestinationIndex = nil
        draggedTrailingTileDestinationIndex = nil
        editMode.paletteDropDestination = nil
    }

    private func updatePreviewDestination(
        at positionValue: CGFloat,
        sourceTileID: String,
        isTileDrag: Bool,
        isPinnedSource: Bool,
        isTrailingSource: Bool,
        canDropIntoPinned: Bool,
        canDropIntoTrailing: Bool
    ) {
        if canDropIntoPinned && isPointInPinnedDropRegion(positionValue) {
            if draggedPinnedTileDestinationIndex == nil || draggedTrailingTileDestinationIndex != nil {
                Self.logger.debug(
                    "Drag entered pinned region sourceTileID=\(sourceTileID, privacy: .public) position=\(positionValue, privacy: .public) pinnedSource=\(isPinnedSource, privacy: .public) trailingSource=\(isTrailingSource, privacy: .public) canDropPinned=\(canDropIntoPinned, privacy: .public) canDropTrailing=\(canDropIntoTrailing, privacy: .public)"
                )
            }
            updateDropDestination(for: .pinned, at: positionValue, sourceTileID: sourceTileID, isTileDrag: isTileDrag)
            if isTileDrag {
                if draggedTrailingTileDestinationIndex != nil {
                    Self.logger.debug(
                        "Drag clearing trailing preview sourceTileID=\(sourceTileID, privacy: .public) because pointer entered pinned region"
                    )
                }
                draggedTrailingTileDestinationIndex = nil
            }
            return
        }

        if canDropIntoTrailing && isPointInTrailingDropRegion(positionValue) {
            if draggedTrailingTileDestinationIndex == nil || draggedPinnedTileDestinationIndex != nil {
                Self.logger.debug(
                    "Drag entered trailing region sourceTileID=\(sourceTileID, privacy: .public) position=\(positionValue, privacy: .public) pinnedSource=\(isPinnedSource, privacy: .public) trailingSource=\(isTrailingSource, privacy: .public) canDropPinned=\(canDropIntoPinned, privacy: .public) canDropTrailing=\(canDropIntoTrailing, privacy: .public)"
                )
            }
            updateDropDestination(for: .trailing, at: positionValue, sourceTileID: sourceTileID, isTileDrag: isTileDrag)
            if isTileDrag {
                if draggedPinnedTileDestinationIndex != nil {
                    Self.logger.debug(
                        "Drag clearing pinned preview sourceTileID=\(sourceTileID, privacy: .public) because pointer entered trailing region"
                    )
                }
                draggedPinnedTileDestinationIndex = nil
            }
            return
        }

        if draggedPinnedTileDestinationIndex != nil || draggedTrailingTileDestinationIndex != nil {
            Self.logger.debug(
                "Drag left drop regions sourceTileID=\(sourceTileID, privacy: .public) position=\(positionValue, privacy: .public) pinnedSource=\(isPinnedSource, privacy: .public) trailingSource=\(isTrailingSource, privacy: .public)"
            )
        }
        if isTileDrag {
            draggedPinnedTileDestinationIndex = nil
        }
        if isTileDrag {
            draggedTrailingTileDestinationIndex = nil
        }
        if !isTileDrag {
            editMode.paletteDropDestination = nil
        }
    }

    private func updateDropDestination(
        for section: DockEditDropSection,
        at positionValue: CGFloat,
        sourceTileID: String,
        isTileDrag: Bool
    ) {
        let visibleTiles = previewTiles(for: section).filter { $0.id != sourceTileID }
        let destinationIndex = visibleTiles.enumerated().first { _, tile in
            guard let frame = tileFrames[tile.id] else {
                return false
            }
            let midpoint = projected(point: frame.origin) + projected(size: frame.size) / 2
            return positionValue < midpoint
        }?.offset ?? visibleTiles.count

        let currentDestinationIndex = currentDropDestinationIndex(for: section, isTileDrag: isTileDrag)
        guard currentDestinationIndex != destinationIndex else {
            return
        }

        Self.logger.debug(
            "Drag destination updated sourceTileID=\(sourceTileID, privacy: .public) section=\(dropSectionDescription(section), privacy: .public) index=\(destinationIndex, privacy: .public) previous=\(optionalIndexDescription(currentDestinationIndex), privacy: .public) visibleTileCount=\(visibleTiles.count, privacy: .public) position=\(positionValue, privacy: .public) tileDrag=\(isTileDrag, privacy: .public)"
        )

        withAnimation(tileMutationAnimation) {
            setDropDestination(section: section, index: destinationIndex, isTileDrag: isTileDrag)
        }
    }

    private func updatePalettePreviewDestination(info: DropInfo, at location: CGPoint) {
        if info.hasItemsConforming(to: [UTType.fileURL]) {
            updateExternalFilePreviewDestination(info: info, at: location)
            return
        }

        guard let palettePreviewTile else {
            editMode.paletteDropDestination = nil
            return
        }

        updatePreviewDestination(
            at: projected(point: location),
            sourceTileID: palettePreviewTile.id,
            isTileDrag: false,
            isPinnedSource: false,
            isTrailingSource: false,
            canDropIntoPinned: makePinnedItem(from: editMode.paletteDrag) != nil,
            canDropIntoTrailing: makeTrailingItem(from: editMode.paletteDrag) != nil
        )
    }

    private func updateExternalFilePreviewDestination(info: DropInfo, at location: CGPoint) {
        lastExternalFileDropLocation = location
        let providers = info.itemProviders(for: [UTType.fileURL])
        if let targetTileID = appDocumentDropTargetTileID(for: location, providers: providers) {
            guard targetTileID != externalDocumentDropTargetTileID
                    || externalAppDropDestinationIndex != nil
                    || externalFolderDropDestinationIndex != nil else {
                return
            }

            withAnimation(tileMutationAnimation) {
                externalDocumentDropTargetTileID = targetTileID
                externalAppDropDestinationIndex = nil
                externalFolderDropDestinationIndex = nil
            }
            return
        }

        externalDocumentDropTargetTileID = nil
        let positionValue = projected(point: location)
        let shouldPreviewPinnedAppDrop = containsOnlyLikelyApplicationBundleProviders(providers)

        if shouldPreviewPinnedAppDrop && isPointInPinnedDropRegion(positionValue) {
            let visibleTiles = previewPinnedBaseTiles
            let destinationIndex = visibleTiles.enumerated().first { _, tile in
                guard let frame = tileFrames[tile.id] else {
                    return false
                }
                let midpoint = projected(point: frame.origin) + projected(size: frame.size) / 2
                return positionValue < midpoint
            }?.offset ?? visibleTiles.count

            guard destinationIndex != externalAppDropDestinationIndex || externalFolderDropDestinationIndex != nil else {
                return
            }
            
            withAnimation(tileMutationAnimation) {
                externalAppDropDestinationIndex = destinationIndex
                externalFolderDropDestinationIndex = nil
            }
            return
        }

        guard !shouldPreviewPinnedAppDrop,
              isPointInTrailingDropRegion(positionValue) else {
            withAnimation(tileMutationAnimation) {
                clearExternalFileDropState()
            }
            return
        }

        let visibleTiles = previewTrailingTiles
        let destinationIndex = visibleTiles.enumerated().first { _, tile in
            guard let frame = tileFrames[tile.id] else {
                return false
            }
            let midpoint = projected(point: frame.origin) + projected(size: frame.size) / 2
            return positionValue < midpoint
        }?.offset ?? visibleTiles.count

        guard destinationIndex != externalFolderDropDestinationIndex else {
            return
        }

        withAnimation(tileMutationAnimation) {
            externalAppDropDestinationIndex = nil
            externalFolderDropDestinationIndex = destinationIndex
        }
    }

    private func clearExternalFileDropState() {
        externalAppDropDestinationIndex = nil
        externalFolderDropDestinationIndex = nil
        externalDocumentDropTargetTileID = nil
        lastExternalFileDropLocation = nil
    }

    private func inferredExternalAppDropDestinationIndex() -> Int? {
        guard let location = lastExternalFileDropLocation else {
            return nil
        }

        let positionValue = projected(point: location)
        guard isPointInPinnedDropRegion(positionValue) else {
            return nil
        }

        let visibleTiles = previewPinnedBaseTiles
        return visibleTiles.enumerated().first { _, tile in
            guard let frame = tileFrames[tile.id] else {
                return false
            }
            let midpoint = projected(point: frame.origin) + projected(size: frame.size) / 2
            return positionValue < midpoint
        }?.offset ?? visibleTiles.count
    }

    private func appDocumentDropTargetTileID(for location: CGPoint, providers: [NSItemProvider]) -> String? {
        guard containsNonAppFileProvider(providers) else {
            return nil
        }

        for tile in displayTiles.reversed() {
            guard appDocumentDropBundleIdentifier(for: tile) != nil,
                  let frame = tileFrames[tile.id],
                  frame.contains(location) else {
                continue
            }

            return tile.id
        }

        return nil
    }

    private func appDocumentDropBundleIdentifier(forTileID tileID: String) -> String? {
        guard let tile = displayTiles.first(where: { $0.id == tileID }) else {
            return nil
        }

        return appDocumentDropBundleIdentifier(for: tile)
    }

    private func appDocumentDropBundleIdentifier(for tile: Tile) -> String? {
        guard !editMode.isActive,
              case .app(let app) = tile.content,
              app.displayedWidget == nil,
              !app.bundleIdentifier.isEmpty else {
            return nil
        }

        return app.bundleIdentifier
    }

    private func containsOnlyLikelyApplicationBundleProviders(_ providers: [NSItemProvider]) -> Bool {
        let fileURLProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileURLProviders.isEmpty else {
            return false
        }

        return fileURLProviders.allSatisfy(isLikelyApplicationBundleProvider(_:))
    }

    private func containsNonAppFileProvider(_ providers: [NSItemProvider]) -> Bool {
        providers
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
            .contains { !isLikelyApplicationBundleProvider($0) }
    }

    private func isLikelyApplicationBundleProvider(_ provider: NSItemProvider) -> Bool {
        if let suggestedName = provider.suggestedName,
           suggestedName.lowercased().hasSuffix(".app") {
            return true
        }

        return provider.registeredTypeIdentifiers.contains { identifier in
            guard let type = UTType(identifier) else {
                return false
            }
            return type.conforms(to: .application)
        }
    }

    private func makeTrailingFolderItem(from url: URL) -> TrailingTileItem? {
        guard isDroppableFolder(url) else {
            return nil
        }

        let displayName = FileManager.default.displayName(atPath: url.path)
        return TrailingTileItem.folder(url: url, displayName: displayName)
    }

    private func bundleIdentifierForDroppedApp(from url: URL) -> String? {
        guard isDroppableApp(url) else {
            return nil
        }
        return Bundle(url: url)?.bundleIdentifier
    }

    private func isDroppableFolder(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    private func isDroppableApp(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .typeIdentifierKey])
        guard values?.isDirectory == true, values?.isPackage == true else {
            return false
        }

        return url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
            || values?.typeIdentifier == UTType.application.identifier
    }

    private func resolveDroppedURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let fileURLProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileURLProviders.isEmpty else {
            completion([])
            return
        }

        let dispatchGroup = DispatchGroup()
        let lock = NSLock()
        var resolvedURLs: [URL] = []

        for provider in fileURLProviders {
            dispatchGroup.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { dispatchGroup.leave() }
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                lock.lock()
                resolvedURLs.append(url)
                lock.unlock()
            }
        }

        dispatchGroup.notify(queue: .global(qos: .userInitiated)) {
            let sanitizedURLs = sanitizedDroppedURLs(resolvedURLs)
            logDroppedURLs(rawURLs: resolvedURLs, sanitizedURLs: sanitizedURLs)
            completion(sanitizedURLs)
        }
    }

    private func sanitizedDroppedURLs(_ urls: [URL]) -> [URL] {
        let normalizedURLs = urls.map {
            $0.standardizedFileURL.resolvingSymlinksInPath()
        }

        var deduplicatedURLs: [URL] = []
        var seenPaths: Set<String> = []
        for url in normalizedURLs {
            guard seenPaths.insert(url.path).inserted else {
                continue
            }
            deduplicatedURLs.append(url)
        }

        return deduplicatedURLs.filter { candidateURL in
            !deduplicatedURLs.contains { otherURL in
                otherURL != candidateURL && otherURL.path.hasPrefix(candidateURL.path + "/")
            }
        }
    }

    private func logDroppedURLs(rawURLs: [URL], sanitizedURLs: [URL]) {
        let rawPaths = rawURLs.map(\.path)
        let sanitizedPaths = sanitizedURLs.map(\.path)
        NSLog("[Docky] External drop raw URLs: \(rawPaths)")
        NSLog("[Docky] External drop sanitized URLs: \(sanitizedPaths)")
    }

    private func isPointInPinnedDropRegion(_ positionValue: CGFloat) -> Bool {
        guard let finderFrame = tileFrames["pinned:com.apple.finder"],
              let trailingBoundaryFrame = tileFrames[pinnedTrailingBoundaryTileID] else {
            return false
        }

        let lowerBound = projected(point: finderFrame.origin) + projected(size: finderFrame.size)
        let upperBound = projected(point: trailingBoundaryFrame.origin)
        return positionValue >= lowerBound && positionValue <= upperBound
    }

    private var pinnedTrailingBoundaryTileID: String {
        tileFrames.keys.contains("divider:running") ? "divider:running" : "divider:trailing"
    }

    private func isPointInTrailingDropRegion(_ positionValue: CGFloat) -> Bool {
        guard let dividerFrame = tileFrames["divider:trailing"],
              let lastTrailingTileID = previewTrailingTiles.last?.id,
              let trailingBoundaryFrame = tileFrames[lastTrailingTileID] else {
            return false
        }

        let lowerBound = projected(point: dividerFrame.origin) + projected(size: dividerFrame.size)
        let upperBound = projected(point: trailingBoundaryFrame.origin) + projected(size: trailingBoundaryFrame.size)
        return positionValue >= lowerBound && positionValue <= upperBound
    }

    private func previewTiles(for section: DockEditDropSection) -> [Tile] {
        switch section {
        case .pinned:
            previewPinnedBaseTiles
        case .trailing:
            previewTrailingTiles
        }
    }

    private func currentDropDestinationIndex(for section: DockEditDropSection, isTileDrag: Bool) -> Int? {
        if isTileDrag {
            return switch section {
            case .pinned: draggedPinnedTileDestinationIndex
            case .trailing: draggedTrailingTileDestinationIndex
            }
        }

        guard editMode.paletteDropDestination?.section == section else {
            return nil
        }
        return editMode.paletteDropDestination?.index
    }

    private func setDropDestination(section: DockEditDropSection, index: Int?, isTileDrag: Bool) {
        if isTileDrag {
            switch section {
            case .pinned:
                draggedPinnedTileDestinationIndex = index
            case .trailing:
                draggedTrailingTileDestinationIndex = index
            }
            return
        }

        if let index {
            editMode.paletteDropDestination = DockEditDropDestination(section: section, index: index)
        } else {
            editMode.paletteDropDestination = nil
        }
    }

    private func clearDragState() {
        if draggedTileID != nil {
            Self.logger.debug(
                "Clearing drag state tileID=\(draggedTileID ?? "nil", privacy: .public) pinnedDestination=\(optionalIndexDescription(draggedPinnedTileDestinationIndex), privacy: .public) trailingDestination=\(optionalIndexDescription(draggedTrailingTileDestinationIndex), privacy: .public) folderTarget=\(draggedAppFolderTargetTileID ?? "nil", privacy: .public)"
            )
        }
        draggedTileID = nil
        draggedTileOffset = 0
        draggedTileInitialFrame = nil
        draggedPinnedTileDestinationIndex = nil
        draggedTrailingTileDestinationIndex = nil
        draggedAppFolderTargetTileID = nil
        draggedAdditionalTileIDs = []
        draggedPickupCandidateTileID = nil
    }

    private func bundleIdentifier(for tile: Tile) -> String? {
        guard case .app(let app) = tile.content else {
            return nil
        }
        return app.bundleIdentifier.isEmpty ? nil : app.bundleIdentifier
    }

    private func optionalIndexDescription(_ index: Int?) -> String {
        guard let index else {
            return "nil"
        }
        return String(index)
    }

    private func dropSectionDescription(_ section: DockEditDropSection) -> String {
        switch section {
        case .pinned:
            return "pinned"
        case .trailing:
            return "trailing"
        }
    }

    private func tileLogDescription(_ tile: Tile) -> String {
        "\(tile.id):\(tileKindDescription(tile))"
    }

    private func tileKindDescription(_ tile: Tile) -> String {
        switch tile.content {
        case .app(let app):
            return "app(\(app.bundleIdentifier))"
        case .appFolder(let folder):
            return "appFolder(\(folder.identifier))"
        case .folder(let folder):
            return "folder(\(folder.url.lastPathComponent))"
        case .widget(let widget):
            return "widget(\(widget.kind.rawValue))"
        case .smartStack:
            return "smartStack"
        case .spacer:
            return "spacer"
        case .divider:
            return "divider"
        case .launchpad:
            return "launchpad"
        case .trash:
            return "trash"
        case .minimizedWindow(let window):
            return "minimizedWindow(\(window.windowIdentifier))"
        }
    }

    private func bundleIdentifier(forTileID tileID: String) -> String? {
        guard let tile = store.tiles.first(where: { $0.id == tileID }) else {
            return nil
        }

        return bundleIdentifier(for: tile)
    }

    private func appFolderDropTargetTileID(
        at location: CGPoint,
        selectedTileIDs: Set<String>,
        selectedBundleIdentifiers: [String]
    ) -> String? {
        let selectedBundleIdentifierSet = Set(selectedBundleIdentifiers)

        for tile in previewPinnedBaseTiles where !selectedTileIDs.contains(tile.id) {
            switch tile.content {
            case .app(let app):
                guard !selectedBundleIdentifierSet.contains(app.bundleIdentifier) else {
                    continue
                }
            case .minimizedWindow:
                continue
            case .appFolder(let folder):
                guard folder.bundleIdentifiers.allSatisfy({ !selectedBundleIdentifierSet.contains($0) }) else {
                    continue
                }
            case .launchpad, .widget, .smartStack, .folder, .spacer, .divider, .trash:
                continue
            }

            guard let frame = tileFrames[tile.id] else {
                continue
            }

            let targetFrame = frame.insetBy(dx: frame.width * 0.18, dy: frame.height * 0.18)
            if targetFrame.contains(location) {
                return tile.id
            }
        }

        return nil
    }

    private func dragPickupCandidateTileID(at location: CGPoint) -> String? {
        guard isCollectingAdditionalAppsDuringDrag else {
            return nil
        }

        let selectedBundleIdentifiers = Set(draggedSelectionBundleIdentifiers)

        for tile in displayTiles.reversed() {
            guard !draggedSelectionTileIDs.contains(tile.id),
                  let bundleIdentifier = bundleIdentifier(for: tile),
                  !selectedBundleIdentifiers.contains(bundleIdentifier),
                  let frame = tileFrames[tile.id] else {
                continue
            }

            let targetFrame = frame.insetBy(dx: frame.width * 0.18, dy: frame.height * 0.18)
            if targetFrame.contains(location) {
                return tile.id
            }
        }

        return nil
    }

    private func groupedOpenedAppFolderID(for tileID: String) -> String? {
        guard tileID.hasPrefix("folder-running:") else {
            return nil
        }

        let suffix = tileID.dropFirst("folder-running:".count)
        guard let separatorIndex = suffix.lastIndex(of: ":") else {
            return nil
        }

        return String(suffix[..<separatorIndex])
    }

    private func projected(size: CGSize) -> CGFloat {
        position.isVertical ? size.height : size.width
    }

    private func projected(point: CGPoint) -> CGFloat {
        position.isVertical ? point.y : point.x
    }

    private func axisSize(value: CGFloat) -> CGSize {
        position.isVertical ? CGSize(width: 0, height: value) : CGSize(width: value, height: 0)
    }

    static func size(
        for tile: Tile,
        tileSize: CGFloat,
        tileHeight: CGFloat,
        tileSpacing: CGFloat = 0,
        position: ResolvedDockWindowPosition,
        compactWidgets: Bool = false
    ) -> CGSize {
        let dividerExtent = tileSize * 0.5

        return switch (position.isVertical, tile.content) {
        case (false, .divider):
            CGSize(width: dividerExtent, height: tileHeight)
        case (false, .app(let app)) where app.displayedWidget != nil:
            CGSize(
                width: spanExtent(
                    for: effectiveWidgetSpan(app.displayedWidget?.span ?? .one, tileSize: tileSize, isVertical: false, compactWidgets: compactWidgets),
                    baseTileSize: tileSize,
                    tileSpacing: tileSpacing
                ),
                height: tileHeight
            )
        case (false, .widget(let widget)):
            CGSize(width: spanExtent(for: effectiveWidgetSpan(widget.span, tileSize: tileSize, isVertical: false, compactWidgets: compactWidgets), baseTileSize: tileSize, tileSpacing: tileSpacing), height: tileHeight)
        case (false, .smartStack(let stack)):
            CGSize(width: spanExtent(for: effectiveWidgetSpan(stack.span, tileSize: tileSize, isVertical: false, compactWidgets: compactWidgets), baseTileSize: tileSize, tileSpacing: tileSpacing), height: tileHeight)
        case (false, _):
            CGSize(width: tileSize, height: tileHeight)
        case (true, .divider):
            CGSize(width: tileHeight / 2, height: dividerExtent)
        case (true, .app(let app)) where app.displayedWidget != nil:
            CGSize(
                width: tileHeight,
                height: spanExtent(
                    for: effectiveWidgetSpan(app.displayedWidget?.span ?? .one, tileSize: tileSize, isVertical: true, compactWidgets: compactWidgets),
                    baseTileSize: tileSize,
                    tileSpacing: tileSpacing
                )
            )
        case (true, .widget(let widget)):
            CGSize(width: tileHeight, height: spanExtent(for: effectiveWidgetSpan(widget.span, tileSize: tileSize, isVertical: true, compactWidgets: compactWidgets), baseTileSize: tileSize, tileSpacing: tileSpacing))
        case (true, .smartStack(let stack)):
            CGSize(width: tileHeight, height: spanExtent(for: effectiveWidgetSpan(stack.span, tileSize: tileSize, isVertical: true, compactWidgets: compactWidgets), baseTileSize: tileSize, tileSpacing: tileSpacing))
        case (true, _):
            CGSize(width: tileHeight, height: tileSize)
        }
    }

    private static func effectiveWidgetSpan(_ span: TileSpan, tileSize: CGFloat, isVertical: Bool, compactWidgets: Bool) -> TileSpan {
        if compactWidgets || isVertical || tileSize < 50 {
            return .one
        }

        return span
    }

    private static func spanExtent(for span: TileSpan, baseTileSize: CGFloat, tileSpacing: CGFloat) -> CGFloat {
        let spanCount = CGFloat(span.rawValue)
        return baseTileSize * spanCount + tileSpacing * max(0, spanCount - 1)
    }

    /// Total content size for the given tile list, including inter-tile spacing
    /// and outer stack padding. Used by MainWindow to size itself to fit.
    static func contentSize(
        tiles: [Tile],
        tileSize: CGFloat,
        tileHeight: CGFloat,
        tileSpacing: CGFloat,
        position: ResolvedDockWindowPosition,
        compactWidgets: Bool = false,
        edgePadding: CGFloat = Self.edgePadding
    ) -> CGSize {
        let sizes = tiles.map {
            size(for: $0, tileSize: tileSize, tileHeight: tileHeight, tileSpacing: tileSpacing, position: position, compactWidgets: compactWidgets)
        }
        let spacings = max(0, CGFloat(tiles.count) - 1) * tileSpacing

        if position.isVertical {
            let height = sizes.reduce(CGFloat(0)) { $0 + $1.height } + spacings + edgePadding * 2
            let width = sizes.map(\.width).max() ?? tileSize
            return CGSize(width: width, height: height)
        }

        let width = sizes.reduce(CGFloat(0)) { $0 + $1.width } + spacings + edgePadding * 2
        let height = sizes.map(\.height).max() ?? tileHeight
        return CGSize(width: width, height: height)
    }

    static func previewedTiles(
        from tiles: [Tile],
        paletteDrag: DockEditPaletteDrag?,
        paletteDropDestination: DockEditDropDestination?
    ) -> [Tile] {
        guard let paletteDrag,
              let paletteDropDestination,
              let previewTile = palettePreviewTile(for: paletteDrag) else {
            return tiles
        }

        var previewTiles = tiles

        switch paletteDropDestination.section {
        case .pinned:
            let insertionIndex = previewTiles.firstIndex(where: { $0.id == "divider:trailing" }) ?? previewTiles.count
            previewTiles.insert(previewTile, at: insertionIndex)
        case .trailing:
            let insertionIndex = min(
                max(0, (previewTiles.firstIndex(where: { $0.id == "divider:trailing" }) ?? (previewTiles.count - 1)) + 1),
                previewTiles.count
            )
            previewTiles.insert(previewTile, at: insertionIndex)
        }

        return previewTiles
    }

    private static func palettePreviewTile(for paletteDrag: DockEditPaletteDrag) -> Tile? {
        if let feature = paletteDrag.item.productFeature,
           !ProductService.shared.availability(for: feature, context: .newPlacement).allowsNewPlacement {
            return nil
        }

        switch paletteDrag.item {
        case .launchpad:
            return Tile(
                id: "editor-preview:launchpad",
                content: .launchpad(LaunchpadTile(identifier: "editor-preview:launchpad"))
            )
        case .spacer:
            return Tile(id: "editor-preview:spacer", content: .spacer)
        case .divider:
            return Tile(id: "editor-preview:divider", content: .divider)
        case .widget(let ownerBundleIdentifier, let kind):
            return Tile(
                id: "editor-preview:widget",
                content: .widget(WidgetTile(
                    identifier: "editor-preview:widget",
                    title: kind.title,
                    kind: kind,
                    ownerBundleIdentifier: ownerBundleIdentifier,
                    span: resolvedPaletteWidgetSpan(
                        ownerBundleIdentifier: ownerBundleIdentifier,
                        kind: kind,
                        requestedSpan: paletteDrag.widgetSpan
                    )
                ))
            )
        case .smartStack:
            return Tile(
                id: "editor-preview:smart-stack",
                content: .smartStack(SmartStackTile(
                    identifier: "editor-preview:smart-stack",
                    title: "Smart Stack",
                    widgets: WidgetCatalog.smartStackRegistrations.map { $0.makeTile() },
                    span: .three
                ))
            )
        }
    }

    private static func resolvedPaletteWidgetSpan(
        ownerBundleIdentifier: String,
        kind: WidgetKind,
        requestedSpan: TileSpan?
    ) -> TileSpan {
        let supportedSpans = kind.supportedSpans
        if let requestedSpan, supportedSpans.contains(requestedSpan) {
            return requestedSpan
        }

        if let catalogSpan = WidgetCatalog.staticRegistrations.first(where: {
            $0.ownerBundleIdentifier == ownerBundleIdentifier && $0.kind == kind
        })?.defaultSpan,
           supportedSpans.contains(catalogSpan) {
            return catalogSpan
        }

        return supportedSpans.last ?? .one
    }
}

private struct TileLayoutSection: Identifiable {
    let id: String
    let tiles: [Tile]
}

private enum TileLayoutComponent: Identifiable {
    case section(TileLayoutSection)
    case divider(Tile)

    var id: String {
        switch self {
        case .section(let section):
            "section:\(section.id)"
        case .divider(let tile):
            tile.id
        }
    }
}

private struct ScrollableSectionLayout {
    let id: String
    let axisLength: CGFloat
}

private struct PaletteInsertDropDelegate: DropDelegate {
    let updateLocation: (DropInfo) -> Void
    let clearPreview: () -> Void
    let performInsert: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText, UTType.fileURL])
    }

    func dropEntered(info: DropInfo) {
        updateLocation(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateLocation(info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        clearPreview()
    }

    func performDrop(info: DropInfo) -> Bool {
        updateLocation(info)
        return performInsert(info.itemProviders(for: [UTType.plainText, UTType.fileURL]))
    }
}

private struct TileFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TileDragKeyMonitor: NSViewRepresentable {
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

        deinit {
            stop()
        }
    }
}
