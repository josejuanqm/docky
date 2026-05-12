//
//  WindowSwitcherOverlayWindowController.swift
//  Docky
//

import AppKit
import Combine
import SwiftUI

final class WindowSwitcherOverlayWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private var cancellables: Set<AnyCancellable> = []
    private let animationDuration: TimeInterval = 0.18
    private let preferences = DockyPreferences.shared

    private var showsOverlayUI: Bool {
        // Empty state — there's nothing to focus-preview, so we need the
        // overlay to render the "No windows available" message.
        if WindowSwitcherService.shared.windows.isEmpty {
            return true
        }

        // List layout always needs the overlay — it's the only thing the user
        // sees, since there are no window thumbnails behind it.
        if WindowSwitcherService.shared.resolvedLayout == .list {
            return true
        }

        guard ProductService.shared.isUnlocked(.windowSwitcher),
              preferences.showsWindowSwitcherFocusPreview,
              preferences.windowSwitcherPreviewMode == .instantFocus else {
            return true
        }

        return false
    }

    init(mainWindow: MainWindow) {
        self.mainWindow = mainWindow

        let overlayWindow = WindowSwitcherOverlayWindow()
        let hostingController = NSHostingController(rootView: WindowSwitcherOverlayView())
        overlayWindow.contentViewController = hostingController

        super.init(window: overlayWindow)

        prepareOverlayWindow()
        observeOverlayPresentation()
        observeMainWindow()
        observeSpaceBehavior()
        observePreviewMode()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func observeOverlayPresentation() {
        WindowSwitcherService.shared.$isPresented
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPresented in
                guard let self else { return }
                if isPresented {
                    self.presentOverlay()
                } else {
                    self.dismissOverlay()
                }
            }
            .store(in: &cancellables)
    }

    private func observeMainWindow() {
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: mainWindow)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: mainWindow))
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification, object: mainWindow))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFrame()
            }
            .store(in: &cancellables)
    }

    private func presentOverlay() {
        guard let window else { return }

        guard showsOverlayUI else {
            configureHiddenWindowState()
            return
        }

        updateFrame()
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissOverlay() {
        guard showsOverlayUI else {
            configureHiddenWindowState()
            return
        }

        animateWindowAlpha(to: 0) { [weak self] in
            guard let self, let window = self.window else { return }

            window.ignoresMouseEvents = true
            window.orderOut(nil)
        }
    }

    private func prepareOverlayWindow() {
        guard let window else { return }

        updateFrame()
        window.collectionBehavior = preferences.windowSpaceBehavior.collectionBehavior(includesFullScreenAuxiliary: true)
        configureHiddenWindowState()
    }

    private func observeSpaceBehavior() {
        observeChanges { [weak self] in
            let behavior = DockyPreferences.shared.windowSpaceBehavior
            self?.window?.collectionBehavior = behavior.collectionBehavior(includesFullScreenAuxiliary: true)
        }
        .store(in: &cancellables)
    }

    private func observePreviewMode() {
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.showsWindowSwitcherFocusPreview
            _ = DockyPreferences.shared.windowSwitcherPreviewMode
            self?.refreshOverlayPresentation()
        }
        .store(in: &cancellables)

        observeChanges { [weak self] in
            _ = DockyPreferences.shared.windowSwitcherLayout
            self?.refreshOverlayPresentation()
        }
        .store(in: &cancellables)

        PermissionsService.shared.$screenCapture
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshOverlayPresentation()
            }
            .store(in: &cancellables)
    }

    private func configureHiddenWindowState() {
        guard let window else { return }

        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderOut(nil)
    }

    private func refreshOverlayPresentation() {
        guard WindowSwitcherService.shared.isPresented else {
            configureHiddenWindowState()
            return
        }

        if showsOverlayUI {
            presentOverlay()
        } else {
            configureHiddenWindowState()
        }
    }

    private func updateFrame() {
        guard let window else { return }
        let screenFrame = mainWindow?.screen?.frame ?? NSScreen.main?.frame ?? .zero
        guard !screenFrame.isEmpty else { return }
        window.setFrame(screenFrame, display: window.isVisible)
    }

    private func animateWindowAlpha(to alphaValue: CGFloat, completion: (() -> Void)? = nil) {
        guard let window else {
            completion?()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = alphaValue
        } completionHandler: {
            completion?()
        }
    }
}

private final class WindowSwitcherOverlayWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct WindowSwitcherOverlayView: View {
    @ObservedObject private var switcher = WindowSwitcherService.shared
    @Bindable private var preferences = DockyPreferences.shared
    @ObservedObject private var permissions = PermissionsService.shared

