//
//  MainWindowView.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    private let borderWidth: CGFloat = 1
    private let chromeResizeAnimation: Animation = .easeInOut(duration: 0.18)

    @ObservedObject private var dockSettings = DockSettingsService.shared
    @Bindable private var preferences = DockyPreferences.shared
    @ObservedObject private var layoutService = DockLayoutService.shared
    @ObservedObject private var magnification = DockMagnificationService.shared
    @ObservedObject private var chromeMetrics = DockChromeMetricsService.shared

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        let cornerRadius = effectiveCornerRadius
        let chromeFrameSize = resolvedChromeFrameSize
        let dockEdge = dockEdgeAlignment

        ZStack(alignment: dockEdge) {
            chromeBackground(cornerRadius: cornerRadius)
                .frame(width: chromeFrameSize?.width, height: chromeFrameSize?.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dockEdge)
                .allowsHitTesting(true)
                // Suppress the implicit easeInOut while magnification is
                // tracking the cursor — chrome growth updates per frame
                // and a 0.18s tween would visibly lag the pointer. Tile
                // add/remove and other resting layout changes still
                // animate normally.
                .animation(
                    isTrackingMagnification ? nil : chromeResizeAnimation,
                    value: chromeFrameSize
                )

            TileContainerView()
        }
        .compositingGroup()
    }

    private var isTrackingMagnification: Bool {
        dockSettings.magnification && magnification.pointerLocation != nil
    }

    private var dockEdgeAlignment: Alignment {
        switch preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation) {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    @ViewBuilder
    private func chromeBackground(cornerRadius: CGFloat) -> some View {
        backgroundFill(cornerRadius: cornerRadius)
            .background {
                if !preferences.effectiveDisablesGlassLook,
                   FeatureGate.shared.isAvailable(.liquidGlass),
                   #available(macOS 26.0, *) {
                    LiquidGlassChromeView(variant: 11, cornerRadius: cornerRadius)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                // Theme border, when set, takes precedence over the
                // default glass stroke. When no theme border is set
                // and glass isn't disabled, we draw the gradient
                // outline that lives with the dock chrome.
                if let themeBorder = preferences.effectiveWindowBorderColor {
                    let width = max(0, preferences.effectiveWindowBorderWidth)
                    if width > 0 {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .inset(by: width / 2)
                            .strokeBorder(Color(nsColor: themeBorder), lineWidth: width)
                    }
                } else if !preferences.effectiveDisablesGlassLook {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .inset(by: borderWidth / 2)
                        .strokeBorder(borderGradient, lineWidth: borderWidth)
                }
            }
    }

    @ViewBuilder
    private func backgroundFill(cornerRadius: CGFloat) -> some View {
        let resolvedPosition = preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
        let rotated = resolvedPosition.isVertical
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .background {
                if let backgroundImage = resolvedBackgroundImage {
                    GeometryReader { proxy in
                        backgroundImageContent(image: backgroundImage)
                            .frame(
                                width: rotated ? proxy.size.height : proxy.size.width,
                                height: rotated ? proxy.size.width : proxy.size.height
                            )
                            .rotationEffect(.degrees(backgroundImageRotationDegrees(for: resolvedPosition)))
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                } else {
                    Color(nsColor: preferences.effectiveWindowTintColor)
                        .opacity(preferences.effectiveWindowTintOpacity)
                }
            }
            .clipped()
    }

    @ViewBuilder
    private func backgroundImageContent(image: NSImage) -> some View {
        switch preferences.effectiveWindowBackgroundImageMode {
        case .fill:
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        case .sprite:
            let cap = max(1, min(image.size.width / 3, image.size.height))
            Image(nsImage: image)
                .resizable(
                    capInsets: EdgeInsets(top: 0, leading: cap, bottom: 0, trailing: cap),
                    resizingMode: .stretch
                )
        }
    }

    private func backgroundImageRotationDegrees(for position: ResolvedDockWindowPosition) -> Double {
        switch position {
        case .left: 90
        case .right: -90
        case .top, .bottom: 0
        }
    }

    private var borderGradient: LinearGradient { dockyGlassBorderGradient }

    private var effectiveCornerRadius: CGFloat {
        preferences.effectiveWindowClipShape.resolvedCornerRadius(
            base: preferences.effectiveWindowCornerRadius,
            maximum: maximumCornerRadius
        )
    }

    private var maximumCornerRadius: CGFloat {
        let iconHeight = layoutService.scaled(dockSettings.displayTileSize)
        return (iconHeight + layoutService.scaled(preferences.effectiveTileVerticalPadding) * 2) / 2
    }

    private var resolvedChromeFrameSize: CGSize? {
        let chromeSize = layoutService.chromeSize
        guard chromeSize.width > 0, chromeSize.height > 0 else {
            return nil
        }

        // Precise per-frame total growth published by `TileContainerView`
        // as a byproduct of the tile walk it does for the anchor offset.
        // This naturally handles edge truncation and non-1×1 widgets in
        // the influence radius — both of which reduce the effective
        // total below the closed-form constant.
        let usesFullAxis = preferences.windowAxisSizing == .fullAxis
        let chromeGrowth = chromeMetrics.alongAxisGrowth
        guard dockSettings.magnification, !usesFullAxis, chromeGrowth > 0 else {
            return chromeSize
        }

        let isVertical = preferences.windowPosition
            .resolved(systemOrientation: dockSettings.orientation)
            .isVertical
        if isVertical {
            return CGSize(width: chromeSize.width, height: chromeSize.height + chromeGrowth)
        }
        return CGSize(width: chromeSize.width + chromeGrowth, height: chromeSize.height)
    }

    private var resolvedBackgroundImage: NSImage? {
        guard let backgroundImageURL = preferences.effectiveWindowBackgroundImageURL else {
            return nil
        }

        return NSImage(contentsOf: backgroundImageURL)
    }
}

/// `NSGlassEffectView` SPI bridge — same surface
/// `electron-liquid-glass` uses (Meridius-Labs/electron-liquid-glass).
/// The class itself is private AppKit on macOS 26, so we load it by
/// name; if the runtime can't find it (older OS that somehow reaches
/// this code despite the availability gate, or a future rename), the
/// view degrades to a plain `NSView` and renders nothing.
///
/// Variants are set via the private `set_variant:` selector taking a
/// `long long`. There's no public Swift typed wrapper, so we look the
/// IMP up by name and call it through a `@convention(c)` cast — same
/// recipe Electron uses. Variant 11 is the configured chrome look.
@available(macOS 26.0, *)
struct LiquidGlassChromeView: NSViewRepresentable {
    var variant: Int
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view: NSView
        if let cls = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            view = cls.init(frame: .zero)
        } else {
            view = NSView(frame: .zero)
        }
        view.wantsLayer = true
        apply(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: NSView) {
        applyVariant(to: view)
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }

    private func applyVariant(to view: NSView) {
        // Try the private `set_variant:` first (what NSGlassEffectView
        // actually exposes), then a hypothetical public `setVariant:`.
        for name in ["set_variant:", "setVariant:"] {
            let sel = NSSelectorFromString(name)
            guard view.responds(to: sel),
                  let imp = view.method(for: sel) else { continue }
            typealias VariantSetter = @convention(c) (NSObject, Selector, Int64) -> Void
            let setter = unsafeBitCast(imp, to: VariantSetter.self)
            setter(view, sel, Int64(variant))
            return
        }
    }
}

