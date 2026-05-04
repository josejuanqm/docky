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
        preferences.$windowSpaceBehavior
            .receive(on: DispatchQueue.main)
            .sink { [weak self] behavior in
                self?.window?.collectionBehavior = behavior.collectionBehavior(includesFullScreenAuxiliary: true)
            }
            .store(in: &cancellables)
    }

    private func observePreviewMode() {
        Publishers.CombineLatest(
            preferences.$showsWindowSwitcherFocusPreview,
            preferences.$windowSwitcherPreviewMode
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
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
    @ObservedObject private var preferences = DockyPreferences.shared

    private let innerPreviewCornerRadius: CGFloat = 16
    private let cardPadding: CGFloat = 12
    private let containerPadding: CGFloat = 18

    private var cardCornerRadius: CGFloat {
        innerPreviewCornerRadius + cardPadding
    }

    private var containerCornerRadius: CGFloat {
        cardCornerRadius + containerPadding
    }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        GeometryReader { proxy in
            ZStack {
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

                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 18) {
                            ForEach(switcher.windows) { window in
                                WindowSwitcherCard(
                                    window: window,
                                    isSelected: window.windowIdentifier == switcher.selectedWindowIdentifier,
                                    innerPreviewCornerRadius: innerPreviewCornerRadius,
                                    cardCornerRadius: cardCornerRadius
                                )
                                .id(window.windowIdentifier)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 28)
                    }
                    .frame(maxWidth: max(0, proxy.size.width - 80))
                    .fixedSize(horizontal: true, vertical: true)
                    .background(.primary.opacity(0.18))
                    .glassEffect(.regular, in: .rect(cornerRadius: containerCornerRadius, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous))
                    .onChange(of: switcher.selectedWindowIdentifier) { _, selection in
                        guard let selection else { return }
                        withAnimation(.easeInOut(duration: 0.14)) {
                            scrollProxy.scrollTo(selection, anchor: .center)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.18), value: switcher.focusedPreview?.windowIdentifier)
        }
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
    let cardCornerRadius: CGFloat
    @ObservedObject private var switcher = WindowSwitcherService.shared
    @ObservedObject private var workspace = WorkspaceService.shared

    private let previewWidth: CGFloat = 180
    private let previewHeight: CGFloat = 102

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
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(isSelected ? .white.opacity(0.14) : .white.opacity(0.0))
                .overlay {
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .strokeBorder(isSelected ? .white.opacity(0.28) : .white.opacity(0.0), lineWidth: 1)
                }
        }
        .background {
            ContextActionMenuPresenter(
                actionProvider: contextActions(modifierFlags:),
                onPresentationChanged: switcher.setContextMenuPresented
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
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
                    .frame(maxHeight: previewHeight)
            } else {
                Color.black.opacity(0.01)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: previewHeight)
            }
        }
        .frame(height: previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: innerPreviewCornerRadius/4, style: .continuous))
    }

    private func contextActions(modifierFlags: NSEvent.ModifierFlags) -> [ContextAction] {
        guard ProductService.shared.isUnlocked(.windowSwitcher) else {
            return []
        }

        return [
            .action("Focus Window") {
                switcher.dismiss()
                _ = workspace.focus(window: window)
            },
            .action("Minimize Window") {
                switcher.dismiss()
                _ = workspace.minimize(window: window)
            },
            .action("Close Window", isDestructive: true) {
                if workspace.close(window: window) {
                    switcher.removeWindow(withIdentifier: window.windowIdentifier)
                }
            },
            .divider,
            .action("Focus App") {
                switcher.dismiss()
                workspace.focusApplication(bundleIdentifier: window.bundleIdentifier)
            },
            .action("Hide App") {
                switcher.dismiss()
                workspace.hide(bundleIdentifier: window.bundleIdentifier)
            },
            .action("Quit") {
                switcher.dismiss()
                workspace.quit(bundleIdentifier: window.bundleIdentifier)
            }
        ]
    }
}
