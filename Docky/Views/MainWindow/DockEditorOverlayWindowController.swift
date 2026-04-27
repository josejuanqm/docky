//
//  DockEditorOverlayWindowController.swift
//  Docky
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

final class DockEditorOverlayWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private var cancellables: Set<AnyCancellable> = []
    private let overlayState = DockEditorOverlayState()

    init(mainWindow: MainWindow) {
        self.mainWindow = mainWindow

        let overlayWindow = DockEditorOverlayWindow()
        let hostingController = NSHostingController(rootView: DockEditorOverlayView(state: overlayState))
        overlayWindow.contentViewController = hostingController

        super.init(window: overlayWindow)

        observeEditMode()
        observeMainWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func observeEditMode() {
        DockEditModeService.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self else { return }
                if isActive {
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
        updateFrame()
        guard let window, let mainWindow else {
            return
        }

        window.level = NSWindow.Level.floating
        window.orderFront(nil)
        mainWindow.orderFrontRegardless()
    }

    private func dismissOverlay() {
        guard let window else {
            return
        }

        window.orderOut(nil)
    }

    private func updateFrame() {
        guard let window else {
            return
        }

        let screenFrame = mainWindow?.screen?.frame ?? NSScreen.main?.frame ?? .zero
        window.setFrame(screenFrame.integral, display: true)

        if let mainWindow {
            overlayState.dockFrame = CGRect(
                x: mainWindow.frame.minX - screenFrame.minX,
                y: screenFrame.maxY - mainWindow.frame.maxY,
                width: mainWindow.frame.width,
                height: mainWindow.frame.height
            ).integral
        } else {
            overlayState.dockFrame = .zero
        }
    }
}

private final class DockEditorOverlayState: ObservableObject {
    @Published var dockFrame: CGRect = .zero
}

private final class DockEditorOverlayWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct DockEditorOverlayView: View {
    private let paletteDockGap: CGFloat = 28
    @ObservedObject var state: DockEditorOverlayState
    @ObservedObject private var editMode = DockEditModeService.shared
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var mediaPlayback = MediaPlaybackService.shared

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let cutoutFrame = state.dockFrame
                let cornerRadius = preferences.windowClipShape.resolvedCornerRadius(
                    base: preferences.windowCornerRadius,
                    maximum: min(cutoutFrame.width, cutoutFrame.height) / 2
                )

                OverlayCutoutShape(cutoutFrame: cutoutFrame, cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial, style: FillStyle(eoFill: true))
                    .overlay {
                        OverlayCutoutShape(cutoutFrame: cutoutFrame, cornerRadius: cornerRadius)
                            .fill(Color.black.opacity(0.28), style: FillStyle(eoFill: true))
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editMode.exit()
                    }
            }
            .ignoresSafeArea()

            layout
                .padding(28)
        }
    }

    @ViewBuilder
    private var layout: some View {
        switch position {
        case .bottom:
            VStack {
                Spacer()
                editorPalette
                    .padding(.bottom, paletteInset)
            }
        case .top:
            VStack {
                editorPalette
                    .padding(.top, paletteInset)
                Spacer()
            }
        case .left:
            HStack {
                editorPalette
                    .padding(.leading, paletteInset)
                Spacer()
            }
        case .right:
            HStack {
                Spacer()
                editorPalette
                    .padding(.trailing, paletteInset)
            }
        }
    }

    private var editorPalette: some View {
        PaletteContainer(position: position) {
            ForEach(paletteItems) { item in
                PaletteItemView(item: item)
            }
        }
    }

    private var paletteItems: [DockEditPaletteItem] {
        [.spacer, .divider]
            + WidgetCatalog.paletteRegistrations.map {
                .widget(ownerBundleIdentifier: $0.ownerBundleIdentifier, kind: $0.kind)
            }
            + [.smartStack]
    }

    private var position: ResolvedDockWindowPosition {
        preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
    }

    private var paletteInset: CGFloat {
        switch position {
        case .bottom, .top:
            state.dockFrame.height + paletteDockGap
        case .left, .right:
            state.dockFrame.width + paletteDockGap
        }
    }
}

private struct OverlayCutoutShape: Shape {
    let cutoutFrame: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)

        if !cutoutFrame.isEmpty {
            path.addRoundedRect(
                in: cutoutFrame,
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
                style: .continuous
            )
        }

        return path
    }
}

private struct PaletteContainer<Content: View>: View {
    let position: ResolvedDockWindowPosition
    let content: Content
    @ObservedObject private var editMode = DockEditModeService.shared

    init(position: ResolvedDockWindowPosition, @ViewBuilder content: () -> Content) {
        self.position = position
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Edit Dock")
                    .font(.headline)
                Spacer(minLength: 0)
                Button("Done") {
                    editMode.exit()
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Drag controls into the pinned or folder/trash section to place them where you want.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            content
        }
        .padding(18)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .frame(maxWidth: position.isVertical ? 360 : 420)
    }
}

private struct PaletteItemView: View {
    let item: DockEditPaletteItem
    @ObservedObject private var editMode = DockEditModeService.shared
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.white.opacity(isDragging ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onDrag {
            isDragging = true
            editMode.beginPaletteDrag(item: item)
            return NSItemProvider(object: item.id as NSString)
        }
        .onDisappear {
            isDragging = false
        }
    }

    private var iconName: String {
        switch item {
        case .spacer:
            "rectangle.split.3x1"
        case .divider:
            "line.3.horizontal.decrease"
        case .widget(_, let kind):
            switch kind {
            case .calendar:
                "calendar"
            case .calendarDate:
                "calendar"
            case .reminders:
                "checklist"
            case .batteries:
                "battery.100percent"
            case .systemStatus:
                "gauge.with.needle"
            case .nowPlaying:
                "waveform"
            case .weather:
                "cloud.sun.fill"
            }
        case .smartStack:
            "square.stack.3d.up"
        }
    }

    private var title: String {
        switch item {
        case .spacer:
            "Spacer"
        case .divider:
            "Divider"
        case .widget(_, let kind):
            kind.title
        case .smartStack:
            "Smart Stack"
        }
    }

    private var subtitle: String {
        switch item {
        case .spacer:
            "Adds breathing room between pinned tiles"
        case .divider:
            "Adds a visual separator inside pinned tiles"
        case .widget(_, let kind):
            switch kind {
            case .calendar:
                "Shows the current date and month at a glance"
            case .calendarDate:
                "Shows the weekday and date number at a glance"
            case .reminders:
                "Shows your open tasks and what needs attention next"
            case .batteries:
                "Shows Mac and accessory battery levels at a glance"
            case .systemStatus:
                "Shows CPU, memory, and network activity at a glance"
            case .nowPlaying:
                "Adds a now playing widget inline"
            case .weather:
                "Shows current weather for your location"
            }
        case .smartStack:
            "Adds a stack of available widgets"
        }
    }
}
