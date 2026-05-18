//
//  FolderFanView.swift
//  Docky
//
//  Parabolic "fan" presentation of a folder's contents — the macOS
//  Dock's classic fan view, recreated as a borderless overlay window.
//  Items are positioned along a quadratic bow that sweeps upward from
//  the tile and animates in with a staggered spring per item.
//
//  Constraints (set by the caller, not enforced here):
//    - Only used when the dock is at the bottom edge.
//    - Only used for folders with ≤ FolderFanView.maximumItemCount items.
//  Both checks live in `TileView`'s overlay dispatch so that the fan
//  silently falls back to the grid popover when conditions don't hold.
//

import AppKit
import Combine
import SwiftUI

/// Externally-controlled expand state for the fan. Living in an
/// ObservableObject (instead of `@State` on `FolderFanView`) lets
/// the presenter's coordinator flip it back to `false` on dismiss
/// so the reverse animation plays before the window orders out.
final class FanAnimationModel: ObservableObject {
    @Published var isExpanded: Bool = false
}

struct FolderFanView: View {
    static let maximumItemCount = 10
    /// Number of items that match the tile preview pile (mirrors
    /// `FolderTileView.stack(in:)`'s 3-deep render). The first
    /// `previewSlotCount` fan items are visible at rest; everything
    /// past that hides at rest and fades in during the open
    /// animation.
    static let previewSlotCount = 3
    /// Along-arc spacing per item. Mirrored from the instance
    /// property below so the static `contentSize` helper can compute
    /// the same `deltaTheta` the live view does.
    static let perItemArcLength: CGFloat = 15

    /// Deterministic content size for the hosting NSWindow. Computing
    /// it externally avoids depending on `NSHostingView.fittingSize`,
    /// which can compress the view's explicit `.frame(...)` away
    /// when invoked before the host has a stable frame — leaving the
    /// rotated icons clipped on the right.
    static func contentSize(
        iconSize: CGFloat,
        chromeReach: CGFloat,
        itemCount: Int,
        screenLongestDimension: CGFloat
    ) -> NSSize {
        let theta = computeDeltaTheta(
            itemCount: itemCount,
            radius: screenLongestDimension
        )
        let maxCurveX = screenLongestDimension * (1 - cos(theta))
        let maxCurveY = screenLongestDimension * sin(theta)
        let w = labelMaxWidth + labelIconGap + iconSize
        let h = iconSize
        let overshootX = max(0, (w * cos(theta) + h * sin(theta) - w) / 2) + rotationOvershootSafetyPad
        let overshootY = max(0, (w * sin(theta) + h * cos(theta) - h) / 2) + rotationOvershootSafetyPad
        return NSSize(
            width: w + maxCurveX + overshootX,
            height: h + maxCurveY + bottomPadding + chromeReach + overshootY
        )
    }

    /// Mirror of `deltaTheta` for the static `contentSize` path —
    /// kept in lockstep with the instance computation.
    private static func computeDeltaTheta(itemCount: Int, radius: CGFloat) -> CGFloat {
        guard itemCount > 1, radius > 0 else { return 0 }
        let absoluteMaxSpan = CGFloat.pi * 25 / 180
        let maxScaledMinSpan = CGFloat.pi * 12.5 / 180
        let progress = CGFloat(itemCount - 1) / CGFloat(Self.maximumItemCount - 1)
        let scaledMinSpan = maxScaledMinSpan * progress
        let natural = CGFloat(itemCount - 1) * perItemArcLength / radius
        return min(absoluteMaxSpan, max(scaledMinSpan, natural))
    }

    // MARK: Layout constants (exposed for the presenter)

    static let labelMaxWidth: CGFloat = 140
    static let labelIconGap: CGFloat = 8
    static let bottomPadding: CGFloat = 4

    /// Horizontal distance from the view's leading edge to item 0's
    /// icon *center*. The presenter passes the tile-derived icon
    /// size in so window placement matches the view's layout.
    static func anchorIconOffsetX(iconSize: CGFloat) -> CGFloat {
        labelMaxWidth + labelIconGap + iconSize / 2
    }

