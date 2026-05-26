//
//  WindowPreviewWindowController.swift
//  Docky
//
//  Hover-driven per-tile counterpart to WindowSwitcherOverlayWindowController.
//  Mirrors WidgetExpansionWindowController's mechanics: a singleton custom
//  borderless NSWindow at .mainMenu level that slide+fades into place over
//  the source tile's frame. The SwiftUI content (thumbnails or list) is the
//  same as the global switcher's so the two presentations stay coherent
//  without coupling their state.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class WindowPreviewWindowController: NSWindowController, ObservableObject {
    static let shared = WindowPreviewWindowController()

    @Published private(set) var activeSourceTileID: String?

    fileprivate static let contentPadding: CGFloat = 6
    private static let animationDuration: TimeInterval = 0.18
    private static let slideOffset: CGFloat = 12
    private static let dismissGrace: Duration = .milliseconds(120)

    private var currentTileID: String?
    private var currentBundleIdentifier: String?
    private var isPreviewHovered = false
    private var isHoldingDockVisible = false
    private weak var heldMainWindow: MainWindow?
    private var pendingDismissTask: Task<Void, Never>?
    private var dismissAnimationTask: Task<Void, Never>?

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
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Presents the preview anchored next to `sourceFrame` on the inward
    /// side of the dock. Returns false when the bundle has no windows so
    /// callers can keep the tooltip up in that case.
    @discardableResult
    func present(
        forBundleIdentifier bundleID: String,
        sourceTileID: String,
        sourceFrame: CGRect,
        preferredEdge: NSRectEdge
    ) -> Bool {
        present(
            forBundleIdentifiers: [bundleID],
            sourceTileID: sourceTileID,
            sourceFrame: sourceFrame,
            preferredEdge: preferredEdge
        )
    }

    /// Multi-bundle variant used by app-folder tiles. Aggregates windows
    /// from every contained app into a single preview.
    @discardableResult
    func present(
        forBundleIdentifiers bundleIDs: [String],
        sourceTileID: String,
        sourceFrame: CGRect,
        preferredEdge: NSRectEdge
    ) -> Bool {
        guard let window else { return false }

        let didLoad = WindowPreviewService.shared.present(
            forBundleIdentifiers: bundleIDs,
            sourceTileID: sourceTileID
        )
        guard didLoad else { return false }

        // Already showing for this tile — keep it, just refresh the frame in
        // case the dock layout shifted (magnification, edit mode exit, etc.).
        if currentTileID == sourceTileID, window.isVisible {
            activeSourceTileID = sourceTileID
            pendingDismissTask?.cancel()
            pendingDismissTask = nil
            return true
        }

        currentTileID = sourceTileID
        currentBundleIdentifier = bundleIDs.count == 1 ? bundleIDs.first : nil
        activeSourceTileID = sourceTileID
        pendingDismissTask?.cancel()
        pendingDismissTask = nil
        dismissAnimationTask?.cancel()
        dismissAnimationTask = nil
        beginDockVisibilityHoldIfNeeded()

        // Two-pass sizing: measure the natural content, then re-host the
        // root view inside an explicit centered frame so the content stays
        // visually centered when the window is floored to the minimum
        // size (one-card thumbnail layouts are narrower than 240pt, and
        // NSHostingView would otherwise top-leading-align the content,
        // leaving the visible card offset from the source tile's midX).
        let sizingHostingView = NSHostingView(rootView: WindowPreviewWindowContent(sourceTileID: sourceTileID))
        sizingHostingView.layoutSubtreeIfNeeded()
        let fittingSize = sizingHostingView.fittingSize
        let windowSize = CGSize(
            width: max(fittingSize.width, 240),
            height: max(fittingSize.height, 80)
        )
        let hostingView = NSHostingView(
            rootView: WindowPreviewWindowContent(sourceTileID: sourceTileID)
                .frame(width: windowSize.width, height: windowSize.height)
        )

        let finalOrigin = frameOrigin(
            for: windowSize,
            sourceFrame: sourceFrame,
            preferredEdge: preferredEdge
        )
        let initialOrigin = initialOrigin(from: finalOrigin, preferredEdge: preferredEdge)
        let finalFrame = CGRect(origin: finalOrigin, size: windowSize)
        let initialFrame = CGRect(origin: initialOrigin, size: windowSize)

        window.contentView = hostingView
        window.setFrame(initialFrame, display: false)
        window.alphaValue = 0
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(finalFrame, display: true)
            window.animator().alphaValue = 1
        }

        return true
    }

    func dismiss(sourceTileID: String) {
        guard currentTileID == sourceTileID else { return }
        pendingDismissTask?.cancel()
        pendingDismissTask = nil
        isPreviewHovered = false
        endDockVisibilityHoldIfNeeded()
        currentTileID = nil
        currentBundleIdentifier = nil
        activeSourceTileID = nil

        // Don't clear WindowPreviewService state yet — the SwiftUI body
        // observes it, and emptying it synchronously would blank the popover
        // content before the alpha animation has a chance to play. We clear
        // it in the completion handler so the user sees a real fade-out.

        guard let window, window.isVisible else {
            WindowPreviewService.shared.dismiss()
            close()
            return
        }

        dismissAnimationTask?.cancel()
        dismissAnimationTask = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = Self.animationDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    continuation.resume()
                })
            }
            if Task.isCancelled { return }
            guard self.currentTileID == nil else { return }
            WindowPreviewService.shared.dismiss()
            self.close()
        }
    }

    func requestDismiss(sourceTileID: String) {
        guard currentTileID == sourceTileID else { return }
        guard !isPreviewHovered else { return }

        pendingDismissTask?.cancel()
        pendingDismissTask = Task { @MainActor in
            try? await Task.sleep(for: Self.dismissGrace)
            guard !Task.isCancelled else { return }
            guard self.currentTileID == sourceTileID, !self.isPreviewHovered else { return }
            self.dismiss(sourceTileID: sourceTileID)
        }
    }

    fileprivate func setPreviewHovered(_ isHovered: Bool, sourceTileID: String) {
        guard currentTileID == sourceTileID else { return }
        isPreviewHovered = isHovered

        if isHovered {
            pendingDismissTask?.cancel()
            pendingDismissTask = nil
        } else {
            requestDismiss(sourceTileID: sourceTileID)
        }
    }

    /// Closes whichever tile's preview is currently showing. Used by the
    /// SwiftUI cards/rows since they only know about the window they
    /// represent, not which source tile spawned the preview.
    func dismissCurrent() {
        guard let currentTileID else { return }
        dismiss(sourceTileID: currentTileID)
    }

    /// Tap-to-confirm: tear down the preview and focus the chosen window.
    func confirm(_ window: AppWindow) {
        dismissCurrent()
        _ = WorkspaceService.shared.focus(window: window)
    }

    var isShowing: Bool { window?.isVisible == true }
    var presentedSourceTileID: String? { currentTileID }

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

    /// Positions the preview window against the inward edge of the dock so
    /// it sits between the tile and the screen interior, mirroring
    /// WidgetExpansionWindowController's overflow handling per dock side.
    private func frameOrigin(
        for size: CGSize,
        sourceFrame originalSourceFrame: CGRect,
        preferredEdge: NSRectEdge
    ) -> CGPoint {
        // proxy.frame(in: .global) reports SwiftUI top-left coords relative to
        // the dock window's hosting view. Convert to AppKit screen bottom-left
        // before placing this NSWindow — otherwise vertical docks see a Y flip
        // and centered docks see an X offset (bottom docks happened to work by
        // coincidence when the tile sat at the dock window's vertical center).
        let sourceFrame = convertToScreen(originalSourceFrame)
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(sourceFrame) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return CGPoint(x: sourceFrame.midX - size.width / 2, y: sourceFrame.maxY)
        }

        switch preferredEdge {
        case .maxY:
            // Dock at bottom — preview above.
            let proposedY = sourceFrame.maxY
            let y = proposedY + size.height <= visibleFrame.maxY
                ? proposedY
                : max(visibleFrame.minY, sourceFrame.minY - size.height)
            let x = clamp(sourceFrame.midX - size.width / 2, visibleFrame: visibleFrame, size: size, axis: .x)
            return CGPoint(x: x, y: y)
        case .minY:
            // Dock at top — preview below.
            let proposedY = sourceFrame.minY - size.height
            let y = proposedY >= visibleFrame.minY ? proposedY : sourceFrame.maxY
            let x = clamp(sourceFrame.midX - size.width / 2, visibleFrame: visibleFrame, size: size, axis: .x)
            return CGPoint(x: x, y: y)
        case .maxX:
            // Dock on left — preview to the right.
            let proposedX = sourceFrame.maxX
            let x = proposedX + size.width <= visibleFrame.maxX
                ? proposedX
                : max(visibleFrame.minX, sourceFrame.minX - size.width)
            let y = clamp(sourceFrame.midY - size.height / 2, visibleFrame: visibleFrame, size: size, axis: .y)
            return CGPoint(x: x, y: y)
        case .minX:
            // Dock on right — preview to the left.
            let proposedX = sourceFrame.minX - size.width
            let x = proposedX >= visibleFrame.minX ? proposedX : sourceFrame.maxX
            let y = clamp(sourceFrame.midY - size.height / 2, visibleFrame: visibleFrame, size: size, axis: .y)
            return CGPoint(x: x, y: y)
        @unknown default:
            return CGPoint(x: sourceFrame.midX - size.width / 2, y: sourceFrame.maxY)
        }
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

    private enum Axis { case x, y }
    private func clamp(_ value: CGFloat, visibleFrame: CGRect, size: CGSize, axis: Axis) -> CGFloat {
        switch axis {
        case .x: return min(max(value, visibleFrame.minX), visibleFrame.maxX - size.width)
        case .y: return min(max(value, visibleFrame.minY), visibleFrame.maxY - size.height)
        }
    }

    private func initialOrigin(from final: CGPoint, preferredEdge: NSRectEdge) -> CGPoint {
        switch preferredEdge {
        case .maxY: return CGPoint(x: final.x, y: final.y - Self.slideOffset)
        case .minY: return CGPoint(x: final.x, y: final.y + Self.slideOffset)
        case .maxX: return CGPoint(x: final.x - Self.slideOffset, y: final.y)
        case .minX: return CGPoint(x: final.x + Self.slideOffset, y: final.y)
        @unknown default: return CGPoint(x: final.x, y: final.y - Self.slideOffset)
        }
    }
}