    private let innerPreviewCornerRadius: CGFloat = 16
    private let cardPadding: CGFloat = 12
    private let containerPadding: CGFloat = 18
    /// Inner padding between the chrome and its content. Same value for both
    /// layouts so the formula `chrome - padding` produces consistent edge
    /// radii across thumbnails and list.
    private let interiorPadding: CGFloat = 8

    private var cardCornerRadius: CGFloat {
        innerPreviewCornerRadius + cardPadding
    }

    private var containerCornerRadius: CGFloat {
        cardCornerRadius + containerPadding
    }

    /// Outer corner radius for cards/rows touching the chrome edge —
    /// chrome radius minus the interior padding so curves run parallel.
    private var edgeContentCornerRadius: CGFloat {
        max(0, containerCornerRadius - interiorPadding)
    }

    /// Half the edge radius. Used for corners facing a neighbor card/row.
    private var innerContentCornerRadius: CGFloat {
        edgeContentCornerRadius / 2
    }

    private var resolvedLayout: WindowSwitcherLayout {
        preferences.windowSwitcherLayout
            .resolved(canCaptureThumbnails: permissions.screenCapture == .granted)
    }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        GeometryReader { proxy in
            ZStack {
                // Stretches the ZStack to the GeometryReader's proposed size so
                // the centered child (cards or list) is centered against the
                // full screen, not the child's own bounds.
                Color.clear.ignoresSafeArea()

                if switcher.windows.isEmpty {
                    emptyStateCard
                } else if resolvedLayout == .thumbnails {
                    Color.black.opacity(switcher.focusedPreview == nil ? 0 : 0.6)
                        .ignoresSafeArea()

                    if let focusedPreview = switcher.focusedPreview {
                        FocusedWindowPreviewView(
                            preview: focusedPreview,
                            containerSize: proxy.size
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }

                    thumbnailLayout(containerSize: proxy.size)
                } else {
                    listLayout
                }
            }
            .animation(.easeInOut(duration: 0.18), value: switcher.focusedPreview?.windowIdentifier)
        }
    }

    private func thumbnailLayout(containerSize: CGSize) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Array(switcher.windows.enumerated()), id: \.element.id) { index, window in
                        let total = switcher.windows.count
                        let isFirst = index == 0
                        let isLast = index == total - 1
                        // Mirror of the list layout, rotated 90°: leading
                        // corners hug chrome on the first card, trailing on
                        // the last card; corners facing a neighbor get the
                        // inner radius.
                        let leadingRadius = isFirst ? edgeContentCornerRadius : innerContentCornerRadius
                        let trailingRadius = isLast ? edgeContentCornerRadius : innerContentCornerRadius
                        WindowSwitcherCard(
                            window: window,
                            isSelected: window.windowIdentifier == switcher.selectedWindowIdentifier,
                            innerPreviewCornerRadius: innerPreviewCornerRadius,
                            leadingCornerRadius: leadingRadius,
                            trailingCornerRadius: trailingRadius
                        )
                        .id(window.windowIdentifier)
                    }
                }
                .padding(interiorPadding)
            }
            .frame(maxWidth: max(0, containerSize.width - 80))
            .fixedSize(horizontal: true, vertical: true)
            .background(.primary.opacity(0.18))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous))
            .onChange(of: switcher.selectedWindowIdentifier) { selection in
                guard let selection else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    scrollProxy.scrollTo(selection, anchor: .center)
                }
            }
        }
    }

    private var listLayout: some View {
        // List chrome is tighter than thumbnail mode — the container is
        // text-only so a small radius reads cleaner than the chunky 46pt
        // used for the thumbnail card stack.
        WindowSwitcherListView(cornerRadius: 16, interiorPadding: interiorPadding)
    }

    private var emptyStateCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
            VStack(alignment: .leading, spacing: 2) {
                Text("No windows available")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Nothing to switch to right now.")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.primary.opacity(0.18))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct WindowSwitcherListView: View {
    let cornerRadius: CGFloat
    let interiorPadding: CGFloat

    @ObservedObject private var switcher = WindowSwitcherService.shared

    private let listWidth: CGFloat = 360
    private let rowHeight: CGFloat = 52
    private let maxVisibleRows: Int = 8

    /// First and last rows hug the container chrome — their radius is the
    /// container's radius minus our inner padding, so the row's outer edge
    /// runs parallel to the container edge.
    private var edgeRowCornerRadius: CGFloat {
        max(0, cornerRadius - interiorPadding)
    }

    /// Middle rows step the radius down — half the edge radius — so
    /// in-list selection highlights look like rows, not detached pills.
    private var innerRowCornerRadius: CGFloat {
        edgeRowCornerRadius / 2
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(switcher.windows.enumerated()), id: \.element.id) { index, window in
                        let total = switcher.windows.count
                        let isFirst = index == 0
                        let isLast = index == total - 1
                        // Outer edge (top of first row, bottom of last row)
                        // hugs the chrome; the inner edge — facing a neighbor
                        // row — uses the half radius for visual continuity.
                        let topRadius = isFirst ? edgeRowCornerRadius : innerRowCornerRadius
                        let bottomRadius = isLast ? edgeRowCornerRadius : innerRowCornerRadius
                        WindowSwitcherListRow(
                            window: window,
                            isSelected: window.windowIdentifier == switcher.selectedWindowIdentifier,
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
            .onChange(of: switcher.selectedWindowIdentifier) { selection in
                guard let selection else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    scrollProxy.scrollTo(selection, anchor: .center)
                }
            }
        }
    }
}

