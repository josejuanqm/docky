//
//  WorkspaceService.swift
//  Docky
//
//  Observes NSWorkspace for live workspace state. First pass: running apps
//  (regular activation policy only, background agents and menu-bar-only
//  apps are filtered out since they don't belong in a dock). Running apps
//  are exposed in a stable order: still-running apps keep their position,
//  newly-launched apps append to the end. Designed to grow: frontmost app,
//  space changes, display changes, etc. can land here as new @Published
//  properties.
//

import AppKit
import ApplicationServices
import Combine
import CoreImage
import CoreMedia
import ScreenCaptureKit

enum AppFolderTileLayout {
    case leftRight, rightLeft, topBottom, bottomTop, quarters
}

struct RunningApp: Hashable, Identifiable {
    let bundleIdentifier: String
    let localizedName: String
    let processIdentifier: pid_t
    let bundleURL: URL?
    let launchDate: Date?
    let isHidden: Bool

    var id: String { bundleIdentifier }
}

final class WorkspaceService: ObservableObject {
    static let shared = WorkspaceService()

    /// Ordered list: still-running apps keep their position across refreshes,
    /// newly-launched apps append. Terminated apps are removed in place.
    @Published private(set) var runningApps: [RunningApp] = []
    @Published private(set) var minimizedWindows: [AppWindow] = []
    @Published private(set) var minimizedWindowPreviews: [String: NSImage] = [:]
    @Published private(set) var appWindowPreviews: [String: NSImage] = [:]
    /// Bundle identifier of the app that currently owns the system
    /// activation (foreground), or `nil` when nothing is frontmost
    /// (rare, typically transient during space switches).
    @Published private(set) var frontmostBundleIdentifier: String?

    private var runningByBundleID: [String: RunningApp] = [:]

    var runningBundleIdentifiers: Set<String> { Set(runningByBundleID.keys) }

    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var attemptedMinimizedWindowPreviewIDs: Set<String> = []
    private var attemptedAppWindowPreviewIDs: Set<String> = []
    private var liveFocusPreviewSession: LiveWindowPreviewSession?

    /// Backstop refresh interval for app-window thumbnails. Title-change
    /// invalidation handles the common case (browsers, IDEs); this catches
    /// content-only changes (editor scroll, in-page navigation) where the
    /// title stays put but the cached thumb no longer represents the window.
    private let appWindowPreviewTTL: TimeInterval = 120
    private struct PreviewMetadata {
        let capturedAt: Date
        let capturedTitle: String
    }
    private var appWindowPreviewMetadata: [String: PreviewMetadata] = [:]

