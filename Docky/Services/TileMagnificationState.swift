//
//  TileMagnificationState.swift
//  Docky
//
//  Resolved magnification for the dock, kept outside the view tree.
//
//  The tile canvas used to read the pointer while building its views, so
//  every pointer move rebuilt and diffed every tile in the dock even though
//  only the few under the cursor change size. Now the canvas hands its
//  layout inputs here once (when they change), pointer moves resolve sizes
//  here, and each tile observes only its own size. A pointer move then
//  re-renders just the tiles whose size changed, plus the anchor offset.
//

import CoreGraphics
import Foundation
import Observation

/// Magnified icon side for one tile. Observed per tile so a size change
/// re-renders only that tile.
@Observable
final class TileMagnificationSlot {
    /// Nil while the tile sits at its resting size.
    fileprivate(set) var iconSize: CGFloat?
}

@Observable
final class TileMagnificationState {
    static let shared = TileMagnificationState()

    /// Inputs for resolving magnification that don't depend on the pointer.
    /// Built by the tile canvas whenever its layout changes.
    struct Context {
        var canvasOrigin: CGPoint
        var canvasAxisLength: CGFloat
        var contentAxisLength: CGFloat
        /// Whether the canvas centers the tile stack. When false the stack
        /// is pinned to the leading edge (a shrunk or compacted dock).
        /// Must match the alignment the canvas actually renders with, or
        /// the cursor maps onto the wrong tiles.
        var centersContent: Bool
        var isVertical: Bool
        var items: [DockMagnificationLayout.Item]
        var spacing: CGFloat
        var edgePadding: CGFloat
        var restIconSize: CGFloat
        var maxIconSize: CGFloat
        /// Along-axis extent of the item at an index once its icon side is
        /// magnified to the given size.
        var magnifiedExtent: (Int, CGFloat) -> CGFloat
    }

    /// Shift applied to the whole tile stack so the icon under the cursor
    /// stays put as its neighbors grow.
    private(set) var anchorOffset: CGFloat = 0

    @ObservationIgnored private var slots: [String: TileMagnificationSlot] = [:]
    @ObservationIgnored private var context: Context?
    @ObservationIgnored private var isResolveScheduled = false
    @ObservationIgnored private let pointer = DockMagnificationService.shared

    private init() {
        pointer.onUpdate = { [weak self] in
            self?.resolve()
        }
    }

    func slot(for tileID: String) -> TileMagnificationSlot {
        if let slot = slots[tileID] {
            return slot
        }
        let slot = TileMagnificationSlot()
        slots[tileID] = slot
        return slot
    }

    /// Called while the canvas builds its views, so the resolve is deferred
    /// rather than mutating observed state in the middle of a view update.
    /// Nil means magnification is suppressed.
    func setContext(_ context: Context?) {
        self.context = context
        guard !isResolveScheduled else { return }
        isResolveScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isResolveScheduled = false
            resolve()
        }
    }

    private func resolve() {
        guard let context, let location = pointer.pointerLocation else {
            apply(iconSizes: [:], anchorOffset: 0, growth: 0)
            return
        }

        // Pointer projected onto the dock axis, relative to the leading edge
        // of the tile stack so it compares directly with the tiles' rest
        // centers. A centered stack has a leading gap that is removed from
        // the cursor first.
        let local = CGPoint(x: location.x - context.canvasOrigin.x, y: location.y - context.canvasOrigin.y)
        let cursorInCanvas = context.isVertical ? local.y : local.x
        let leadingGap = max(0, context.canvasAxisLength - context.contentAxisLength) / 2
        let cursor = context.centersContent ? cursorInCanvas - leadingGap : cursorInCanvas

        let model = DockMagnificationModel(
            baseSize: context.restIconSize,
            maxSize: context.maxIconSize,
            influenceRadius: context.restIconSize * 2.5,
            strength: pointer.strength,
            cursorAxisLocation: cursor
        )
        let resolved = DockMagnificationLayout(
            items: context.items,
            spacing: context.spacing,
            edgePadding: context.edgePadding,
            restIconSize: context.restIconSize,
            model: model,
            cursor: cursor,
            magnifiedExtent: context.magnifiedExtent
        )

        // Centered mode skips the anchor shift: the stack's own centering
        // already splits growth across both sides. A leading-pinned stack
        // is shifted so the icon under the cursor stays put, and the chrome
        // moves with it: the magnified stack spans [anchor, anchor + rest
        // length + growth], so its center sits anchor + growth / 2 away
        // from where it rests.
        let anchorOffset = context.centersContent ? 0 : cursor - resolved.anchoredMag
        apply(
            iconSizes: resolved.iconSizes.filter { $0.value > context.restIconSize },
            anchorOffset: anchorOffset,
            growth: resolved.totalGrowth,
            chromeOffset: context.centersContent ? 0 : anchorOffset + resolved.totalGrowth / 2
        )
    }

    private func apply(
        iconSizes: [String: CGFloat],
        anchorOffset: CGFloat,
        growth: CGFloat,
        chromeOffset: CGFloat = 0
    ) {
        for (tileID, slot) in slots {
            let iconSize = iconSizes[tileID]
            if slot.iconSize != iconSize {
                slot.iconSize = iconSize
            }
        }
        if self.anchorOffset != anchorOffset {
            self.anchorOffset = anchorOffset
        }
        DockChromeMetricsService.shared.setAlongAxis(growth: growth, offset: chromeOffset)
    }
}