private struct WindowSwitcherListRow: View {
    let window: AppWindow
    let isSelected: Bool
    let height: CGFloat
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    @ObservedObject private var switcher = WindowSwitcherService.shared
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
                Image(systemName: "minus.rectangle.fill")
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
                    rowShape
                        .strokeBorder(isSelected ? .white.opacity(0.28) : .clear, lineWidth: 1)
                }
        }
        .background {
            ContextActionMenuPresenter(
                actionProvider: contextActions(modifierFlags:),
                onPresentationChanged: switcher.setContextMenuPresented
            )
        }
        .contentShape(rowShape)
        .onHover { isHovering in
            if isHovering {
                switcher.selectWindow(withIdentifier: window.windowIdentifier)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    private func contextActions(modifierFlags: NSEvent.ModifierFlags) -> [ContextAction] {
        guard ProductService.shared.isUnlocked(.windowSwitcher) else {
            return []
        }

        let dismiss = { switcher.dismiss() }
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
                    switcher.removeWindow(withIdentifier: window.windowIdentifier)
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

private struct FocusedWindowPreviewView: View {
    let preview: FocusedWindowPreview
    let containerSize: CGSize

    var body: some View {
        Image(nsImage: preview.image)
            .resizable()
            .interpolation(.high)
            .frame(width: previewSize.width, height: previewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 28, y: 10)
            .position(previewCenter)
    }

    private var previewSize: CGSize {
        CGSize(
            width: min(preview.screenBounds.width, containerSize.width),
            height: min(preview.screenBounds.height, containerSize.height)
        )
    }

    private var previewCenter: CGPoint {
        CGPoint(
            x: min(max(preview.screenBounds.minX + (previewSize.width / 2), previewSize.width / 2), containerSize.width - (previewSize.width / 2)),
            y: min(max(preview.screenBounds.minY + (previewSize.height / 2), previewSize.height / 2), containerSize.height - (previewSize.height / 2))
        )
    }
}

private struct WindowSwitcherCard: View {
    let window: AppWindow
    let isSelected: Bool
    let innerPreviewCornerRadius: CGFloat
    let leadingCornerRadius: CGFloat
    let trailingCornerRadius: CGFloat
    @ObservedObject private var switcher = WindowSwitcherService.shared
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
            .frame(width: 180)
        }
        .padding(12)
        .background {
            cardShape
                .fill(isSelected ? .white.opacity(0.14) : .white.opacity(0.0))
                .overlay {
                    cardShape
                        .strokeBorder(isSelected ? .white.opacity(0.28) : .white.opacity(0.0), lineWidth: 1)
                }
        }
        .background {
            ContextActionMenuPresenter(
                actionProvider: contextActions(modifierFlags:),
                onPresentationChanged: switcher.setContextMenuPresented
            )
        }
        .contentShape(cardShape)
        .onHover { isHovering in
            if isHovering {
                switcher.selectWindow(withIdentifier: window.windowIdentifier)
            }
        }
        .animation(.easeInOut(duration: 0.14), value: isSelected)
    }

    private var previewSurface: some View {
        Group {
            if let preview = switcher.windowPreview(for: window) {
                Image(nsImage: preview)
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
        .clipShape(RoundedRectangle(cornerRadius: innerPreviewCornerRadius/4, style: .continuous))
    }

    private func contextActions(modifierFlags: NSEvent.ModifierFlags) -> [ContextAction] {
        guard ProductService.shared.isUnlocked(.windowSwitcher) else {
            return []
        }

        let dismiss = { switcher.dismiss() }
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
                    switcher.removeWindow(withIdentifier: window.windowIdentifier)
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
