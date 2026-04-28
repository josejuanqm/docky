//
//  LaunchpadOverlayWindowController.swift
//  Docky
//

import AppKit
import Combine
import SwiftUI

final class LaunchpadOverlayWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var isInterruptingMainWindow = false

    init(mainWindow: MainWindow) {
        self.mainWindow = mainWindow

        let overlayWindow = LaunchpadOverlayWindow()
        let hostingController = NSHostingController(rootView: LaunchpadOverlayView())
        overlayWindow.contentViewController = hostingController

        super.init(window: overlayWindow)

        observeOverlayPresentation()
        observeMainWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func observeOverlayPresentation() {
        LaunchpadOverlayService.shared.$isPresented
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

        updateFrame()
        beginMainWindowInteraction()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissOverlay() {
        window?.orderOut(nil)
        endMainWindowInteraction()
    }

    private func updateFrame() {
        guard let window else { return }
        let screenFrame = mainWindow?.screen?.frame ?? NSScreen.main?.frame ?? .zero
        guard !screenFrame.isEmpty else { return }
        window.setFrame(screenFrame, display: true)
    }

    private func beginMainWindowInteraction() {
        guard !isInterruptingMainWindow else { return }
        mainWindow?.beginInteraction()
        isInterruptingMainWindow = true
    }

    private func endMainWindowInteraction() {
        guard isInterruptingMainWindow else { return }
        mainWindow?.endInteraction()
        isInterruptingMainWindow = false
    }
}

private final class LaunchpadOverlayWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct LaunchpadOverlayView: View {
    @ObservedObject private var overlay = LaunchpadOverlayService.shared
    @ObservedObject private var preferences = DockyPreferences.shared
    @State private var searchText = ""
    @State private var selectedBundleIdentifier: String?
    @FocusState private var isSearchFocused: Bool

    private let searchBarWidth: CGFloat = 560
    private let searchBarTopInset: CGFloat = 56
    private let searchBarHeight: CGFloat = 56
    private let appCardScale: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(proxy.size.width - 96, 1440)
            let columnCount = gridColumnCount(for: proxy.size.width)

            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        overlay.dismiss()
                    }

                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 28) {
                            LazyVGrid(columns: gridColumns(for: proxy.size.width), spacing: 48) {
                                ForEach(filteredApps, id: \.bundleIdentifier) { app in
                                    Button {
                                        launch(app)
                                    } label: {
                                        LaunchpadAppCard(
                                            app: app,
                                            isSelected: app.bundleIdentifier == selectedBundleIdentifier,
                                            scale: appCardScale
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .id(app.bundleIdentifier)
                                }
                            }
                            .frame(width: contentWidth)
                        }
                        .frame(width: contentWidth)
                        .padding(.top, searchBarTopInset + searchBarHeight + 24)
                        .onChange(of: selectedBundleIdentifier) { _, selection in
                            guard let selection else { return }
                            withAnimation(.easeInOut(duration: 0.16)) {
                                scrollProxy.scrollTo(selection, anchor: .center)
                            }
                        }
                        .onChange(of: filteredApps.map(\.bundleIdentifier)) { _, _ in
                            synchronizeSelection()
                        }
                    }
                    .scrollClipDisabled()
                    .padding(.horizontal, 48)
                    .padding(.vertical, 56)
                    .frame(maxWidth: .infinity)
                }

                VStack {
                    searchField
                        .frame(width: min(contentWidth, searchBarWidth))
                        .padding(.top, searchBarTopInset)

                    Spacer()
                }
            }
            .ignoresSafeArea()
            .onExitCommand {
                overlay.dismiss()
            }
            .background {
                LaunchpadOverlayKeyMonitor { event in
                    handleKeyDown(event, columnCount: columnCount)
                }
            }
            .onAppear {
                isSearchFocused = true
                synchronizeSelection()
            }
            .onChange(of: overlay.isPresented) { _, isPresented in
                if isPresented {
                    searchText = ""
                    isSearchFocused = true
                    synchronizeSelection()
                }
            }
        }
    }

    private var filteredApps: [AppTile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return overlay.apps }

        return overlay.apps
            .compactMap { app -> (app: AppTile, score: Int)? in
                let score = matchScore(for: app, query: query)
                guard score != Int.max else { return nil }
                return (app, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score < rhs.score
                }

                return lhs.app.displayName.localizedCaseInsensitiveCompare(rhs.app.displayName) == .orderedAscending
            }
            .map(\.app)
    }

    private func matchScore(for app: AppTile, query: String) -> Int {
        let loweredQuery = query.lowercased()
        let displayName = app.displayName.lowercased()
        let bundleIdentifier = app.bundleIdentifier.lowercased()

        if displayName == loweredQuery {
            return 0
        }

        if displayName.hasPrefix(loweredQuery) {
            return 1
        }

        if let range = displayName.range(of: loweredQuery) {
            return 10 + displayName.distance(from: displayName.startIndex, to: range.lowerBound)
        }

        if bundleIdentifier == loweredQuery {
            return 100
        }

        if bundleIdentifier.hasPrefix(loweredQuery) {
            return 101
        }

        if let range = bundleIdentifier.range(of: loweredQuery) {
            return 110 + bundleIdentifier.distance(from: bundleIdentifier.startIndex, to: range.lowerBound)
        }

        return Int.max
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.primary.opacity(0.7))

            TextField("Search apps", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary.opacity(0.95))
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.primary.opacity(0.45), .primary.opacity(0.2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.windowBackground.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private func gridColumns(for availableWidth: CGFloat) -> [GridItem] {
        let count = gridColumnCount(for: availableWidth)
        return Array(
            repeating: GridItem(.flexible(minimum: 120, maximum: 152), spacing: 48, alignment: .top),
            count: count
        )
    }

    private func gridColumnCount(for availableWidth: CGFloat) -> Int {
        let usableWidth = max(min(availableWidth - 96, 1440), 320)
        let maximumColumnsThatFit = max(Int(usableWidth / 140), 1)
        return min(preferences.launchpadGridColumnCount, maximumColumnsThatFit)
    }

    private func handleKeyDown(_ event: NSEvent, columnCount: Int) -> Bool {
        guard event.type == .keyDown else { return false }

        switch event.keyCode {
        case 53:
            overlay.dismiss()
            return true
        case 36, 76:
            guard let selectedApp else { return false }
            launch(selectedApp)
            return true
        case 123:
            moveSelection(delta: -1)
            return true
        case 124:
            moveSelection(delta: 1)
            return true
        case 125:
            moveSelection(delta: columnCount)
            return true
        case 126:
            moveSelection(delta: -columnCount)
            return true
        default:
            return false
        }
    }

    private var selectedApp: AppTile? {
        guard let selectedBundleIdentifier else {
            return filteredApps.first
        }

        return filteredApps.first { $0.bundleIdentifier == selectedBundleIdentifier }
            ?? filteredApps.first
    }

    private func synchronizeSelection() {
        selectedBundleIdentifier = selectedApp?.bundleIdentifier
    }

    private func moveSelection(delta: Int) {
        guard !filteredApps.isEmpty else { return }

        let currentIndex = filteredApps.firstIndex { $0.bundleIdentifier == selectedBundleIdentifier } ?? 0
        let newIndex = min(max(currentIndex + delta, 0), filteredApps.count - 1)
        selectedBundleIdentifier = filteredApps[newIndex].bundleIdentifier
        isSearchFocused = true
    }

    private func launch(_ app: AppTile) {
        overlay.dismiss()
        WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
    }
}

private struct LaunchpadAppCard: View {
    let app: AppTile
    let isSelected: Bool
    let scale: CGFloat
    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 76 * scale, height: 76 * scale)

            Text(app.displayName)
                .font(.system(size: 7.5 * scale, weight: .medium))
                .foregroundStyle(.primary.opacity(0.95))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 14 * scale)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.primary.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.primary.opacity(0.22), lineWidth: 1)
                    }
            }
        }
        .contentShape(Rectangle())
    }

    private var icon: NSImage {
        if let overrideURL = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: app.bundleIdentifier),
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return IconCacheService.shared.icon(forBundleIdentifier: app.bundleIdentifier)
    }
}

private struct LaunchpadOverlayKeyMonitor: NSViewRepresentable {
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
    }
}
