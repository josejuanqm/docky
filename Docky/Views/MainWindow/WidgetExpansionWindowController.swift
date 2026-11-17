//
//  WidgetExpansionWindowController.swift
//  Docky
//

import AppKit
import Combine
import SwiftUI

final class WidgetExpansionWindowController: NSWindowController, ObservableObject {
    static let shared = WidgetExpansionWindowController()

    @Published private(set) var activeSourceTileID: String?

    private static let contentPadding: CGFloat = 8
    private static let animationDuration: TimeInterval = 0.18
    private static let slideOffset: CGFloat = 12
    private static let minimumExpansionBaseTileSize: CGFloat = 80

    private var currentTileID: String?
    private var isPreviewHovered = false
    private var isHoldingDockVisible = false
    private weak var heldMainWindow: MainWindow?
    private var pendingDismissTask: Task<Void, Never>?
    private var dismissAnimationTask: Task<Void, Never>?
    /// Reused across presentations: a new NSHostingView per hover rebuilt
    /// the whole expanded widget's view tree on the main thread (~90 ms
    /// for a widget with a scroller of cards) before the window could show.
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    private init() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .mainMenu
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.contentView = hostingView
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(
        widget: WidgetTile,
        sourceTileID: String,
        sourceFrame: CGRect,
        cornerRadius: CGFloat,
        renderedSpan: TileSpan
    ) {
        guard let window else { return }

        currentTileID = sourceTileID
        activeSourceTileID = sourceTileID
        pendingDismissTask?.cancel()
        pendingDismissTask = nil
        dismissAnimationTask?.cancel()
        dismissAnimationTask = nil
        beginDockVisibilityHoldIfNeeded()

        let resolvedTileSize = max(1, min(
            sourceFrame.height,
            sourceFrame.width / CGFloat(max(renderedSpan.rawValue, 1))
        ))
        let baseTileSize = max(Self.minimumExpansionBaseTileSize, resolvedTileSize)
        let extent = widget.kind.expansionExtent
        let size = CGSize(
            width: baseTileSize * CGFloat(extent.widthTiles),
            height: baseTileSize * CGFloat(extent.heightTiles)
        )
        let windowSize = CGSize(
            width: size.width + Self.contentPadding * 2,
            height: size.height + Self.contentPadding * 2
        )

        // Widget views pick their layout variant (1-up / 2-up / 3-up)
        // off `renderedSpan`, so a 1x1 tile's expanded preview was
        // drawing 1-up content inside a 3x3 window. Map the expansion
        // extent's tile width to the equivalent TileSpan instead, clamped
        // to `.four` (the highest case) for the 5-wide nowPlaying preview.
        let expandedRenderedSpan = TileSpan(
            rawValue: min(max(extent.widthTiles, 1), TileSpan.four.rawValue)
        ) ?? .four

        let rootView = ZStack {
            Color.clear

            WidgetTileView(
                tile: widget,
                cornerRadius: cornerRadius,
                renderedSpan: expandedRenderedSpan,
                isWithinStack: false,
                isExpanded: true,
                isExpandedPreviewOpen: true
            )
            .frame(width: size.width, height: size.height)
            .padding(Self.contentPadding)
        }
        .frame(width: windowSize.width, height: windowSize.height)
        .contentShape(Rectangle())
        .onHover { isHovering in
            WidgetExpansionWindowController.shared.setPreviewHovered(isHovering, sourceTileID: sourceTileID)
        }

        let finalOrigin = frameOrigin(for: windowSize, sourceFrame: sourceFrame)
        let slide = slideOffsetVector()
        let initialOrigin = CGPoint(x: finalOrigin.x + slide.x, y: finalOrigin.y + slide.y)
        let finalFrame = CGRect(origin: finalOrigin, size: windowSize)
        let initialFrame = CGRect(origin: initialOrigin, size: windowSize)

        hostingView.rootView = AnyView(rootView)
        window.setFrame(initialFrame, display: false)
        window.alphaValue = 0
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(finalFrame, display: true)
            window.animator().alphaValue = 1
        }
    }

    func dismiss(sourceTileID: String) {
        guard currentTileID == sourceTileID else { return }
        pendingDismissTask?.cancel()
        pendingDismissTask = nil
        isPreviewHovered = false
        endDockVisibilityHoldIfNeeded()
        currentTileID = nil
        activeSourceTileID = nil

        guard let window, window.isVisible else {
            close()
            return
        }

        let currentFrame = window.frame
        let slide = slideOffsetVector()
        let targetFrame = currentFrame.offsetBy(dx: slide.x, dy: slide.y)

        dismissAnimationTask?.cancel()
        dismissAnimationTask = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = Self.animationDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    window.animator().setFrame(targetFrame, display: true)
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    continuation.resume()
                })
            }
            if Task.isCancelled { return }
            guard self.currentTileID == nil else { return }
            self.close()
        }
    }

    func requestDismiss(sourceTileID: String) {
        guard currentTileID == sourceTileID else { return }
        guard !isPreviewHovered else { return }

        pendingDismissTask?.cancel()
        pendingDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            guard self.currentTileID == sourceTileID, !self.isPreviewHovered else { return }
            self.dismiss(sourceTileID: sourceTileID)
        }
    }

    private func setPreviewHovered(_ isHovered: Bool, sourceTileID: String) {
        guard currentTileID == sourceTileID else { return }
        isPreviewHovered = isHovered

        if isHovered {
            pendingDismissTask?.cancel()
            pendingDismissTask = nil
        } else {
            requestDismiss(sourceTileID: sourceTileID)
        }
    }

    private func beginDockVisibilityHoldIfNeeded() {
        guard !isHoldingDockVisible else { return }
        guard let mainWindow = NSApp.windows.compactMap({ $0 as? MainWindow }).first else { return }

        mainWindow.beginInteraction()
        heldMainWindow = mainWindow
        isHoldingDockVisible = true
    }

    private func endDockVisibilityHoldIfNeeded() {
        guard isHoldingDockVisible else { return }

        heldMainWindow?.endInteraction()
        heldMainWindow = nil
        isHoldingDockVisible = false
    }

    private func frameOrigin(for size: CGSize, sourceFrame originalSourceFrame: CGRect) -> CGPoint {
        let sourceFrame = convertToScreen(originalSourceFrame)
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(sourceFrame) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return CGPoint(x: sourceFrame.midX - size.width / 2, y: sourceFrame.maxY)
        }

        switch dockEdge {
        case .maxY:
            let proposedY = sourceFrame.maxY
            let y = proposedY + size.height <= visibleFrame.maxY
                ? proposedY
                : max(visibleFrame.minY, sourceFrame.minY - size.height)
            let x = clamp(sourceFrame.midX - size.width / 2, lower: visibleFrame.minX, upper: visibleFrame.maxX - size.width)
            return CGPoint(x: x, y: y)
        case .minY:
            let proposedY = sourceFrame.minY - size.height
            let y = proposedY >= visibleFrame.minY ? proposedY : sourceFrame.maxY
            let x = clamp(sourceFrame.midX - size.width / 2, lower: visibleFrame.minX, upper: visibleFrame.maxX - size.width)
            return CGPoint(x: x, y: y)
        case .maxX:
            let proposedX = sourceFrame.maxX
            let x = proposedX + size.width <= visibleFrame.maxX
                ? proposedX
                : max(visibleFrame.minX, sourceFrame.minX - size.width)
            let y = clamp(sourceFrame.midY - size.height / 2, lower: visibleFrame.minY, upper: visibleFrame.maxY - size.height)
            return CGPoint(x: x, y: y)
        case .minX:
            let proposedX = sourceFrame.minX - size.width
            let x = proposedX >= visibleFrame.minX ? proposedX : sourceFrame.maxX
            let y = clamp(sourceFrame.midY - size.height / 2, lower: visibleFrame.minY, upper: visibleFrame.maxY - size.height)
            return CGPoint(x: x, y: y)
        @unknown default:
            return CGPoint(x: sourceFrame.midX - size.width / 2, y: sourceFrame.maxY)
        }
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    private func convertToScreen(_ frame: CGRect) -> CGRect {
        guard let dockFrame = NSApp.windows.compactMap({ $0 as? MainWindow }).first?.frame else {
            return frame
        }
        return CGRect(
            x: dockFrame.minX + frame.minX,
            y: dockFrame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private var dockEdge: NSRectEdge {
        let prefs = DockyPreferences.shared
        let settings = DockSettingsService.shared
        switch prefs.windowPosition.resolved(systemOrientation: settings.orientation) {
        case .top: return .minY
        case .bottom: return .maxY
        case .left: return .maxX
        case .right: return .minX
        }
    }

    private func slideOffsetVector() -> CGPoint {
        switch dockEdge {
        case .maxY: return CGPoint(x: 0, y: -Self.slideOffset)
        case .minY: return CGPoint(x: 0, y: Self.slideOffset)
        case .maxX: return CGPoint(x: -Self.slideOffset, y: 0)
        case .minX: return CGPoint(x: Self.slideOffset, y: 0)
        @unknown default: return CGPoint(x: 0, y: -Self.slideOffset)
        }
    }
}