/// Snapshot of a system drag image we temporarily hid so our own preview
/// can take over.
private struct HiddenDragImageSnapshot {
    let item: NSDraggingItem
    let originalProvider: (() -> [NSDraggingImageComponent])?
}

/// Concrete (non-generic) `NSHostingView` subclass for the dock chrome.
/// Used to be `ClickThroughHostingView<Content: View>`, but the only call
/// site instantiates it with `MainWindowView`, and the generic form
/// triggered a Swift 6.x `EarlyPerfInliner` crash at `-O` while
/// synthesizing the generic class's `deinit`. Concretizing the
/// `NSHostingView` specialization avoids that path entirely.
final class ClickThroughHostingView: NSHostingView<MainWindowView> {
    private var hiddenDragImageOriginals: [HiddenDragImageSnapshot] = []

    @MainActor required init(rootView: MainWindowView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL, .string])
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        registerForDraggedTypes([.fileURL, .string])
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        let urls = readURLs(from: sender)
        let pasteboardTypes = sender.draggingPasteboard.types?.map(\.rawValue) ?? []
        if let kind = DockDragService.resolvePreview(from: urls) {
            NSLog(
                "[Docky] drag entered: kind=%@ urls=%@ pasteboardTypes=%@",
                Self.describe(kind: kind),
                urls.map(\.path).joined(separator: ", "),
                pasteboardTypes.joined(separator: ", ")
            )
            DockDragService.shared.begin(kind: kind, at: location)
            updateSystemDragImageVisibility(in: sender)
            return .copy
        }
        if DockEditModeService.shared.paletteDrag != nil {
            NSLog(
                "[Docky] drag entered: kind=palette urls=%@ pasteboardTypes=%@",
                urls.map(\.path).joined(separator: ", "),
                pasteboardTypes.joined(separator: ", ")
            )
            DockDragService.shared.cursorLocation = location
            updateSystemDragImageVisibility(in: sender)
            return .copy
        }
        NSLog(
            "[Docky] drag entered: kind=rejected urls=%@ pasteboardTypes=%@",
            urls.map(\.path).joined(separator: ", "),
            pasteboardTypes.joined(separator: ", ")
        )
        return []
    }

    /// One-line description of a `DockDragService.Kind` for logging.
    private static func describe(kind: DockDragService.Kind) -> String {
        switch kind {
        case .app(let url, let tile):
            return "app(bundle=\(tile.bundleIdentifier), path=\(url.path))"
        case .folder(let url, _):
            return "folder(path=\(url.path))"
        case .document(let urls):
            return "document(paths=[\(urls.map(\.path).joined(separator: ", "))])"
        }
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        if DockDragService.shared.kind != nil {
            DockDragService.shared.updateCursor(location)
            updateSystemDragImageVisibility(in: sender)
            return .copy
        }
        if DockEditModeService.shared.paletteDrag != nil {
            DockDragService.shared.cursorLocation = location
            updateSystemDragImageVisibility(in: sender)
            return .copy
        }
        return []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        // Cursor left the dock window, but the drag may still be live — the
        // user might be moving into a spring-loaded popover. Drop the
        // location-derived state so previews disappear, but keep `kind`
        // alive so popover-side drop handlers can resolve the source. The
        // drag service is fully cleared in `draggingEnded(_:)` once AppKit
        // tells us the drag is truly over.
        DockDragService.shared.cursorLocation = nil
        DockDragService.shared.destinationIndex = nil
        DockDragService.shared.destinationSection = nil
        DockDragService.shared.documentTargetTileID = nil
        // Keep paletteDrag alive so re-entry works — the SwiftUI .onDrag-initiated
        // drag is still in flight outside the window, and the palette item can't be
        // recovered from the pasteboard (which only carries the variant ID).
        DockEditModeService.shared.paletteDropDestination = nil
        restoreSystemDragImage()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        DockDragService.shared.clear()
    }

    /// Hide the system drag preview when our own insertion preview is active, so the
    /// user sees one drop indication instead of two competing ones. Restore originals
    /// when the active region is exited so the preview returns outside the dock.
    /// Drag-onto-tile (open-with) intentionally keeps the system preview because
    /// there's no insertion indicator competing for attention.
    private func updateSystemDragImageVisibility(in sender: any NSDraggingInfo) {
        let shouldHide =
            DockDragService.shared.destinationIndex != nil
            || DockEditModeService.shared.paletteDropDestination != nil
        if shouldHide {
            guard hiddenDragImageOriginals.isEmpty else { return }
            sender.enumerateDraggingItems(
                options: [],
                for: self,
                classes: [NSPasteboardItem.self],
                searchOptions: [:]
            ) { item, _, _ in
                self.hiddenDragImageOriginals.append(
                    HiddenDragImageSnapshot(item: item, originalProvider: item.imageComponentsProvider)
                )
                item.imageComponentsProvider = { [] }
            }
        } else {
            restoreSystemDragImage()
        }
    }

    private func restoreSystemDragImage() {
        for snapshot in hiddenDragImageOriginals {
            snapshot.item.imageComponentsProvider = snapshot.originalProvider
        }
        hiddenDragImageOriginals.removeAll()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { restoreSystemDragImage() }
        if let kind = DockDragService.shared.kind {
            let destinationIndex = DockDragService.shared.destinationIndex
            let targetTileID = DockDragService.shared.documentTargetTileID
            NSLog(
                "[Docky] drag drop: kind=%@ destinationIndex=%@ documentTargetTileID=%@",
                Self.describe(kind: kind),
                destinationIndex.map(String.init) ?? "nil",
                targetTileID ?? "nil"
            )
            defer { DockDragService.shared.clear() }
            switch kind {
            case .app(_, let tile):
                guard let index = destinationIndex else { return false }
                return TileStore.shared.pinApp(bundleIdentifier: tile.bundleIdentifier, at: index)
            case .folder(let url, let tile):
                if let targetTileID,
                   let bundleIdentifier = TileStore.shared.tiles
                    .first(where: { $0.id == targetTileID })
                    .flatMap({ tile -> String? in
                        if case .app(let app) = tile.content { return app.bundleIdentifier }
                        return nil
                    }) {
                    WorkspaceService.shared.open(fileURLs: [url], withApplicationBundleIdentifier: bundleIdentifier)
                    return true
                }
                guard let index = destinationIndex else { return false }
                TileStore.shared.insertTrailingItem(
                    .folder(url: url, displayName: tile.displayName),
                    at: index
                )
                return true
            case .document(let urls):
                guard let targetTileID,
                      let bundleIdentifier = TileStore.shared.tiles
                        .first(where: { $0.id == targetTileID })
                        .flatMap({ tile -> String? in
                            if case .app(let app) = tile.content { return app.bundleIdentifier }
                            return nil
                        }) else {
                    return false
                }
                WorkspaceService.shared.open(fileURLs: urls, withApplicationBundleIdentifier: bundleIdentifier)
                return true
            }
        }
        if let paletteDrag = DockEditModeService.shared.paletteDrag,
           let destination = DockEditModeService.shared.paletteDropDestination {
            defer {
                DockEditModeService.shared.endPaletteDrag()
                DockDragService.shared.cursorLocation = nil
            }
            switch destination.section {
            case .pinned:
                guard let item = TileContainerView.makePinnedItem(from: paletteDrag) else { return false }
                TileStore.shared.insertPinnedItem(item, at: destination.index)
                return true
            case .trailing:
                guard let item = TileContainerView.makeTrailingItem(from: paletteDrag) else { return false }
                TileStore.shared.insertTrailingItem(item, at: destination.index)
                return true
            }
        }
        return false
    }

    private func readURLs(from sender: any NSDraggingInfo) -> [URL] {
        let pasteboard = sender.draggingPasteboard
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
    }
}
