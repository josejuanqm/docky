//
//  StartMenuOverlayWindowController.swift
//  Docky
//
//  Prototype controller. Hosts a borderless `.nonactivatingPanel`
//  attached to the dock via `addChildWindow(_:ordered:)`. The two
//  things this prototype is meant to verify:
//
//   1. Movement grouping — when the dock re-anchors (edge change,
//      screen change, manual setFrame), does the child follow without
//      us wiring our own move/resize observers?
//   2. Focus — can a `.nonactivatingPanel` child become key for its
//      SwiftUI TextField without pulling Docky to the foreground?
//      (Spotlight's pattern.)
//

import AppKit
import Carbon
import Combine
import SwiftUI

final class StartMenuOverlayWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var isInterruptingMainWindow = false
    private var isAttachedToParent = false
    private var localDismissMonitor: Any?
    private var globalDismissMonitor: Any?
    private var escapeKeyMonitor: Any?
    /// systemUptime captured when the dismiss monitors are installed.
    /// Used to swallow the very click that opened the menu, which can
    /// reach the local monitor with a timestamp predating install
    /// because Combine defers present() to the next runloop tick but
    /// the originating mouseDown stays queued.
    private var dismissMonitorsInstalledAt: TimeInterval = 0
    private let animationDuration: TimeInterval = 0.16
    /// The host panel is always sized for both sub-panels so the layout
    /// never reflows. The right slot stays transparent (and non-
    /// interactive) until the user toggles the all-apps panel on.
    private let mainPanelWidth: CGFloat = 440
    private let sidePanelWidth: CGFloat = 280
    private let sidePanelGap: CGFloat = 8
    private var panelSize: NSSize {
        NSSize(width: mainPanelWidth + sidePanelGap + sidePanelWidth, height: 680)
    }
    private let gap: CGFloat = 8
    private let hostingController = NSHostingController(rootView: StartMenuView())

    init(mainWindow: MainWindow) {
        self.mainWindow = mainWindow

        let panel = StartMenuPanel()
        panel.setContentSize(NSSize(width: 440 + 8 + 280, height: 680))
        panel.contentViewController = hostingController

        super.init(window: panel)

        prepareWindow()
        observePresentation()
        observeChromeAndParent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func prepareWindow() {
        guard let window else { return }
        window.alphaValue = 0
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    private func observePresentation() {
        StartMenuService.shared.$isPresented
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPresented in
                guard let self else { return }
                isPresented ? self.present() : self.dismiss()
            }
            .store(in: &cancellables)
    }

    /// Re-anchor whenever the chrome rect inside the window shifts
    /// (tile add/remove, magnification, axis-sizing toggle) or when the
    /// parent's frame itself changes (edge change, screen change).
    /// addChildWindow already translates the child for parent moves,
    /// but it can't see chrome shifts that happen inside the parent.
    private func observeChromeAndParent() {
        DockLayoutService.shared.$chromeSize
            .removeDuplicates(by: { abs($0.width - $1.width) < 0.5 && abs($0.height - $1.height) < 0.5 })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateFrameIfPresented() }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        center.publisher(for: NSWindow.didMoveNotification, object: mainWindow)
            .merge(with: center.publisher(for: NSWindow.didResizeNotification, object: mainWindow))
            .merge(with: center.publisher(for: NSWindow.didChangeScreenNotification, object: mainWindow))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateFrameIfPresented() }
            .store(in: &cancellables)
    }

    private func updateFrameIfPresented() {
        guard StartMenuService.shared.isPresented else { return }
        updateFrame()
    }

    private func present() {
        guard let panel = window as? StartMenuPanel, let main = mainWindow else { return }
        updateFrame()
        beginMainInteraction()
        if !isAttachedToParent {
            main.addChildWindow(panel, ordered: .above)
            isAttachedToParent = true
        }
        // Re-assert level after addChildWindow because AppKit will pin
        // the child's z-order relative to the parent and can clamp the
        // absolute level in the process.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitors()
        animateAlpha(to: 1)
    }

    private func dismiss() {
        removeDismissMonitors()
        animateAlpha(to: 0) { [weak self] in
            guard let self, let panel = self.window as? StartMenuPanel else { return }
            if self.isAttachedToParent, let main = self.mainWindow {
                main.removeChildWindow(panel)
                self.isAttachedToParent = false
            }
            panel.orderOut(nil)
            self.endMainInteraction()
        }
    }

    private func updateFrame() {
        guard let panel = window, let main = mainWindow,
              let screen = main.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let position = DockyPreferences.shared.windowPosition
            .resolved(systemOrientation: DockSettingsService.shared.orientation)

        // Anchor against the visible chrome rect when available; fall
        // back to the window frame for the brief startup window before
        // TileContainerView has reported its first geometry pass.
        let anchor = main.chromeScreenFrame() ?? main.frame

        // Leading along-axis is the user's natural reading-start edge:
        // left for horizontal docks, top for vertical docks. Trailing
        // across-axis is the chrome's inward edge (the side that faces
        // the rest of the screen). The panel hugs the corner where
        // those two edges meet, then extends inward and along the axis.
        let size = panelSize
        let origin: CGPoint
        switch position {
        case .bottom:
            origin = CGPoint(x: anchor.minX, y: anchor.maxY + gap)
        case .top:
            origin = CGPoint(x: anchor.minX, y: anchor.minY - size.height - gap)
        case .left:
            origin = CGPoint(x: anchor.maxX + gap, y: anchor.maxY - size.height)
        case .right:
            origin = CGPoint(x: anchor.minX - size.width - gap, y: anchor.maxY - size.height)
        }

        let clamped = CGPoint(
            x: min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8),
            y: min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        )

        panel.setFrame(CGRect(origin: clamped, size: size).integral, display: true)
    }


    private func animateAlpha(to value: CGFloat, completion: (() -> Void)? = nil) {
        guard let window else {
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = value
        } completionHandler: {
            completion?()
        }
    }

    private func beginMainInteraction() {
        guard !isInterruptingMainWindow else { return }
        mainWindow?.beginInteraction()
        isInterruptingMainWindow = true
    }

    private func endMainInteraction() {
        guard isInterruptingMainWindow else { return }
        mainWindow?.endInteraction()
        isInterruptingMainWindow = false
    }

    /// Click-outside-to-dismiss. Local monitor fires when the click
    /// lands in any Docky window (including the dock itself); global
    /// fires for every other app. The hit test against the panel
    /// frame in screen coords keeps clicks inside the start menu
    /// from dismissing it.
    private func installDismissMonitors() {
        guard localDismissMonitor == nil, globalDismissMonitor == nil else { return }

        dismissMonitorsInstalledAt = ProcessInfo.processInfo.systemUptime

        let dismissIfOutside: () -> Void = { [weak self] in
            guard let self, let panel = self.window else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                DispatchQueue.main.async {
                    StartMenuService.shared.dismiss()
                }
            }
        }

        localDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            // Suppress the originating tile click: its timestamp is
            // already older than the install time by the time we get
            // here, otherwise a single tap would open + close in one go.
            guard event.timestamp > self.dismissMonitorsInstalledAt else {
                return event
            }
            // Clicks on the dock itself are handled by the source
            // tile's own tap logic: the start-menu / Finder tile
            // calls `toggle()`, which closes the menu cleanly. If we
            // also dismissed here, the tap handler would see
            // `isPresented == false` and reopen on the same click.
            if let eventWindow = event.window, eventWindow === self.mainWindow {
                return event
            }
            dismissIfOutside()
            return event
        }

        globalDismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return }
            guard event.timestamp > self.dismissMonitorsInstalledAt else {
                return
            }
            dismissIfOutside()
        }

        // Escape dismisses while the menu has key focus. Returning nil
        // swallows the event so the focused TextField doesn't also see
        // it (and try to clear its contents on first press).
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Int(event.keyCode) == kVK_Escape else { return event }
            DispatchQueue.main.async {
                StartMenuService.shared.dismiss()
            }
            return nil
        }
    }

    private func removeDismissMonitors() {
        if let monitor = localDismissMonitor {
            NSEvent.removeMonitor(monitor)
            localDismissMonitor = nil
        }
        if let monitor = globalDismissMonitor {
            NSEvent.removeMonitor(monitor)
            globalDismissMonitor = nil
        }
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
    }
}