// MARK: - SwiftUI shell

/// Wraps the existing WindowPreviewView with a hover detector that keeps
/// the popover open while the cursor is inside it (and triggers the grace
/// dismiss when it leaves) — same coordination contract widget expansion
/// uses to bridge tile hover and detached-window hover.
private struct WindowPreviewWindowContent: View {
    let sourceTileID: String

    var body: some View {
        WindowPreviewView()
            .contentShape(Rectangle())
            .padding(.bottom, 8)
            .onHover { isHovering in
                WindowPreviewWindowController.shared.setPreviewHovered(isHovering, sourceTileID: sourceTileID)
            }
    }
}

// MARK: - SwiftUI views (intentional copies of the switcher's, trimmed)

private struct WindowPreviewView: View {
    @ObservedObject private var preview = WindowPreviewService.shared

    // 1:1 mirror of WindowSwitcherOverlayView's chrome geometry so the two
    // presentations stay visually coherent. Same constants, same formula.
    private let innerPreviewCornerRadius: CGFloat = 16
    private let cardPadding: CGFloat = 12
    private let containerPadding: CGFloat = 18
    private let interiorPadding: CGFloat = 8

    private var cardCornerRadius: CGFloat {
        innerPreviewCornerRadius + cardPadding
    }
    private var containerCornerRadius: CGFloat {
        cardCornerRadius + containerPadding
    }
    private var edgeContentCornerRadius: CGFloat {
        max(0, containerCornerRadius - interiorPadding)
    }
    private var innerContentCornerRadius: CGFloat {
        edgeContentCornerRadius / 2
    }