    private init() {
        refresh()
        subscribe()
        subscribeToPermissions()
        subscribeToRegistry()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    func isRunning(bundleIdentifier: String) -> Bool {
        runningByBundleID[bundleIdentifier] != nil
    }

    func isFrontmost(bundleIdentifier: String) -> Bool {
        frontmostBundleIdentifier == bundleIdentifier
    }

    func isHidden(bundleIdentifier: String) -> Bool {
        runningByBundleID[bundleIdentifier]?.isHidden == true
    }

    func minimizedWindowPreview(for window: AppWindow) -> NSImage? {
        minimizedWindowPreviews[window.windowIdentifier]
    }

    func activateOrOpen(bundleIdentifier: String) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            // Not running: launch it.
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                openApplication(at: appURL)
            }
            return
        }

        let accessibilityGranted = PermissionsService.shared.accessibility == .granted
        let allWindows = accessibilityGranted ? appWindows(bundleIdentifier: bundleIdentifier) : []
        let visibleWindows = allWindows.filter { !$0.isMinimized }
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
            && !runningApp.isHidden

        // Running but no AX windows: spawn a new window.
        if accessibilityGranted, allWindows.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            openApplication(at: appURL)
            return
        }

        // Running but every window is minimized: restore the most-recently-minimized.
        if accessibilityGranted, visibleWindows.isEmpty, !allWindows.isEmpty,
           let lastMinimized = minimizedWindows.last(where: { $0.bundleIdentifier == bundleIdentifier }) {
            _ = restoreMinimizedWindow(lastMinimized)
            return
        }

        // Already frontmost with at least one visible window: apply user preference.
        if isFrontmost, !visibleWindows.isEmpty {
            applyFrontmostAppTileClickBehavior(
                runningApp: runningApp,
                visibleWindows: visibleWindows
            )
            return
        }

        // Default: bring the app forward.
        runningApp.unhide()
        runningApp.activate(options: [.activateAllWindows])
    }

    private func applyFrontmostAppTileClickBehavior(
        runningApp: NSRunningApplication,
        visibleWindows: [AppWindow]
    ) {
        let preference = DockyPreferences.shared.appTileFrontmostClickBehavior
        let resolved: AppTileFrontmostClickBehavior = {
            guard preference.requiresPro else { return preference }
            return ProductService.shared.currentTier == .pro ? preference : .none
        }()

        switch resolved {
        case .none:
            return
        case .hide:
            runningApp.hide()
        case .cycleWindows:
            cycleFrontmostAppWindows(visibleWindows)
        case .minimizeAll:
            minimizeAllWindows(visibleWindows)
        }
    }

    private func cycleFrontmostAppWindows(_ visibleWindows: [AppWindow]) {
        // appWindows() returns front-to-back order from AXWindows; raising index 1
        // promotes the next window beneath the frontmost.
        guard visibleWindows.count > 1 else { return }
        _ = focus(window: visibleWindows[1])
    }

    private func minimizeAllWindows(_ visibleWindows: [AppWindow]) {
        for window in visibleWindows {
            _ = minimize(window: window)
        }
    }

    func open(fileURLs: [URL], withApplicationBundleIdentifier bundleIdentifier: String) {
        guard !fileURLs.isEmpty,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(fileURLs, withApplicationAt: appURL, configuration: configuration) { _, error in
            guard let error else {
                return
            }

            NSLog("[Docky] Failed to open dropped files with app %@: %@ (%@)", bundleIdentifier, fileURLs.map(\.path).joined(separator: ", "), error.localizedDescription)
        }
    }

    func appWindows(bundleIdentifier: String) -> [AppWindow] {
        WindowRegistry.shared.windows(forBundleIdentifier: bundleIdentifier)
    }

    func switchableWindows(forceRefresh: Bool = false) -> [AppWindow] {
        // Registry is event-driven; the cached snapshot is always fresh, so
        // `forceRefresh` is now a no-op kept for source-compat.
        _ = forceRefresh
        return WindowRegistry.shared.visible
    }

    func appWindowPreview(for window: AppWindow) -> NSImage? {
        appWindowPreviews[window.windowIdentifier]
    }

    func liveFocusPreviewImage(for window: AppWindow) async -> NSImage? {
        guard PermissionsService.shared.screenCapture == .granted else {
            return appWindowPreviews[window.windowIdentifier]
        }

        if let cgWindowID = window.cgWindowID,
           let cgImage = CGWindowListCreateImagePrivate(
               .null,
               [.optionIncludingWindow],
               cgWindowID,
               [.boundsIgnoreFraming, .bestResolution]
           ) {
            return makeFullSizeImage(from: cgImage)
        }

        return await captureFullSizeAppWindowImage(for: window) ?? appWindowPreviews[window.windowIdentifier]
    }

    func startLiveFocusPreview(
        for window: AppWindow,
        onFrame: @escaping @MainActor (NSImage?) -> Void
    ) async -> Bool {
        stopLiveFocusPreview()

        guard PermissionsService.shared.screenCapture == .granted else {
            return false
        }

        do {
            let shareableContent = try await shareableContentIncludingOffscreenWindows()
            guard let shareableWindow = matchingShareableWindow(for: window, in: shareableContent.windows) else {
                return false
            }

            let session = LiveWindowPreviewSession(
                shareableWindow: shareableWindow,
                captureSize: fullSizeCaptureSize(for: shareableWindow.frame.size, screenBounds: window.screenBounds),
                onFrame: onFrame
            )
            try await session.start()
            liveFocusPreviewSession = session
            return true
        } catch {
            NSLog("[Docky] Live focus preview stream failed for \(window.windowIdentifier): \(error.localizedDescription)")
            liveFocusPreviewSession = nil
            return false
        }
    }

    func stopLiveFocusPreview() {
        liveFocusPreviewSession?.stop()
        liveFocusPreviewSession = nil
    }

    @discardableResult
    func focus(window: AppWindow) -> Bool {
        WindowRegistry.shared.focus(window)
    }

    func focusApplication(bundleIdentifier: String) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return
        }

        runningApp.unhide()
        _ = runningApp.activate()
    }

    @discardableResult
    func minimize(window: AppWindow) -> Bool {
        WindowRegistry.shared.minimize(window)
    }

    @discardableResult
    func close(window: AppWindow) -> Bool {
        WindowRegistry.shared.close(window)
    }

    // MARK: - Window geometry actions

    @discardableResult
    func zoom(window: AppWindow) -> Bool {
        let ok = WindowRegistry.shared.zoom(window)
        if ok { _ = focus(window: window) }
        return ok
    }

    @discardableResult
    func fill(window: AppWindow) -> Bool {
        guard let screen = currentScreen(for: window) else { return false }
        let ok = resize(window, toNSFrame: screen.visibleFrame)
        if ok { _ = focus(window: window) }
        return ok
    }

    @discardableResult
    func center(window: AppWindow) -> Bool {
        guard let screen = currentScreen(for: window),
              let size = window.frame?.size, size.width > 0, size.height > 0 else {
            return false
        }
        let v = screen.visibleFrame
        let target = CGRect(
            x: v.midX - size.width / 2,
            y: v.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let ok = resize(window, toNSFrame: target)
        if ok { _ = focus(window: window) }
        return ok
    }

    @discardableResult
    func fillLeftHalf(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height)
        }
    }

    @discardableResult
    func fillRightHalf(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height)
        }
    }

    @discardableResult
    func fillTopHalf(window: AppWindow) -> Bool {
        // NSScreen Y grows upward; "top half" sits at higher Y.
        fillRect(of: window) { v in
            CGRect(x: v.minX, y: v.midY, width: v.width, height: v.height / 2)
        }
    }

    @discardableResult
    func fillBottomHalf(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height / 2)
        }
    }

    @discardableResult
    func fillTopLeftQuarter(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.minX, y: v.midY, width: v.width / 2, height: v.height / 2)
        }
    }

    @discardableResult
    func fillTopRightQuarter(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.midX, y: v.midY, width: v.width / 2, height: v.height / 2)
        }
    }

    @discardableResult
    func fillBottomLeftQuarter(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height / 2)
        }
    }

    @discardableResult
    func fillBottomRightQuarter(window: AppWindow) -> Bool {
        fillRect(of: window) { v in
            CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height / 2)
        }
    }

    private func fillRect(of window: AppWindow, _ make: (CGRect) -> CGRect) -> Bool {
        guard let screen = currentScreen(for: window) else { return false }
        let ok = resize(window, toNSFrame: make(screen.visibleFrame))
        if ok { _ = focus(window: window) }
        return ok
    }

    /// Tiles up to four windows on the screen of the first window (the
    /// "anchor"). Order matters: the first window in `windows` takes the
    /// first-named position in the layout (e.g., for `.leftRight`, windows[0]
    /// is the left half). Caller is expected to pass windows in the order
    /// the user understands as "first" (typically WindowRegistry MRU).
    @discardableResult
    func tile(windows: [AppWindow], layout: AppFolderTileLayout) -> Bool {
        guard windows.count >= 2,
              let screen = currentScreen(for: windows[0]) else { return false }
        let v = screen.visibleFrame
        let leftHalf = CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height)
        let rightHalf = CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height)
        let topHalf = CGRect(x: v.minX, y: v.midY, width: v.width, height: v.height / 2)
        let bottomHalf = CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height / 2)
        let quarters: [CGRect] = [
            CGRect(x: v.minX, y: v.midY, width: v.width / 2, height: v.height / 2), // TL
            CGRect(x: v.midX, y: v.midY, width: v.width / 2, height: v.height / 2), // TR
            CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height / 2), // BL
            CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height / 2), // BR
        ]

        let placements: [(AppWindow, CGRect)]
        switch layout {
        case .leftRight:
            placements = [(windows[0], leftHalf), (windows[1], rightHalf)]
        case .rightLeft:
            placements = [(windows[0], rightHalf), (windows[1], leftHalf)]
        case .topBottom:
            placements = [(windows[0], topHalf), (windows[1], bottomHalf)]
        case .bottomTop:
            placements = [(windows[0], bottomHalf), (windows[1], topHalf)]
        case .quarters:
            let n = min(windows.count, 4)
            placements = (0..<n).map { (windows[$0], quarters[$0]) }
        }

        var allOk = true
        for (window, frame) in placements {
            allOk = resize(window, toNSFrame: frame) && allOk
        }
        // Surface every tiled window, windows on inactive Spaces won't be
        // visible after resize until SLPS pulls them forward. Focus in order
        // so the first-in-the-layout-name window ends up frontmost / key.
        for (window, _) in placements.reversed() {
            _ = focus(window: window)
        }
        return allOk
    }

    /// Routes an NSScreen-space target rect through the AX-space (Y-flipped
    /// against the primary display) coordinates that `WindowRegistry.resize`
    /// expects. Same flip used by `WindowReservationService`.
    private func resize(_ window: AppWindow, toNSFrame nsFrame: CGRect) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return false }
        let axFrame = CGRect(
            x: nsFrame.minX,
            y: primaryHeight - nsFrame.maxY,
            width: nsFrame.width,
            height: nsFrame.height
        )
        return WindowRegistry.shared.resize(window, to: axFrame)
    }

    /// Picks the NSScreen the window mostly occupies. Falls back to the main
    /// screen when AX has no frame for the window (some apps return zero).
    private func currentScreen(for window: AppWindow) -> NSScreen? {
        guard let axFrame = window.frame,
              let primaryHeight = NSScreen.screens.first?.frame.height else {
            return NSScreen.main
        }
        let nsFrame = CGRect(
            x: axFrame.minX,
            y: primaryHeight - axFrame.maxY,
            width: axFrame.width,
            height: axFrame.height
        )
        var best: (screen: NSScreen, area: CGFloat)?
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(nsFrame)
            let area = intersection.width * intersection.height
            if area > 0, area > (best?.area ?? 0) {
                best = (screen, area)
            }
        }
        return best?.screen ?? NSScreen.main
    }

    private func openApplication(at appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    func revealApplicationInFinder(bundleIdentifier: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }

    func showAllWindows(bundleIdentifier: String) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return
        }

        runningApp.unhide()
        _ = runningApp.activate()
        // The Dock targets App Exposé at whatever app is frontmost when the
        // call arrives. The small delay lets activation land first so Exposé
        // surfaces the correct app's windows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            CoreDockSendNotification("com.apple.expose.front.awake")
        }
    }

    @discardableResult
    func restoreMinimizedWindow(_ window: AppWindow) -> Bool {
        WindowRegistry.shared.focus(window)
    }

    @discardableResult
    func closeMinimizedWindow(_ window: AppWindow) -> Bool {
        WindowRegistry.shared.close(window)
    }

    func hide(bundleIdentifier: String) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return
        }

        runningApp.hide()
    }

    func quit(bundleIdentifier: String, force: Bool = false) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return
        }

        if force {
            runningApp.forceTerminate()
        } else {
            runningApp.terminate()
        }
    }

    func refresh() {
        // Docky is invisible to itself: filtering at this source removes
        // it from every downstream surface (dock tiles, settings pickers,
        // grouped running apps in folders, etc.) without needing per-site
        // exclusions. Matched by bundle ID so debug launches from Xcode
        // are filtered too.
        let dockyBundleID = Bundle.main.bundleIdentifier
        let regular = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != dockyBundleID
        }
        var newMap: [String: RunningApp] = [:]
        for app in regular {
            guard let bundleID = app.bundleIdentifier else { continue }
            newMap[bundleID] = RunningApp(
                bundleIdentifier: bundleID,
                localizedName: app.localizedName ?? bundleID,
                processIdentifier: app.processIdentifier,
                bundleURL: app.bundleURL,
                launchDate: app.launchDate,
                isHidden: app.isHidden
            )
        }

        let ordered = newMap.values.sorted(by: Self.byLaunchDate)

        runningByBundleID = newMap
        if runningApps != ordered {
            runningApps = ordered
        }
        refreshWindowDerivedState()
    }

    /// Oldest → newest. Apps without a launchDate (rare; system apps launched
    /// before our process) are treated as oldest. Bundle identifier is used
    /// as a deterministic tiebreaker.
    nonisolated private static func byLaunchDate(_ lhs: RunningApp, _ rhs: RunningApp) -> Bool {
        switch (lhs.launchDate, rhs.launchDate) {
        case let (l?, r?):
            return l == r
                ? lhs.bundleIdentifier < rhs.bundleIdentifier
                : l < r
        case (nil, _?): return true
        case (_?, nil): return false
        case (nil, nil): return lhs.bundleIdentifier < rhs.bundleIdentifier
        }
    }

    private func subscribe() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            let token = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
            observers.append(token)
        }

        // Track the frontmost (foreground) app independently of the
        // running-apps list so the "active tile background" can paint
        // under just the focused tile, not every running one.
        let frontmostToken = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.updateFrontmost(app ?? NSWorkspace.shared.frontmostApplication)
        }
        observers.append(frontmostToken)

        // Seed once so the first render after launch already reflects
        // whichever app was foreground when Docky came up.
        updateFrontmost(NSWorkspace.shared.frontmostApplication)
    }

    private func updateFrontmost(_ app: NSRunningApplication?) {
        let next = app?.bundleIdentifier
        guard next != frontmostBundleIdentifier else { return }
        frontmostBundleIdentifier = next
    }

    private func subscribeToPermissions() {
        PermissionsService.shared.$screenCapture
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshWindowDerivedState()
            }
            .store(in: &cancellables)
    }

    /// Mirrors the registry's window list into the published `minimizedWindows`
    /// array and drives preview captures. Called whenever the registry's
    /// snapshot, the running-apps list, or the screen-capture permission
    /// changes.
    ///
    /// Also re-runs the full `refresh()` so the published running-apps list
    /// catches apps whose `activationPolicy` promotes to `.regular` *after*
    /// `didLaunchApplicationNotification` (some apps launch as `.prohibited`
    /// or `.accessory` and only become dock-eligible once their first
    /// window appears). The `runningApps` setter is diff-guarded so this
    /// extra pass costs nothing when no app changed eligibility.
    private func subscribeToRegistry() {
        WindowRegistry.shared.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    private func refreshWindowDerivedState() {
        let registry = WindowRegistry.shared
        let nextMinimized = registry.minimized
        if nextMinimized != minimizedWindows {
            minimizedWindows = nextMinimized
        }
        refreshMinimizedWindowPreviews(for: nextMinimized)
        refreshAppWindowPreviews(for: registry.visible)
    }

    private func refreshMinimizedWindowPreviews(for windows: [AppWindow]) {
        guard PermissionsService.shared.screenCapture == .granted else {
            if !minimizedWindowPreviews.isEmpty {
                minimizedWindowPreviews = [:]
            }
            attemptedMinimizedWindowPreviewIDs = []
            return
        }

        let activeWindowIdentifiers = Set(windows.map(\.windowIdentifier))
        var updatedPreviews = minimizedWindowPreviews
        var didChange = false

        for windowIdentifier in updatedPreviews.keys where !activeWindowIdentifiers.contains(windowIdentifier) {
            updatedPreviews.removeValue(forKey: windowIdentifier)
            didChange = true
        }

        attemptedMinimizedWindowPreviewIDs = attemptedMinimizedWindowPreviewIDs.intersection(activeWindowIdentifiers)

        for window in windows {
            guard updatedPreviews[window.windowIdentifier] == nil,
                  !attemptedMinimizedWindowPreviewIDs.contains(window.windowIdentifier) else {
                continue
            }

            attemptedMinimizedWindowPreviewIDs.insert(window.windowIdentifier)
            captureMinimizedWindowPreviewIfNeeded(for: window)
        }

        if didChange {
            minimizedWindowPreviews = updatedPreviews
        }
    }

    private func captureMinimizedWindowPreviewIfNeeded(for window: AppWindow) {
        Task { [weak self] in
            guard let self,
                  let preview = await self.captureMinimizedWindowPreview(for: window) else {
                return
            }

            guard self.minimizedWindows.contains(where: { $0.windowIdentifier == window.windowIdentifier }),
                  self.minimizedWindowPreviews[window.windowIdentifier] == nil else {
                return
            }

            var updatedPreviews = self.minimizedWindowPreviews
            updatedPreviews[window.windowIdentifier] = preview
            self.minimizedWindowPreviews = updatedPreviews
        }
    }

    private func refreshAppWindowPreviews(for windows: [AppWindow]) {
        // App-window preview thumbnails are only consumed by Pro
        // features (`WindowSwitcherService`, `WindowPreviewService`),
        // both of which already gate reads on
        // `ProductService.isUnlocked(.windowSwitcher)`. Skipping the
        // capture on the producer side keeps free users out of the
        // screen-capture path entirely — saving CPU/GPU and avoiding
        // private-API code paths they can't even surface.
        guard ProductService.shared.isUnlocked(.windowSwitcher),
              PermissionsService.shared.screenCapture == .granted else {
            if !appWindowPreviews.isEmpty {
                appWindowPreviews = [:]
            }
            appWindowPreviewMetadata.removeAll()
            attemptedAppWindowPreviewIDs = []
            return
        }

        let activeWindowIdentifiers = Set(windows.map(\.windowIdentifier))
        let windowsByIdentifier = DataIntegrityReporter.makeDictionary(
            windows.map { ($0.windowIdentifier, $0) },
            site: "WorkspaceService.refreshAppWindowPreviews.windowsByIdentifier"
        )
        var updatedPreviews = appWindowPreviews
        var didChange = false
        let now = Date()

        for windowIdentifier in updatedPreviews.keys where !activeWindowIdentifiers.contains(windowIdentifier) {
            updatedPreviews.removeValue(forKey: windowIdentifier)
            appWindowPreviewMetadata.removeValue(forKey: windowIdentifier)
            didChange = true
        }

        // Evict cached previews whose source window's title changed or whose
        // age exceeded the TTL, the cached image is no longer representative.
        let staleIdentifiers: [String] = appWindowPreviewMetadata.compactMap { id, metadata in
            guard let window = windowsByIdentifier[id] else { return nil }
            let titleChanged = metadata.capturedTitle != window.windowTitle
            let expired = now.timeIntervalSince(metadata.capturedAt) > appWindowPreviewTTL
            return (titleChanged || expired) ? id : nil
        }
        for identifier in staleIdentifiers {
            updatedPreviews.removeValue(forKey: identifier)
            appWindowPreviewMetadata.removeValue(forKey: identifier)
            attemptedAppWindowPreviewIDs.remove(identifier)
            didChange = true
        }

        attemptedAppWindowPreviewIDs = attemptedAppWindowPreviewIDs.intersection(activeWindowIdentifiers)
        var windowsToCapture: [AppWindow] = []

        for window in windows {
            guard updatedPreviews[window.windowIdentifier] == nil,
                  !attemptedAppWindowPreviewIDs.contains(window.windowIdentifier) else {
                continue
            }

            attemptedAppWindowPreviewIDs.insert(window.windowIdentifier)
            windowsToCapture.append(window)
        }

        if didChange {
            appWindowPreviews = updatedPreviews
        }

        captureAppWindowPreviewsIfNeeded(for: windowsToCapture)
    }

    private func captureAppWindowPreviewsIfNeeded(for windows: [AppWindow]) {
        guard !windows.isEmpty else {
            return
        }

        Task { [weak self] in
            guard let self else { return }

            let shareableContentCache = ShareableContentCache()
            for window in windows {
                guard self.appWindowPreviews[window.windowIdentifier] == nil,
                      let preview = await self.captureAppWindowPreview(
                          for: window,
                          shareableContentCache: shareableContentCache
                      ) else {
                    continue
                }

                guard self.appWindowPreviews[window.windowIdentifier] == nil else {
                    continue
                }

                var updatedPreviews = self.appWindowPreviews
                updatedPreviews[window.windowIdentifier] = preview
                self.appWindowPreviews = updatedPreviews
                self.appWindowPreviewMetadata[window.windowIdentifier] = PreviewMetadata(
                    capturedAt: Date(),
                    capturedTitle: window.windowTitle
                )
            }
        }
    }

    private func captureAppWindowPreview(
        for window: AppWindow,
        shareableContentCache: ShareableContentCache? = nil
    ) async -> NSImage? {
        guard PermissionsService.shared.screenCapture == .granted else {
            return nil
        }

        if let windowNumber = window.windowNumber,
           let cgImage = CGWindowListCreateImagePrivate(
               .null,
               [.optionIncludingWindow],
               CGWindowID(windowNumber),
               [.boundsIgnoreFraming, .bestResolution]
           ) {
            return makeThumbnail(from: cgImage, maxSize: CGSize(width: 480, height: 300))
        }

        do {
            let shareableContent: SCShareableContent
            if let shareableContentCache {
                if let cachedContent = shareableContentCache.content {
                    shareableContent = cachedContent
                } else {
                    let fetchedContent = try await shareableContentIncludingOffscreenWindows()
                    shareableContentCache.content = fetchedContent
                    shareableContent = fetchedContent
                }
            } else {
                shareableContent = try await shareableContentIncludingOffscreenWindows()
            }

            guard let shareableWindow = matchingShareableWindow(for: window, in: shareableContent.windows) else {
                NSLog(
                    "[Docky] App window preview: no shareable window for \(window.windowIdentifier) title=\(window.windowTitle) totalShareableWindows=\(shareableContent.windows.count)"
                )
                return nil
            }

            if let cgImage = CGWindowListCreateImagePrivate(
                .null,
                [.optionIncludingWindow],
                shareableWindow.windowID,
                [.boundsIgnoreFraming, .bestResolution]
            ) {
                return makeThumbnail(from: cgImage, maxSize: CGSize(width: 480, height: 300))
            }

            let configuration = SCStreamConfiguration()
            let captureSize = constrainedCaptureSize(for: shareableWindow.frame.size)
            configuration.width = Int(captureSize.width)
            configuration.height = Int(captureSize.height)
            configuration.capturesAudio = false
            if FeatureGate.shared.isAvailable(.streamMicrophoneCapture), #available(macOS 15.0, *) {
                configuration.captureMicrophone = false
            }
            configuration.showsCursor = false
            configuration.scalesToFit = true
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true

            let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
            let cgImage = try await captureImage(contentFilter: filter, configuration: configuration)
            return makeThumbnail(from: cgImage, maxSize: CGSize(width: 480, height: 300))
        } catch {
            NSLog("[Docky] App window preview capture failed for \(window.windowIdentifier): \(error.localizedDescription)")
            return nil
        }
    }

    private func captureFullSizeAppWindowImage(for window: AppWindow) async -> NSImage? {
        guard PermissionsService.shared.screenCapture == .granted else {
            return nil
        }

        do {
            let shareableContent = try await shareableContentIncludingOffscreenWindows()
            guard let shareableWindow = matchingShareableWindow(for: window, in: shareableContent.windows) else {
                return nil
            }

            let configuration = SCStreamConfiguration()
            let captureSize = fullSizeCaptureSize(for: shareableWindow.frame.size, screenBounds: window.screenBounds)
            configuration.width = Int(captureSize.width)
            configuration.height = Int(captureSize.height)
            configuration.capturesAudio = false
            if FeatureGate.shared.isAvailable(.streamMicrophoneCapture), #available(macOS 15.0, *) {
                configuration.captureMicrophone = false
            }
            configuration.showsCursor = false
            configuration.scalesToFit = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true

            let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
            let cgImage = try await captureImage(contentFilter: filter, configuration: configuration)
            return makeFullSizeImage(from: cgImage)
        } catch {
            NSLog("[Docky] Live focus preview capture failed for \(window.windowIdentifier): \(error.localizedDescription)")
            return nil
        }
    }

    private func captureMinimizedWindowPreview(for window: AppWindow) async -> NSImage? {
        guard PermissionsService.shared.screenCapture == .granted else {
            return nil
        }

        do {
            let shareableContent = try await shareableContentIncludingOffscreenWindows()
            guard let shareableWindow = matchingShareableWindow(for: window, in: shareableContent.windows) else {
                NSLog(
                    "[Docky] Minimized window preview: no shareable window for \(window.windowIdentifier) title=\(window.windowTitle) totalShareableWindows=\(shareableContent.windows.count)"
                )
                return nil
            }

            if let cgImage = CGWindowListCreateImagePrivate(
                .null,
                [.optionIncludingWindow],
                shareableWindow.windowID,
                [.boundsIgnoreFraming, .bestResolution]
            ) {
                return makeThumbnail(from: cgImage, maxSize: CGSize(width: 320, height: 200))
            }

            let configuration = SCStreamConfiguration()
            let captureSize = constrainedCaptureSize(for: shareableWindow.frame.size)
            configuration.width = Int(captureSize.width)
            configuration.height = Int(captureSize.height)
            configuration.capturesAudio = false
            if FeatureGate.shared.isAvailable(.streamMicrophoneCapture), #available(macOS 15.0, *) {
                configuration.captureMicrophone = false
            }
            configuration.showsCursor = false
            configuration.scalesToFit = true
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true

            let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
            let cgImage = try await captureImage(contentFilter: filter, configuration: configuration)
            return makeThumbnail(from: cgImage, maxSize: CGSize(width: 320, height: 200))
        } catch {
            NSLog("[Docky] Minimized window preview capture failed for \(window.windowIdentifier): \(error.localizedDescription)")
            return nil
        }
    }

    private func matchingShareableWindow(for window: AppWindow, in windows: [SCWindow]) -> SCWindow? {
        if let windowNumber = window.windowNumber,
           let exactMatch = windows.first(where: { Int($0.windowID) == windowNumber }) {
            return exactMatch
        }

        let candidates = windows.filter { shareableWindow in
            guard let owningApplication = shareableWindow.owningApplication else {
                return false
            }

            return owningApplication.processID == window.processIdentifier
                || owningApplication.bundleIdentifier == window.bundleIdentifier
        }

        let titledCandidates = candidates.filter { shareableWindow in
            normalizedWindowTitle(shareableWindow.title) == normalizedWindowTitle(window.windowTitle)
        }

        // Fallback index: position of `window` within its app's window list.
        // The registry maintains stable ordering, so this is consistent across
        // calls within a process run.
        let lookupIndex = WindowRegistry.shared
            .windows(forBundleIdentifier: window.bundleIdentifier)
            .firstIndex(where: { $0.id == window.id }) ?? 0

        if titledCandidates.indices.contains(lookupIndex) {
            return titledCandidates[lookupIndex]
        }

        if let titleMatch = titledCandidates.first {
            return titleMatch
        }

        if candidates.indices.contains(lookupIndex) {
            return candidates[lookupIndex]
        }

        return candidates.first
    }

    private func normalizedWindowTitle(_ title: String?) -> String {
        (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shareableContentIncludingOffscreenWindows() async throws -> SCShareableContent {
        try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let content else {
                    continuation.resume(throwing: NSError(domain: "Docky.WindowPreview", code: -2, userInfo: nil))
                    return
                }

                continuation.resume(returning: content)
            }
        }
    }

    private func constrainedCaptureSize(for sourceSize: CGSize) -> CGSize {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGSize(width: 320, height: 200)
        }

        let maxSize = CGSize(width: 640, height: 400)
        let scale = min(maxSize.width / sourceSize.width, maxSize.height / sourceSize.height, 1)
        return CGSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )
    }

    private func fullSizeCaptureSize(for sourceSize: CGSize, screenBounds: CGRect?) -> CGSize {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGSize(width: 1, height: 1)
        }

        let scaleFactor = backingScaleFactor(for: screenBounds)

        return CGSize(
            width: max(1, ceil(sourceSize.width * scaleFactor)),
            height: max(1, ceil(sourceSize.height * scaleFactor))
        )
    }

    private func backingScaleFactor(for screenBounds: CGRect?) -> CGFloat {
        guard let screenBounds else {
            return NSScreen.main?.backingScaleFactor ?? 2
        }

        let bestScreen = NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.frame, with: screenBounds) < intersectionArea(rhs.frame, with: screenBounds)
        }

        return bestScreen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func intersectionArea(_ lhs: CGRect, with rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else {
            return 0
        }

        return intersection.width * intersection.height
    }

    private func captureImage(
        contentFilter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image else {
                    continuation.resume(throwing: NSError(domain: "Docky.WindowPreview", code: -1, userInfo: nil))
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }

    private func makeThumbnail(from cgImage: CGImage, maxSize: CGSize) -> NSImage? {
        guard cgImage.width > 0, cgImage.height > 0 else {
            return nil
        }

        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = min(maxSize.width / sourceSize.width, maxSize.height / sourceSize.height, 1)
        let thumbnailSize = CGSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )

        let sourceImage = NSImage(cgImage: cgImage, size: sourceSize)
        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        defer { thumbnail.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        sourceImage.draw(
            in: NSRect(origin: .zero, size: thumbnailSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )
        thumbnail.isTemplate = false
        return thumbnail
    }

    private func makeFullSizeImage(from cgImage: CGImage) -> NSImage? {
        guard cgImage.width > 0, cgImage.height > 0 else {
            return nil
        }

        let image = NSImage(
            cgImage: cgImage,
            size: CGSize(width: cgImage.width, height: cgImage.height)
        )
        image.isTemplate = false
        return image
    }

}

private final class ShareableContentCache {
    var content: SCShareableContent?
}

private final class LiveWindowPreviewSession: NSObject, SCStreamOutput {
    private let stream: SCStream
    private let outputQueue = DispatchQueue(label: "Docky.LiveWindowPreview", qos: .userInteractive)
    private let ciContext = CIContext(options: nil)
    private let onFrame: @MainActor (NSImage?) -> Void
    private var isStopped = false

    init(
        shareableWindow: SCWindow,
        captureSize: CGSize,
        onFrame: @escaping @MainActor (NSImage?) -> Void
    ) {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(captureSize.width)
        configuration.height = Int(captureSize.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.capturesAudio = false
        if FeatureGate.shared.isAvailable(.streamMicrophoneCapture), #available(macOS 15.0, *) {
            configuration.captureMicrophone = false
        }
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true

        self.stream = SCStream(
            filter: SCContentFilter(desktopIndependentWindow: shareableWindow),
            configuration: configuration,
            delegate: nil
        )
        self.onFrame = onFrame

        super.init()
    }

    func start() async throws {
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true

        try? stream.removeStreamOutput(self, type: .screen)
        Task {
            try? await stream.stopCapture()
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        guard let cgImage = ciContext.createCGImage(ciImage, from: rect) else {
            return
        }

        let image = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        image.isTemplate = false

        Task { @MainActor in
            self.onFrame(image)
        }
    }
}