private final class StartMenuPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // AppKit derives a window shadow from the content alpha mask, and
        // on a transparent panel hosting separate SwiftUI glass surfaces
        // that mask has aliased sub-pixel edges along the panel
        // perimeter, which render as a faint hairline around the whole
        // window. The shadows on each sub-panel come from SwiftUI's own
        // `.shadow(...)` modifier instead.
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    }

    /// `.nonactivatingPanel` + `canBecomeKey == true` is the Spotlight
    /// pattern: the panel can take keyboard focus (so the SwiftUI
    /// TextField actually receives input) without bringing Docky to
    /// the foreground.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct StartMenuView: View {
    @ObservedObject private var recents = RecentFilesService.shared
    @ObservedObject private var launchpad = LaunchpadOverlayService.shared
    @ObservedObject private var recentApps = RecentAppsService.shared
    @ObservedObject private var service = StartMenuService.shared
    @Bindable private var preferences = DockyPreferences.shared
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private let mainWidth: CGFloat = 440
    private let allAppsWidth: CGFloat = 280

    /// Two rows worth of recent apps; the grid wraps to ~4 columns at the
    /// current panel width, so 8 is a comfortable upper bound.
    private static let recentAppsLimit = 8

    private var filteredRecents: [URL] {
        let urls = recents.recentURLs
        guard !query.isEmpty else { return urls }
        return urls.filter {
            $0.lastPathComponent.localizedCaseInsensitiveContains(query)
        }
    }

    /// Apps section content: with an empty query we surface the two-row
    /// recents shelf; while searching we fall back to the launchpad set
    /// so the user can find any installed app, not just ones they've
    /// recently touched.
    private var appsSectionTiles: [AppTile] {
        if query.isEmpty {
            return resolveTiles(forBundleIDs: Array(recentApps.recentBundleIdentifiers.prefix(Self.recentAppsLimit)))
        }
        let all = Self.flattened(launchpad.entries)
        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    private var appsSectionTitle: String {
        query.isEmpty ? "Recent Apps" : "Apps"
    }

    /// Map persisted bundle IDs to AppTile by resolving each via
    /// NSWorkspace. Missing bundles (uninstalled apps) drop out, and so
    /// do system-bundled apps and anything outside the user-facing
    /// `/Applications` and `~/Applications` roots, so the Recent Apps
    /// shelf only ever surfaces things the user actually installed.
    private func resolveTiles(forBundleIDs ids: [String]) -> [AppTile] {
        let allowedRoots = Self.userAppRoots
        return ids.compactMap { bundleID in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                  Self.isURL(url, under: allowedRoots) else {
                return nil
            }
            return AppTile(
                bundleIdentifier: bundleID,
                displayName: FileManager.default.displayName(atPath: url.path)
            )
        }
    }

    private static let userAppRoots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true),
    ]

    private static func isURL(_ url: URL, under roots: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        return roots.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }

    private var filteredHomeFolders: [HomeFolderShortcut] {
        let all = Self.homeFolders
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Canonical user shortcuts. URLs are built from
    /// FileManager.homeDirectoryForCurrentUser plus the path Apple ships
    /// these folders at, so they work even when one of them has been
    /// removed (the click just no-ops if the folder is missing).
    private static let homeFolders: [HomeFolderShortcut] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            HomeFolderShortcut(name: "Home", url: home),
            HomeFolderShortcut(name: "Documents", url: home.appendingPathComponent("Documents", isDirectory: true)),
            HomeFolderShortcut(name: "Downloads", url: home.appendingPathComponent("Downloads", isDirectory: true)),
            HomeFolderShortcut(name: "Desktop", url: home.appendingPathComponent("Desktop", isDirectory: true)),
            HomeFolderShortcut(name: "Pictures", url: home.appendingPathComponent("Pictures", isDirectory: true)),
            HomeFolderShortcut(name: "Movies", url: home.appendingPathComponent("Movies", isDirectory: true)),
            HomeFolderShortcut(name: "Music", url: home.appendingPathComponent("Music", isDirectory: true)),
            HomeFolderShortcut(name: "Applications", url: URL(fileURLWithPath: "/Applications", isDirectory: true)),
        ]
    }()

    /// Walks LaunchpadEntry, expanding virtual folders into their apps so
    /// the Start menu's flat grid mirrors Launchpad's full coverage of
    /// /Applications, /System/Applications, and ~/Applications.
    private static func flattened(_ entries: [LaunchpadEntry]) -> [AppTile] {
        var apps: [AppTile] = []
        apps.reserveCapacity(entries.count)
        for entry in entries {
            switch entry {
            case .app(let app):
                apps.append(app)
            case .folder(let folder):
                apps.append(contentsOf: folder.apps)
            }
        }
        return apps
    }

    var body: some View {
        HStack(spacing: 8) {
            mainPanel
            sidePanel
                .opacity(service.showsAllApps ? 1 : 0)
                .scaleEffect(service.showsAllApps ? 1 : 0.97, anchor: .leading)
                .allowsHitTesting(service.showsAllApps)
        }
        .animation(.easeInOut(duration: 0.18), value: service.showsAllApps)
        .onAppear { searchFocused = true }
    }

    private var mainPanel: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            // Glass + window tint + gradient stroke, layered in the same
            // order the dock's `chromeBackground` uses so the Start menu
            // tracks any tint color or opacity the user picks for the
            // dock chrome.
            Color.clear
                .dockyGlass(in: shape)
                .overlay {
                    shape.fill(Color(nsColor: preferences.effectiveWindowTintColor))
                        .opacity(preferences.effectiveWindowTintOpacity)
                }
                .dockyGlassBorder(in: shape)

            VStack(spacing: 0) {
                searchField
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        recentsSection
                        homeSection
                        appsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                Divider()
                footer
            }
        }
        .frame(width: mainWidth)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }

    private var sidePanel: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            Color.clear
                .dockyGlass(in: shape)
                .overlay {
                    shape.fill(Color(nsColor: preferences.effectiveWindowTintColor))
                        .opacity(preferences.effectiveWindowTintOpacity)
                }
                .dockyGlassBorder(in: shape)

            allAppsSidePanel
        }
        .frame(width: allAppsWidth)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14, weight: .medium))
            TextField("Search apps and recent files", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var homeSection: some View {
        let items = filteredHomeFolders
        if !items.isEmpty {
            sectionHeader("Home")
            let columns = [GridItem(.adaptive(minimum: 88, maximum: 110), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(items) { folder in
                    homeFolderCell(folder)
                }
            }
        }
    }

    private func homeFolderCell(_ folder: HomeFolderShortcut) -> some View {
        Button {
            NSWorkspace.shared.open(folder.url)
            StartMenuService.shared.dismiss()
        } label: {
            VStack(spacing: 6) {
                Image(nsImage: IconCacheService.shared.icon(forFileURL: folder.url))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                Text(folder.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var recentsSection: some View {
        let items = Array(filteredRecents.prefix(8))
        if !items.isEmpty {
            sectionHeader("Recents")
            VStack(spacing: 4) {
                ForEach(items, id: \.self) { url in
                    recentRow(url: url)
                }
            }
        }
    }

    @ViewBuilder
    private var appsSection: some View {
        let apps = appsSectionTiles
        if !apps.isEmpty {
            appsSectionHeader
            let columns = [GridItem(.adaptive(minimum: 88, maximum: 110), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(apps, id: \.bundleIdentifier) { app in
                    appCell(app)
                }
            }
        }
    }

    /// Recent Apps header with a trailing "Show All" button that opens
    /// the side panel. Hidden while the user is searching (the section
    /// already shows all matching apps in that case).
    private var appsSectionHeader: some View {
        HStack(spacing: 8) {
            Text(appsSectionTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 0)
            if query.isEmpty {
                Button {
                    service.showsAllApps.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text(service.showsAllApps ? "Hide" : "Show All")
                        Image(systemName: service.showsAllApps ? "chevron.left" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private var allAppsSidePanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("All Apps")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                Button {
                    service.showsAllApps = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(allAppsAlphabetical, id: \.bundleIdentifier) { app in
                        allAppsRow(app)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
    }

    private func allAppsRow(_ app: AppTile) -> some View {
        Button {
            launch(app)
            StartMenuService.shared.dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: IconCacheService.shared.displayedIcon(forBundleIdentifier: app.bundleIdentifier))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                Text(app.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// All apps from Launchpad's scan, alphabetised. Search filtering is
    /// applied so typing into the main search field also narrows this
    /// list down.
    private var allAppsAlphabetical: [AppTile] {
        let sorted = Self.flattened(launchpad.entries).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func recentRow(url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
            StartMenuService.shared.dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(nsImage: IconCacheService.shared.icon(forFileURL: url))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 14))
                        .lineLimit(1)
                    Text(url.deletingLastPathComponent().path)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func appCell(_ app: AppTile) -> some View {
        Button {
            launch(app)
            StartMenuService.shared.dismiss()
        } label: {
            VStack(spacing: 6) {
                Image(nsImage: IconCacheService.shared.displayedIcon(forBundleIdentifier: app.bundleIdentifier))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 52, height: 52)
                Text(app.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func launch(_ app: AppTile) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Spacer()
            Button {
                (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
                StartMenuService.shared.dismiss()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Docky Settings")

            Menu {
                Button(SystemAction.sleep.title) { SystemAction.sleep.perform() }
                Button(SystemAction.restart.title) { SystemAction.restart.perform() }
                Button(SystemAction.shutDown.title) { SystemAction.shutDown.perform() }
                Divider()
                Button(SystemAction.logOut.title) { SystemAction.logOut.perform() }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct HomeFolderShortcut: Identifiable, Hashable {
    let name: String
    let url: URL
    var id: URL { url }
}

/// Power menu actions. Dispatched as AppleEvents to `loginwindow`, which
/// is the same channel the Apple menu's Sleep/Restart/Shut Down items use.
/// No automation permission required, the system surfaces its own
/// confirmation dialogs when it needs them.
private enum SystemAction {
    case sleep
    case restart
    case shutDown
    case logOut

    var title: String {
        switch self {
        case .sleep: return "Sleep"
        case .restart: return "Restart..."
        case .shutDown: return "Shut Down..."
        case .logOut: return "Log Out..."
        }
    }

    private var eventID: AEEventID {
        switch self {
        case .sleep: return AEEventID(kAESleep)
        case .restart: return AEEventID(kAERestart)
        case .shutDown: return AEEventID(kAEShutDown)
        case .logOut: return AEEventID(kAEReallyLogOut)
        }
    }

    func perform() {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: eventID,
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        _ = try? event.sendEvent(options: [.noReply], timeout: 2)
    }
}