    let folderURL: URL
    let items: [URL]
    /// Side length of each preview icon. The presenter sets this to
    /// the same 0.82× tile multiplier `FolderTileView.stack(in:)`
    /// uses for the tile's fanned preview, so the fan icons match
    /// the size of the icons the user just clicked on.
    let iconSize: CGFloat
    /// Longest side of the screen the fan is opening on, in points.
    /// Used as the circle's radius (diameter = 2× this), so items
    /// traverse a tiny arc of a very large circle — the gentle
    /// outward drift characteristic of the macOS Dock fan.
    let screenLongestDimension: CGFloat
    /// How far below the icon-resting baseline the fan view extends
    /// so it overlaps the dock chrome and the tile itself. Items
    /// animate *from* the bottom of this extended area (over the
    /// tile center) up onto the curve, instead of starting from
    /// their final position above the chrome.
    let chromeReach: CGFloat
    /// Drives the open/close animation. The presenter sets
    /// `isExpanded = true` once the window is on screen and
    /// `isExpanded = false` when dismissing — the reverse animation
    /// plays out before the window is finally ordered out.
    @ObservedObject var model: FanAnimationModel
    let onSelect: (URL) -> Void

    // Along-arc spacing per item. Bumped 25% over the original 12 pt
    // for a touch more breathing room. The clamp bounds in
    // `deltaTheta` are bumped in lockstep so the per-item visual
    // spacing actually reflects the increase instead of being held
    // back by the floor. Shared with the static `contentSize` path
    // via `Self.perItemArcLength`.
    private var perItemArcLength: CGFloat { Self.perItemArcLength }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, url in
                fanItem(url: url, index: index, total: items.count)
            }
        }
        .frame(width: viewWidth, height: viewHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func fanItem(url: URL, index: Int, total: Int) -> some View {
        let t = total <= 1 ? 0 : CGFloat(index) / CGFloat(total - 1)
        // θ runs from π (item 0 at x=0, y=0) backward by `deltaTheta`
        // radians (the angular span needed to cover the total arc
        // length at our radius). Circle center is at (radius, 0) so
        // cos(π) = -1 yields x=0 for item 0; subsequent items move
        // right and up as θ decreases.
        let theta = .pi - deltaTheta * t
        let curveX = radius * (1 + cos(theta))
        let curveY = radius * sin(theta)
        // Pre-compute the heavy sums so the SwiftUI builder doesn't
        // blow up the type-checker on the modifiers below.
        let hstackWidth = Self.labelMaxWidth + Self.labelIconGap + iconSize
        let positionX = Self.anchorIconOffsetX(iconSize: iconSize)
            + curveX
            - (Self.labelMaxWidth + Self.labelIconGap) / 2
        let positionY = anchorIconCenterY - curveY
        let initialOffsetY = curveY
            + Self.bottomPadding
            + chromeReach
            + stackPreviewOffsetY(for: index, total: total)

        Button(action: { onSelect(url) }) {
            HStack(alignment: .center, spacing: Self.labelIconGap) {
                Text(displayName(for: url))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    // Use the same Liquid-Glass / SkyLight-fallback
                    // chrome the rest of Docky uses for tile glass
                    // surfaces. Falls back automatically when glass
                    // is unavailable so the chip stays readable.
                    .background(.thickMaterial)
                    .clipShape(.capsule)
                    .dockyGlassBorder(in: Capsule())
                    .frame(maxWidth: Self.labelMaxWidth, alignment: .trailing)
                    // Chip fades in alongside the position slide and
                    // reaches full opacity exactly when the icon
                    // arrives on the curve — sharing the same
                    // animation modifier below.
                    .opacity(model.isExpanded ? 1 : 0)

                // Use the same `previewIcon` path the grid popover
                // and folder stack thumbnails go through — that's
                // the one that returns a QuickLook content preview
                // for documents/images and falls back to the system
                // icon for everything else.
                Image(nsImage: IconCacheService.shared.previewIcon(forFileURL: url))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    // Shadow only renders in the expanded state. At
                    // rest the icons mimic `FolderTileView.stack`'s
                    // shadowless pile so the fan's collapsed pile
                    // is visually identical to the tile preview
                    // underneath. Animates with the rest of the
                    // open / close transition.
                    .shadow(
                        color: .black.opacity(model.isExpanded ? 0.35 : 0),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
                    // Match `FolderTileView.stack(in:)`'s depth-based
                    // opacity ramp on the visible preview slots, so
                    // the at-rest pile reads exactly like the tile
                    // preview the user clicked. Items past the
                    // preview window are invisible at rest and fade
                    // in during the open animation.
                    .opacity(iconOpacity(forIndex: index))
            }
            .frame(width: hstackWidth, alignment: .trailing)
        }
        .buttonStyle(.plain)
        // `.position(x:y:)` places the HStack *center* at the given
        // point. We want the *icon* center (right end of the HStack)
        // on the curve, so `positionX` is shifted left by half the
        // (label + gap) span to compensate.
        .position(x: positionX, y: positionY)
        // Until the view appears, every item is offset to the same
        // spot — icon bottom flush with the view's bottom edge,
        // which sits over the tile (inside the chrome). The Y term
        // is `curveY + bottomPadding + chromeReach` so each item's
        // resting position (offset 0) and starting position differ
        // by exactly the curve travel + the chrome overlap. Adding
        // an extra `iconSize/2` here would push the icon below the
        // view's frame and the hosting view would clip the bottom
        // half during the first frame of animation.
        // Tangent-matched clockwise rotation: each item leans into
        // the curve by the angular distance it has travelled from
        // item 0 along the ellipse. At rest on the tile (collapsed)
        // everything is upright; as items slide out to their final
        // spot, they rotate to match the curve's local tangent.
        .rotationEffect(.radians(model.isExpanded ? deltaTheta * t : 0))
        // `initialOffsetY` collapses each item back onto the tile,
        // with the 3-item stack offset matching `FolderTileView`'s
        // preview so there's no jump at the start or end of the
        // animation.
        .offset(
            x: model.isExpanded ? 0 : -curveX,
            y: model.isExpanded ? 0 : initialOffsetY
        )
        // Snappy: 0.25s spring, 20 ms stagger. Last of 10 items
        // finishes at 0.02*9 + 0.25 ≈ 0.43s. Same modifier drives
        // both the position slide and the chip's opacity, so the
        // label reaches full opacity exactly when the icon arrives
        // on the curve.
        .animation(
            .spring(response: 0.25, dampingFraction: 0.82)
                .delay(Double(index) * 0.02),
            value: model.isExpanded
        )
        // Bottom-landing items (low `index`) paint *on top* of the
        // initial collapsed pile, top-landing items (high `index`)
        // sit at the back. In the expanded state the cells are at
        // distinct curve points so they don't overlap and zIndex is
        // visually inert.
        .zIndex(-Double(index))
    }

    // MARK: Curve

    private var radius: CGFloat { screenLongestDimension }

    private var deltaTheta: CGFloat {
        // Clamp the angular span to [scaledMin, 20°]. The upper
        // bound keeps the fan from opening into a wide wedge (macOS
        // Dock fan is a near-vertical column with gentle outward
        // drift, not a sector). The lower bound scales linearly
        // with item count so 10 items hit a 10° floor while a
        // 2-item fan only needs ~1° of curve — preventing the min
        // clamp from spreading sparse fans halfway across the
        // screen.
        guard items.count > 1, radius > 0 else { return 0 }
        let absoluteMaxSpan = CGFloat.pi * 25 / 180
        let maxScaledMinSpan = CGFloat.pi * 12.5 / 180
        let progress = CGFloat(items.count - 1) / CGFloat(Self.maximumItemCount - 1)
        let scaledMinSpan = maxScaledMinSpan * progress
        let natural = CGFloat(items.count - 1) * perItemArcLength / radius
        return min(absoluteMaxSpan, max(scaledMinSpan, natural))
    }

    private var maxCurveX: CGFloat { radius * (1 - cos(deltaTheta)) }
    private var maxCurveY: CGFloat { radius * sin(deltaTheta) }

    // MARK: Frame

    private var viewWidth: CGFloat {
        // `rotationOvershootX` reserves room on the right for the
        // top-of-curve item's `.rotationEffect`. Without it the
        // rotated bounding box extends past the view's frame and
        // the hosting NSWindow clips the icon.
        Self.labelMaxWidth + Self.labelIconGap + iconSize + maxCurveX + rotationOvershootX
    }

    private var viewHeight: CGFloat {
        // `chromeReach` is the extra height below item 0's icon
        // that the view occupies so animations can start over the
        // tile. The icon baseline stays at the same screen position
        // because the presenter shifts the window down by exactly
        // `chromeReach`. `rotationOvershootY` adds matching headroom
        // *above* the topmost icon so rotation doesn't clip the top
        // of the bounding box either.
        iconSize + maxCurveY + Self.bottomPadding + chromeReach + rotationOvershootY
    }

    private var anchorIconCenterY: CGFloat {
        // The rotation overshoot grows `viewHeight` at the *top*
        // (smaller y in SwiftUI top-down). The icon's resting
        // position is measured up from the view's bottom, so it
        // stays anchored to the same screen Y regardless of how
        // much overshoot we add — meaning the collapsed pile lands
        // exactly at the tile center the presenter aimed for, and
        // the extra space sits above the topmost icon as headroom
        // for rotated rendering.
        viewHeight - Self.bottomPadding - chromeReach - iconSize / 2
    }

    /// Additional safety margin past the precise rotation-overshoot
    /// math, in points. Covers shadows on the icon, the capsule
    /// stroke on the label chip, and any sub-pixel rounding in the
    /// rotation transform.
    private static let rotationOvershootSafetyPad: CGFloat = 12

    /// Half of the bounding-box width growth for a rectangle of
    /// size (hstackWidth × iconSize) rotated by the maximum angle
    /// any item reaches (`deltaTheta`, only the top-most item).
    /// Total bbox growth on the rotated axis is `w*cos+h*sin - w`;
    /// the rotated content extends by half that on each side, plus
    /// a safety pad for shadows / strokes.
    private var rotationOvershootX: CGFloat {
        let w = Self.labelMaxWidth + Self.labelIconGap + iconSize
        let h = iconSize
        let theta = deltaTheta
        let math = max(0, (w * cos(theta) + h * sin(theta) - w) / 2)
        return math + Self.rotationOvershootSafetyPad
    }

    /// Vertical mirror of `rotationOvershootX`. Wide rectangles get
    /// much larger vertical overshoot than horizontal because the
    /// long edge sweeps top/bottom.
    private var rotationOvershootY: CGFloat {
        let w = Self.labelMaxWidth + Self.labelIconGap + iconSize
        let h = iconSize
        let theta = deltaTheta
        let math = max(0, (w * sin(theta) + h * cos(theta) - h) / 2)
        return math + Self.rotationOvershootSafetyPad
    }

    private func displayName(for url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
    }

    /// Y offset for the fan's collapsed-onto-tile state. Matches the
    /// real-world "pile of papers" model: the top sheet (z-top) is
    /// the *lowest* one (closest to you); the sheets behind peek
    /// out slightly higher. So the bottom-landing item (newest,
    /// z-top) gets +4 and the top-landing items (older, z-back) get
    /// −4 — same mapping as `FolderTileView.stack(in:)`'s preview
    /// pile, which is what the fan emerges from / collapses back
    /// into.
    ///
    /// Mapping by index from the front of the list: index 0 → +4,
    /// index 1 → 0, index 2+ → −4 (clamped, since the tile preview
    /// only spans 3 slots anyway).
    /// Per-item icon opacity. In the expanded state every visible
    /// item is fully opaque. In the collapsed state the first three
    /// slots mirror `FolderTileView.stack(in:)`'s depth-based ramp
    /// (1.0 / 0.88 / 0.76) so the at-rest pile is indistinguishable
    /// from the tile preview underneath; items beyond the preview
    /// window are invisible.
    private func iconOpacity(forIndex index: Int) -> Double {
        if model.isExpanded {
            return 1.0
        }
        guard index < Self.previewSlotCount else { return 0 }
        let depthOpacityStep: Double = 0.12 // matches FolderTileView.stack
        return 1.0 - Double(index) * depthOpacityStep
    }

    private func stackPreviewOffsetY(for index: Int, total: Int) -> CGFloat {
        let tileStackVerticalStep: CGFloat = 4
        let cappedIndex = min(index, Self.previewSlotCount - 1)
        let centeredBaseOffset = CGFloat(Self.previewSlotCount - 1) / 2
        return (centeredBaseOffset - CGFloat(cappedIndex)) * tileStackVerticalStep
    }
}

struct FolderFanPresenter: NSViewRepresentable {
    let folderURL: URL
    let items: [URL]
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeNSView(context: Context) -> NSView {
        // Zero-size anchor: SwiftUI ignores layout impact, but the view
        // still has a window+frame we can convert to screen coords.
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            folderURL: folderURL,
            items: items,
            isPresented: $isPresented
        )

        if isPresented {
            DispatchQueue.main.async {
                context.coordinator.present(relativeTo: nsView)
            }
        } else {
            context.coordinator.dismiss()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        // The SwiftUI tree is going away — skip the close animation
        // and rip the window down immediately so we never orphan it.
        coordinator.tearDown()
    }

    final class Coordinator: NSObject {
        // Match the spring response + per-item stagger in
        // `FolderFanView.fanItem(...)` so the close animation
        // finishes right before the window is ordered out. Springs
        // overshoot/settle past `response`, so add a small safety
        // pad to make sure the last item is visually at rest before
        // we tear the window down.
        private static let animationDuration: TimeInterval = 0.25
        private static let perItemStagger: TimeInterval = 0.02
        private static let settleSafetyPad: TimeInterval = 0.05

        private var folderURL: URL = URL(fileURLWithPath: "/")
        private var items: [URL] = []
        var isPresented: Binding<Bool>
        private weak var window: NSWindow?
        // Weak reference to the dock window so we can pair
        // `beginInteraction()` (in `present`) with `endInteraction()`
        // (in `tearDown`) and keep auto-hide deferred while the fan
        // is on screen — same behavior as the grid popover and the
        // folder list menu.
        private weak var dockMainWindow: MainWindow?
        private var isHoldingDockVisible = false
        private var animationModel: FanAnimationModel?
        private var isClosing = false
        private var closeWorkItem: DispatchWorkItem?
        private var globalMonitor: Any?
        private var localMonitor: Any?
        private var keyMonitor: Any?

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        func update(folderURL: URL, items: [URL], isPresented: Binding<Bool>) {
            self.folderURL = folderURL
            self.items = items
            self.isPresented = isPresented
        }

        func present(relativeTo anchor: NSView) {
            guard window == nil, let anchorWindow = anchor.window else { return }

            // Tell the dock to defer auto-hide while the fan is on
            // screen. Paired with the `endInteraction()` call in
            // `tearDown`. Without this, dragging the cursor off the
            // tile (to click an item in the fan) lets the dock
            // start its auto-hide animation underneath, which both
            // looks wrong and breaks the click-through to the tile.
            if let dockWindow = anchorWindow as? MainWindow, !isHoldingDockVisible {
                dockWindow.beginInteraction()
                dockMainWindow = dockWindow
                isHoldingDockVisible = true
            }

            let anchorBoundsInWindow = anchor.convert(anchor.bounds, to: nil)
            let anchorFrameInScreen = anchorWindow.convertToScreen(anchorBoundsInWindow)

            // Use the screen the anchor window sits on so a multi-
            // display setup picks up each screen's own longest side.
            let screenFrame = anchorWindow.screen?.frame ?? NSScreen.main?.frame ?? .zero
            let longest = max(screenFrame.width, screenFrame.height)

            // Match the icon side that `FolderTileView.stack(in:)`
            // renders inside the tile (0.82 × the tile's shorter
            // side), so fan icons are the same visual size as the
            // tile preview icons the user just clicked.
            let tileSide = min(anchorFrameInScreen.width, anchorFrameInScreen.height)
            let iconSize = tileSide * 0.82

            // Pick `chromeReach` so the initial icon center lands on
            // the tile's *center*, not above the tile. Derivation:
            //   • view bottom in screen Y = window.originY
            //   • initial icon center in screen Y = window.originY + iconSize/2
            //     (icon bottom is flush with the view bottom)
            //   • window.originY = tile.maxY + 8 - bottomPadding - chromeReach
            // Solving `tile.midY = window.originY + iconSize/2`:
            //   chromeReach = tile.height/2 + 8 + iconSize/2 - bottomPadding
            let chromeReach = anchorFrameInScreen.height / 2
                + 8
                + iconSize / 2
                - FolderFanView.bottomPadding

            let model = FanAnimationModel()
            self.animationModel = model
            self.isClosing = false

            let rootView = FolderFanView(
                folderURL: folderURL,
                items: items,
                iconSize: iconSize,
                screenLongestDimension: longest,
                chromeReach: chromeReach,
                model: model,
                onSelect: { [weak self] url in
                    NSWorkspace.shared.open(url)
                    self?.dismiss()
                }
            )

            // Compute the window size deterministically. We can't
            // rely on `NSHostingView.fittingSize` here — it sometimes
            // compresses the SwiftUI view's explicit `.frame(...)`
            // away when called before the host is laid out into a
            // real window, leaving rotated icons clipped on the right.
            let size = FolderFanView.contentSize(
                iconSize: iconSize,
                chromeReach: chromeReach,
                itemCount: items.count,
                screenLongestDimension: longest
            )
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.frame = NSRect(origin: .zero, size: size)
            // Belt-and-suspenders: disable layer clipping so any
            // residual overshoot (shadows, capsule strokes) past the
            // computed bounds still renders.
            hostingView.wantsLayer = true
            hostingView.layer?.masksToBounds = false

            let newWindow = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.backgroundColor = .clear
            newWindow.isOpaque = false
            newWindow.hasShadow = false
            newWindow.level = .mainMenu
            // The fan should never steal focus from whatever the user
            // is currently doing — same behavior as the main dock panel.
            newWindow.hidesOnDeactivate = false
            newWindow.contentView = hostingView

            // Anchor item 0's *icon center* (which sits at
            // `anchorIconOffsetX` from the view's leading edge once
            // the label chip is laid out on the left) directly above
            // the tile's horizontal center, with a small gap above
            // the tile top. The label trail extends further left of
            // the tile; the curve sweeps off to the right. The
            // window is shifted down by `chromeReach` so the extra
            // bottom area overlaps the tile — that's where the items
            // start their slide-out animation from.
            let originX = anchorFrameInScreen.midX - FolderFanView.anchorIconOffsetX(iconSize: iconSize)
            let originY = anchorFrameInScreen.maxY + 8 - FolderFanView.bottomPadding - chromeReach
            newWindow.setFrameOrigin(NSPoint(x: originX, y: originY))
            newWindow.orderFrontRegardless()

            window = newWindow
            installDismissMonitors()

            // Toggle on the next runloop tick so SwiftUI renders the
            // initial (collapsed-onto-tile) state once before the
            // expand animation kicks in. Without the async hop the
            // view would skip the starting frame and snap to its
            // final positions.
            DispatchQueue.main.async {
                model.isExpanded = true
            }
        }

        /// Start the reverse animation; the window is ordered out
        /// only after the per-item slide-back finishes. Idempotent
        /// — repeated calls while closing are no-ops.
        func dismiss() {
            guard window != nil, !isClosing else { return }

            // If we never expanded (e.g. dismiss arrived before the
            // initial async hop) just close immediately — there's
            // nothing to animate back from.
            guard let model = animationModel, model.isExpanded else {
                tearDown()
                return
            }

            isClosing = true
            removeDismissMonitors()

            // Pass clicks through during the close animation so the
            // user isn't blocked from interacting with the dock or
            // other apps while items slide back onto the tile.
            window?.ignoresMouseEvents = true

            model.isExpanded = false

            let totalDuration = Self.animationDuration
                + Double(max(0, items.count - 1)) * Self.perItemStagger
                + Self.settleSafetyPad
            let workItem = DispatchWorkItem { [weak self] in
                self?.tearDown()
            }
            closeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration, execute: workItem)
        }

        /// Immediately tear the window down without animation. Used
        /// on `dismantleNSView` (SwiftUI tree going away) and as the
        /// final step of `dismiss()` after the reverse animation.
        func tearDown() {
            closeWorkItem?.cancel()
            closeWorkItem = nil
            animationModel = nil
            removeDismissMonitors()

            if let w = window {
                w.orderOut(nil)
                window = nil
            }

            // Release the dock auto-hide hold acquired in `present`.
            if isHoldingDockVisible {
                dockMainWindow?.endInteraction()
                dockMainWindow = nil
                isHoldingDockVisible = false
            }

            isClosing = false

            if isPresented.wrappedValue {
                DispatchQueue.main.async { [isPresented] in
                    isPresented.wrappedValue = false
                }
            }
        }

        private func installDismissMonitors() {
            // Global: clicks anywhere outside the app.
            globalMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                self?.dismiss()
            }
            // Local: clicks inside the app but not on the fan window.
            // Returning `event` lets the click reach its real target
            // (e.g. another tile) — same feel as NSPopover.transient.
            localMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                guard let self else { return event }
                if event.window !== self.window {
                    self.dismiss()
                }
                return event
            }
            // Escape always dismisses.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                if event.keyCode == 53 { // Escape
                    self?.dismiss()
                    return nil
                }
                return event
            }
        }

        private func removeDismissMonitors() {
            if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
            if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
            if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
        }
    }
}