    var body: some View {
        // Empty state intentionally renders nothing — the controller never
        // presents a preview when windows are empty (`present` returns false),
        // and `removeWindow` tearing the last window also tells the controller
        // to dismiss. The branch is kept as a defensive no-op.
        if preview.windows.isEmpty {
            EmptyView()
        } else if preview.resolvedLayout == .thumbnails {
            thumbnailLayout
        } else {
            listLayout
        }
    }

    private var thumbnailLayout: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Array(preview.windows.enumerated()), id: \.element.id) { index, window in
                        let total = preview.windows.count
                        let isFirst = index == 0
                        let isLast = index == total - 1
                        let leadingRadius = isFirst ? edgeContentCornerRadius : innerContentCornerRadius
                        let trailingRadius = isLast ? edgeContentCornerRadius : innerContentCornerRadius
                        WindowPreviewCard(
                            window: window,
                            isSelected: window.windowIdentifier == preview.selectedWindowIdentifier,
                            innerPreviewCornerRadius: innerPreviewCornerRadius,
                            leadingCornerRadius: leadingRadius,
                            trailingCornerRadius: trailingRadius
                        )
                        .id(window.windowIdentifier)
                    }
                }
                .padding(interiorPadding)
            }
            .frame(maxWidth: 720)
            .fixedSize(horizontal: true, vertical: true)
            .background(.primary.opacity(0.18))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous))
            .onChange(of: preview.selectedWindowIdentifier) { selection in
                guard let selection else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    scrollProxy.scrollTo(selection, anchor: .center)
                }
            }
        }
    }

    private var listLayout: some View {
        WindowPreviewListView(
            cornerRadius: 16,
            interiorPadding: interiorPadding
        )
    }
}

