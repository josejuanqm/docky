//
//  TileContainerView.swift
//  Docky
//

import SwiftUI
import UniformTypeIdentifiers

struct TileContainerView: View {
    static let edgePadding: CGFloat = 8
    static let dividerWidth: CGFloat = 40
    private let tileMutationAnimation: Animation = .easeInOut(duration: 0.18)

    @ObservedObject private var store = TileStore.shared
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var editMode = DockEditModeService.shared

    @State private var draggedTileID: String?
    @State private var draggedTileOffset: CGFloat = 0
    @State private var draggedTileInitialFrame: CGRect?
    @State private var draggedPinnedTileDestinationIndex: Int?
    @State private var tileFrames: [String: CGRect] = [:]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Group {
                    if position.isVertical {
                        VStack(spacing: preferences.tileSpacing) {
                            tileViews
                        }
                        .padding(.vertical, Self.edgePadding)
                    } else {
                        HStack(spacing: preferences.tileSpacing) {
                            tileViews
                        }
                        .padding(.horizontal, Self.edgePadding)
                    }
                }

                draggedTileOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(TileFramePreferenceKey.self) { tileFrames = $0 }
            .onChange(of: editMode.paletteDrag) { _, paletteDrag in
                guard paletteDrag != nil else {
                    editMode.paletteDropDestinationIndex = nil
                    return
                }
            }
            .onDrop(of: [UTType.plainText], delegate: PaletteInsertDropDelegate(
                updateLocation: { location in
                    let globalLocation = CGPoint(
                        x: proxy.frame(in: .global).minX + location.x,
                        y: proxy.frame(in: .global).minY + location.y
                    )
                    updatePalettePreviewDestination(at: globalLocation)
                },
                clearPreview: {
                    editMode.endPaletteDrag()
                },
                performInsert: {
                    guard let kind = editMode.paletteDrag?.kind,
                          let destinationIndex = editMode.paletteDropDestinationIndex else {
                        editMode.endPaletteDrag()
                        return false
                    }

                    TileStore.shared.insertPinnedItem(kind: kind, at: destinationIndex)
                    editMode.endPaletteDrag()
                    return true
                }
            ))
            .animation(tileMutationAnimation, value: displayTiles)
        }
    }

    @ViewBuilder
    private var tileViews: some View {
        ForEach(displayTiles) { tile in
            let size = Self.size(
                for: tile,
                tileSize: dockSettings.tileSize,
                tileHeight: tileHeight,
                tileSpacing: preferences.tileSpacing,
                position: position
            )
            TileView(tile: tile)
                .frame(width: size.width, height: size.height)
                .opacity(tile.id == draggedTileID ? 0 : 1)
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
    }

    @ViewBuilder
    private var draggedTileOverlay: some View {
        if let draggedTile {
            let size = Self.size(
                for: draggedTile,
                tileSize: dockSettings.tileSize,
                tileHeight: tileHeight,
                tileSpacing: preferences.tileSpacing,
                position: position
            )
            TileView(tile: draggedTile)
                .frame(width: size.width, height: size.height)
                .position(draggedTilePosition)
                .offset(axisSize(value: draggedTileOffset))
                .zIndex(10)
                .allowsHitTesting(false)
        }
    }

    private var displayTiles: [Tile] {
        guard let finderTile = store.tiles.first else {
            return store.tiles
        }

        var result: [Tile] = [finderTile]
        result.append(contentsOf: previewPinnedTiles)

        for tile in store.tiles.dropFirst() {
            if isPinnedReorderable(tileID: tile.id) || shouldHideDraggedOriginalTile(tileID: tile.id) {
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

    private var previewPinnedTiles: [Tile] {
        guard let destinationIndex = activePinnedDropDestinationIndex else {
            return pinnedTiles
        }

        var remainingPinnedTiles = pinnedTiles
        if let draggedTileID {
            remainingPinnedTiles.removeAll { $0.id == draggedTileID }
        }
        let clampedDestinationIndex = min(max(destinationIndex, 0), remainingPinnedTiles.count)
        if let draggedTile {
            remainingPinnedTiles.insert(draggedTile, at: clampedDestinationIndex)
        } else if let palettePreviewTile {
            remainingPinnedTiles.insert(palettePreviewTile, at: clampedDestinationIndex)
        }
        return remainingPinnedTiles
    }

    private var palettePreviewTile: Tile? {
        guard let paletteDrag = editMode.paletteDrag else {
            return nil
        }

        switch paletteDrag.kind {
        case .app:
            return nil
        case .spacer:
            return Tile(id: "editor-preview:spacer", content: .spacer)
        case .divider:
            return Tile(id: "editor-preview:divider", content: .divider)
        }
    }

    private var draggedTile: Tile? {
        guard let draggedTileID else {
            return nil
        }

        return store.tiles.first { $0.id == draggedTileID }
    }

    private var draggedTilePosition: CGPoint {
        guard let frame = draggedTileInitialFrame else {
            return .zero
        }

        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private var activePinnedDropDestinationIndex: Int? {
        draggedTileID == nil ? editMode.paletteDropDestinationIndex : draggedPinnedTileDestinationIndex
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

    private var tileHeight: CGFloat {
        let iconHeight = dockSettings.magnification ? dockSettings.largeSize : dockSettings.tileSize
        return iconHeight + preferences.tileVerticalPadding * 2
    }

    private var position: ResolvedDockWindowPosition {
        preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
    }

    private func isPinnedReorderable(tileID: String) -> Bool {
        store.isPinnedReorderable(tileID: tileID)
    }

    private func isTileDraggable(_ tile: Tile) -> Bool {
        switch tile.content {
        case .app(let app):
            return !app.bundleIdentifier.isEmpty && app.bundleIdentifier != "com.apple.finder"
        case .spacer, .divider:
            return editMode.isActive && isPinnedReorderable(tileID: tile.id)
        case .widget, .smartStack, .folder, .trash:
            return false
        }
    }

    private var isDraggingPinnedTile: Bool {
        guard let draggedTileID else {
            return false
        }
        return isPinnedReorderable(tileID: draggedTileID)
    }

    private func shouldHideDraggedOriginalTile(tileID: String) -> Bool {
        guard tileID == draggedTileID else {
            return false
        }
        return !isDraggingPinnedTile && draggedPinnedTileDestinationIndex != nil
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
            draggedTileInitialFrame = tileFrames[tile.id]
            draggedPinnedTileDestinationIndex = isPinnedReorderable(tileID: tile.id) ? pinnedTileIDs.firstIndex(of: tile.id) : nil
        }

        guard draggedTileID == tile.id else {
            return
        }

        draggedTileOffset = projected(size: value.translation)
        updatePreviewDestination(
            at: projected(point: value.location),
            sourceTileID: tile.id,
            isPinnedSource: isPinnedReorderable(tileID: tile.id)
        )
    }

    private func endDrag(for tile: Tile, value: DragGesture.Value) {
        updateDrag(for: tile, value: value)

        guard draggedTileID == tile.id else {
            clearDragState()
            return
        }

        if isPinnedReorderable(tileID: tile.id) {
            let finalPinnedTileIDs = previewPinnedTiles.map(\.id)
            if finalPinnedTileIDs != pinnedTileIDs {
                store.setPinnedTileOrder(ids: finalPinnedTileIDs)
            }
        } else if let destinationIndex = draggedPinnedTileDestinationIndex,
                  let bundleIdentifier = draggedBundleIdentifier {
            _ = store.pinApp(bundleIdentifier: bundleIdentifier, at: destinationIndex)
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

    private func updatePreviewDestination(at positionValue: CGFloat, sourceTileID: String, isPinnedSource: Bool) {
        guard isPointInPinnedDropRegion(positionValue) || isPinnedSource else {
            if isPinnedSource {
                draggedPinnedTileDestinationIndex = nil
            } else {
                editMode.paletteDropDestinationIndex = nil
            }
            return
        }

        let visiblePinnedTiles = previewPinnedTiles.filter { $0.id != sourceTileID }
        guard !visiblePinnedTiles.isEmpty else {
            if isPinnedSource {
                draggedPinnedTileDestinationIndex = 0
            } else {
                editMode.paletteDropDestinationIndex = 0
            }
            return
        }

        let destinationIndex = visiblePinnedTiles.enumerated().first { _, tile in
            guard let frame = tileFrames[tile.id] else {
                return false
            }
            let midpoint = projected(point: frame.origin) + projected(size: frame.size) / 2
            return positionValue < midpoint
        }?.offset ?? visiblePinnedTiles.count

        let currentDestinationIndex = isPinnedSource ? draggedPinnedTileDestinationIndex : editMode.paletteDropDestinationIndex
        guard currentDestinationIndex != destinationIndex else {
            return
        }

        withAnimation(tileMutationAnimation) {
            if isPinnedSource {
                draggedPinnedTileDestinationIndex = destinationIndex
            } else {
                editMode.paletteDropDestinationIndex = destinationIndex
            }
        }
    }

    private func updatePalettePreviewDestination(at location: CGPoint) {
        guard let palettePreviewTile else {
            editMode.paletteDropDestinationIndex = nil
            return
        }

        updatePreviewDestination(
            at: projected(point: location),
            sourceTileID: palettePreviewTile.id,
            isPinnedSource: false
        )
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

    private func clearDragState() {
        draggedTileID = nil
        draggedTileOffset = 0
        draggedTileInitialFrame = nil
        draggedPinnedTileDestinationIndex = nil
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
        position: ResolvedDockWindowPosition
    ) -> CGSize {
        switch (position.isVertical, tile.content) {
        case (false, .divider):
            CGSize(width: dividerWidth, height: tileHeight)
        case (false, .widget(let widget)):
            CGSize(width: spanExtent(for: widget.effectiveSpan, baseTileSize: tileSize, tileSpacing: tileSpacing), height: tileHeight)
        case (false, .smartStack(let stack)):
            CGSize(width: spanExtent(for: stack.span, baseTileSize: tileSize, tileSpacing: tileSpacing), height: tileHeight)
        case (false, _):
            CGSize(width: tileSize, height: tileHeight)
        case (true, .divider):
            CGSize(width: tileHeight, height: dividerWidth)
        case (true, .widget(let widget)):
            CGSize(width: tileHeight, height: spanExtent(for: widget.effectiveSpan, baseTileSize: tileSize, tileSpacing: tileSpacing))
        case (true, .smartStack(let stack)):
            CGSize(width: tileHeight, height: spanExtent(for: stack.span, baseTileSize: tileSize, tileSpacing: tileSpacing))
        case (true, _):
            CGSize(width: tileHeight, height: tileSize)
        }
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
        position: ResolvedDockWindowPosition
    ) -> CGSize {
        let sizes = tiles.map {
            size(for: $0, tileSize: tileSize, tileHeight: tileHeight, tileSpacing: tileSpacing, position: position)
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
}

private struct PaletteInsertDropDelegate: DropDelegate {
    let updateLocation: (CGPoint) -> Void
    let clearPreview: () -> Void
    let performInsert: () -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        updateLocation(info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateLocation(info.location)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        clearPreview()
    }

    func performDrop(info: DropInfo) -> Bool {
        updateLocation(info.location)
        return performInsert()
    }
}

private struct TileFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