private struct WindowPreviewCard: View {
    let window: AppWindow
    let isSelected: Bool
    let innerPreviewCornerRadius: CGFloat
    let leadingCornerRadius: CGFloat
    let trailingCornerRadius: CGFloat

    @ObservedObject private var preview = WindowPreviewService.shared
    @ObservedObject private var workspace = WorkspaceService.shared

    private let previewWidth: CGFloat = 180
    private let previewHeight: CGFloat = 102

    private var cardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: leadingCornerRadius,
                bottomLeading: leadingCornerRadius,
                bottomTrailing: trailingCornerRadius,
                topTrailing: trailingCornerRadius
            ),
            style: .continuous
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            previewSurface

            VStack(spacing: 4) {
                Text(window.windowTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.96))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(isSelected ? 1 : 0.25)

                Text(window.appDisplayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(isSelected ? 1 : 0.12)
            }
            .frame(width: previewWidth)
        }
        .padding(12)
        .background {
            cardShape
                .fill(isSelected ? .white.opacity(0.14) : .white.opacity(0))
                .overlay {
                    cardShape
                        .strokeBorder(isSelected ? .white.opacity(0.28) : .white.opacity(0), lineWidth: 1)
                }
        }
        .background {
            ContextActionMenuPresenter(
                actionProvider: contextActions(modifierFlags:),
                onPresentationChanged: preview.setContextMenuPresented
            )
        }
        .contentShape(cardShape)
        .onHover { isHovering in
            if isHovering {
                preview.selectWindow(withIdentifier: window.windowIdentifier)
            }
        }
        .onTapGesture {
            WindowPreviewWindowController.shared.confirm(window)
        }
        .animation(.easeInOut(duration: 0.14), value: isSelected)
    }

    private var previewSurface: some View {
        Group {
            if let image = preview.windowPreview(for: window) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: previewWidth, maxHeight: previewHeight)
            } else {
                Color.black.opacity(0.01)
                    .frame(maxWidth: previewWidth, maxHeight: previewHeight)
            }
        }
        .frame(width: previewWidth, height: previewHeight)
        // Desaturate stale minimized captures so they read as suspended,
        // matching the switcher card treatment.
        .saturation(window.isMinimized ? 0 : 1)
        .opacity(window.isMinimized ? 0.7 : 1)
        .clipShape(RoundedRectangle(cornerRadius: innerPreviewCornerRadius / 4, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if window.isMinimized {
                Image(systemName: "minus.diamond.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .padding(6)
            }
        }
    }

    private func contextActions(modifierFlags: NSEvent.ModifierFlags) -> [ContextAction] {
        let dismiss = { WindowPreviewWindowController.shared.dismissCurrent() }
        var actions: [ContextAction] = [
            .action(String(localized: "Focus Window")) {
                dismiss()
                _ = workspace.focus(window: window)
            },
            .divider,
        ]
        actions.append(contentsOf: windowMenuContextActions(for: window, dismiss: dismiss))
        actions.append(contentsOf: [
            .divider,
            .action(String(localized: "Close Window"), isDestructive: true) {
                if workspace.close(window: window) {
                    preview.removeWindow(withIdentifier: window.windowIdentifier)
                }
            },
            .divider,
            .action(String(localized: "Focus App")) {
                dismiss()
                workspace.focusApplication(bundleIdentifier: window.bundleIdentifier)
            },
            .action(String(localized: "Hide App")) {
                dismiss()
                workspace.hide(bundleIdentifier: window.bundleIdentifier)
            },
            .action(String(localized: "Quit")) {
                dismiss()
                workspace.quit(bundleIdentifier: window.bundleIdentifier)
            },
        ])
        return actions
    }
}

private struct WindowPreviewListView: View {
    let cornerRadius: CGFloat
    let interiorPadding: CGFloat

    @ObservedObject private var preview = WindowPreviewService.shared

    private let listWidth: CGFloat = 360
    private let rowHeight: CGFloat = 52
    private let maxVisibleRows: Int = 8

    private var edgeRowCornerRadius: CGFloat {
        max(0, cornerRadius - interiorPadding)
    }
    private var innerRowCornerRadius: CGFloat {
        edgeRowCornerRadius / 2
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(preview.windows.enumerated()), id: \.element.id) { index, window in
                        let total = preview.windows.count
                        let isFirst = index == 0
                        let isLast = index == total - 1
                        let topRadius = isFirst ? edgeRowCornerRadius : innerRowCornerRadius
                        let bottomRadius = isLast ? edgeRowCornerRadius : innerRowCornerRadius
                        WindowPreviewListRow(
                            window: window,
                            isSelected: window.windowIdentifier == preview.selectedWindowIdentifier,
                            height: rowHeight,
                            topCornerRadius: topRadius,
                            bottomCornerRadius: bottomRadius
                        )
                        .id(window.windowIdentifier)
                    }
                }
                .padding(interiorPadding)
            }
            .frame(width: listWidth)
            .frame(maxHeight: CGFloat(maxVisibleRows) * rowHeight + 16)
            .fixedSize(horizontal: true, vertical: true)
            .background(.primary.opacity(0.18))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onChange(of: preview.selectedWindowIdentifier) { selection in
                guard let selection else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    scrollProxy.scrollTo(selection, anchor: .center)
                }
            }
        }
    }
}

private struct WindowPreviewListRow: View {
    let window: AppWindow
    let isSelected: Bool
    let height: CGFloat
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    @ObservedObject private var preview = WindowPreviewService.shared
    @ObservedObject private var workspace = WorkspaceService.shared

    private let iconSize: CGFloat = 28

    private var rowShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: topCornerRadius,
                bottomLeading: bottomCornerRadius,
                bottomTrailing: bottomCornerRadius,
                topTrailing: topCornerRadius
            ),
            style: .continuous
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: IconCacheService.shared.icon(forBundleIdentifier: window.bundleIdentifier))
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(window.windowTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(isSelected ? 1 : 0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(window.appDisplayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(isSelected ? 0.75 : 0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if window.isMinimized {
                Image(systemName: "minus.diamond.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.55))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .background {
            rowShape
                .fill(isSelected ? .white.opacity(0.16) : .clear)
                .overlay {
                    rowShape.strokeBorder(isSelected ? .white.opacity(0.28) : .clear, lineWidth: 1)
                }
        }
        .background {
            ContextActionMenuPresenter(
                actionProvider: contextActions(modifierFlags:),
                onPresentationChanged: preview.setContextMenuPresented
            )
        }
        .contentShape(rowShape)
        .onHover { isHovering in
            if isHovering {
                preview.selectWindow(withIdentifier: window.windowIdentifier)
            }
        }
        .onTapGesture {
            WindowPreviewWindowController.shared.confirm(window)
        }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    private func contextActions(modifierFlags: NSEvent.ModifierFlags) -> [ContextAction] {
        let dismiss = { WindowPreviewWindowController.shared.dismissCurrent() }
        var actions: [ContextAction] = [
            .action(String(localized: "Focus Window")) {
                dismiss()
                _ = workspace.focus(window: window)
            },
            .divider,
        ]
        actions.append(contentsOf: windowMenuContextActions(for: window, dismiss: dismiss))
        actions.append(contentsOf: [
            .divider,
            .action(String(localized: "Close Window"), isDestructive: true) {
                if workspace.close(window: window) {
                    preview.removeWindow(withIdentifier: window.windowIdentifier)
                }
            },
            .divider,
            .action(String(localized: "Focus App")) {
                dismiss()
                workspace.focusApplication(bundleIdentifier: window.bundleIdentifier)
            },
            .action(String(localized: "Hide App")) {
                dismiss()
                workspace.hide(bundleIdentifier: window.bundleIdentifier)
            },
            .action(String(localized: "Quit")) {
                dismiss()
                workspace.quit(bundleIdentifier: window.bundleIdentifier)
            },
        ])
        return actions
    }
}
