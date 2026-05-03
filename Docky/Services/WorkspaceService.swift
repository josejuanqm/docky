//
//  WorkspaceService.swift
//  Docky
//
//  Observes NSWorkspace for live workspace state. First pass: running apps
//  (regular activation policy only — background agents and menu-bar-only
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

private let axWindowNumberAttribute = "AXWindowNumber" as CFString
private let axCloseAction = "AXClose" as CFString
private let axRaiseAction = "AXRaise" as CFString
private let minimumSwitchableWindowSize = CGSize(width: 100, height: 100)

struct RunningApp: Hashable, Identifiable {
    let bundleIdentifier: String
    let localizedName: String
    let processIdentifier: pid_t
    let bundleURL: URL?
    let launchDate: Date?
    let isHidden: Bool

    var id: String { bundleIdentifier }
}

struct AppWindow: Equatable, Identifiable {
    let windowIdentifier: String
    let windowNumber: Int?
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let appDisplayName: String
    let windowTitle: String
    let isMinimized: Bool
    let previewLookupIndex: Int
    let screenBounds: CGRect?

    var id: String { windowIdentifier }
}

final class WorkspaceService: ObservableObject {
    static let shared = WorkspaceService()

    /// Ordered list: still-running apps keep their position across refreshes,
    /// newly-launched apps append. Terminated apps are removed in place.
    @Published private(set) var runningApps: [RunningApp] = []
    @Published private(set) var minimizedWindows: [MinimizedWindowTile] = []
    @Published private(set) var minimizedWindowPreviews: [String: NSImage] = [:]
    @Published private(set) var appWindowPreviews: [String: NSImage] = [:]

    private var runningByBundleID: [String: RunningApp] = [:]

    var runningBundleIdentifiers: Set<String> { Set(runningByBundleID.keys) }

    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var lastMinimizedWindowsDebugSummary: String?
    private var attemptedMinimizedWindowPreviewIDs: Set<String> = []
    private var attemptedAppWindowPreviewIDs: Set<String> = []
    private var prefetchedSwitchableWindows: [AppWindow] = []
    private var lastPrefetchedSwitchableWindowsAt: Date?
    private let switchableWindowPrefetchMaxAge: TimeInterval = 1.5
    private var liveFocusPreviewSession: LiveWindowPreviewSession?

    private init() {
        refresh()
        subscribe()
        subscribeToPermissions()
        subscribeToWindowSwitcherPreferences()
        subscribeToRefreshTimer()
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

    func isHidden(bundleIdentifier: String) -> Bool {
        runningByBundleID[bundleIdentifier]?.isHidden == true
    }

    func minimizedWindowPreview(for window: MinimizedWindowTile) -> NSImage? {
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
        guard PermissionsService.shared.accessibility == .granted,
              let runningApp = runningByBundleID[bundleIdentifier] else {
            return []
        }

        let applicationElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        return windowElements(applicationElement: applicationElement).enumerated().compactMap { index, windowElement in
            appWindow(from: windowElement, runningApp: runningApp, fallbackIndex: index)
        }
    }

    func switchableWindows(forceRefresh: Bool = false) -> [AppWindow] {
        if !forceRefresh,
           hasFreshSwitchableWindowPrefetch,
           !prefetchedSwitchableWindows.isEmpty {
            return prefetchedSwitchableWindows
        }

        return refreshSwitchableWindowSnapshot()
    }

    @discardableResult
    private func refreshSwitchableWindowSnapshot() -> [AppWindow] {
        let windows = querySwitchableWindows()
        prefetchedSwitchableWindows = windows
        lastPrefetchedSwitchableWindowsAt = Date()
        refreshAppWindowPreviews(for: windows)
        return windows
    }

    private func querySwitchableWindows() -> [AppWindow] {
        guard PermissionsService.shared.accessibility == .granted else {
            return []
        }

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] ?? []
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let runningAppsByProcessIdentifier = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) })
        var seenWindowIdentifiers: Set<String> = []
        var cachedWindowsByBundleIdentifier: [String: [AppWindow]] = [:]
        var result: [AppWindow] = []

        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID] as? pid_t,
                  ownerPID != currentProcessIdentifier,
                  (entry[kCGWindowLayer] as? Int) == 0,
                  let bounds = entry[kCGWindowBounds] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 1,
                  (bounds["Height"] ?? 0) > 1 else {
                continue
            }

            guard let runningApp = runningAppsByProcessIdentifier[ownerPID] else {
                continue
            }

            var bundleWindows = cachedWindowsByBundleIdentifier[runningApp.bundleIdentifier] ?? {
                let windows = appWindows(bundleIdentifier: runningApp.bundleIdentifier)
                cachedWindowsByBundleIdentifier[runningApp.bundleIdentifier] = windows
                return windows
            }()

            let windowNumber = entry[kCGWindowNumber] as? Int
            let windowName = (entry[kCGWindowName] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let screenBounds = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            guard let matchedWindowIndex = bundleWindows.firstIndex(where: {
                if let windowNumber, $0.windowNumber == windowNumber {
                    return true
                }

                return normalizedWindowTitle($0.windowTitle) == normalizedWindowTitle(windowName)
            }) else {
                continue
            }
            let matchedWindow = bundleWindows.remove(at: matchedWindowIndex)
            cachedWindowsByBundleIdentifier[runningApp.bundleIdentifier] = bundleWindows

            let visibleWindow = AppWindow(
                windowIdentifier: matchedWindow.windowIdentifier,
                windowNumber: windowNumber ?? matchedWindow.windowNumber,
                bundleIdentifier: matchedWindow.bundleIdentifier,
                processIdentifier: matchedWindow.processIdentifier,
                appDisplayName: matchedWindow.appDisplayName,
                windowTitle: matchedWindow.windowTitle,
                isMinimized: matchedWindow.isMinimized,
                previewLookupIndex: matchedWindow.previewLookupIndex,
                screenBounds: screenBounds
            )

            if screenBounds.width < minimumSwitchableWindowSize.width
                || screenBounds.height < minimumSwitchableWindowSize.height {
                NSLog(
                    "[Docky] Tiny switchable window candidate made it through app=%@ title=%@ id=%@ bounds=%@ windowNumber=%@",
                    visibleWindow.bundleIdentifier,
                    visibleWindow.windowTitle,
                    visibleWindow.windowIdentifier,
                    NSStringFromRect(screenBounds.integral),
                    visibleWindow.windowNumber.map(String.init) ?? "nil"
                )
            }

            guard !visibleWindow.isMinimized,
                  !seenWindowIdentifiers.contains(visibleWindow.windowIdentifier) else {
                continue
            }

            seenWindowIdentifiers.insert(visibleWindow.windowIdentifier)
            result.append(visibleWindow)
        }

        return result
    }

    func appWindowPreview(for window: AppWindow) -> NSImage? {
        appWindowPreviews[window.windowIdentifier]
    }

    func liveFocusPreviewImage(for window: AppWindow) async -> NSImage? {
        guard PermissionsService.shared.screenCapture == .granted else {
            return appWindowPreviews[window.windowIdentifier]
        }

        if let windowNumber = window.windowNumber,
           let cgImage = CGWindowListCreateImagePrivate(
               .null,
               [.optionIncludingWindow],
               CGWindowID(windowNumber),
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
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "focus app windows")
            return false
        }

        guard let (runningApp, windowElement) = appWindowTarget(for: window) else {
            refreshMinimizedWindows()
            return false
        }

        let restored = !window.isMinimized || AXUIElementSetAttributeValue(
            windowElement,
            kAXMinimizedAttribute as CFString,
            kCFBooleanFalse
        ) == .success

        runningApp.unhide()
        runningApp.activate(options: [.activateAllWindows])
        let raised = AXUIElementPerformAction(windowElement, axRaiseAction) == .success

        refreshMinimizedWindows()
        return restored && raised
    }

    func focusApplication(bundleIdentifier: String) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return
        }

        runningApp.unhide()
        runningApp.activate(options: [.activateAllWindows])
    }

    @discardableResult
    func minimize(window: AppWindow) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "minimize app windows")
            return false
        }

        guard let (_, windowElement) = appWindowTarget(for: window) else {
            refreshMinimizedWindows()
            return false
        }

        let minimized = AXUIElementSetAttributeValue(
            windowElement,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        ) == .success

        refreshMinimizedWindows()
        return minimized
    }

    @discardableResult
    func close(window: AppWindow) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "close app windows")
            return false
        }

        guard let (_, windowElement) = appWindowTarget(for: window) else {
            refreshMinimizedWindows()
            return false
        }

        let closed = AXUIElementPerformAction(windowElement, axCloseAction) == .success
            || closeWindowViaButton(windowElement)

        refreshMinimizedWindows()
        return closed
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
        focusApplication(bundleIdentifier: bundleIdentifier)
    }

    @discardableResult
    func restoreMinimizedWindow(_ window: MinimizedWindowTile) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "restore minimized windows")
            return false
        }

        guard let (runningApp, windowElement) = minimizedWindowTarget(for: window) else {
            refreshMinimizedWindows()
            return false
        }

        let restored = AXUIElementSetAttributeValue(
            windowElement,
            kAXMinimizedAttribute as CFString,
            kCFBooleanFalse
        ) == .success

        if restored {
            runningApp.unhide()
            runningApp.activate(options: [.activateAllWindows])
        }

        refreshMinimizedWindows()
        return restored
    }

    @discardableResult
    func closeMinimizedWindow(_ window: MinimizedWindowTile) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "close minimized windows")
            return false
        }

        guard let (_, windowElement) = minimizedWindowTarget(for: window) else {
            refreshMinimizedWindows()
            return false
        }

        let closed = AXUIElementPerformAction(windowElement, axCloseAction) == .success
            || closeWindowViaButton(windowElement)

        refreshMinimizedWindows()
        return closed
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
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
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
        runningApps = ordered
        refreshMinimizedWindows()
        refreshSwitchableWindowPrefetchIfNeeded(force: true)
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
    }

    private func subscribeToPermissions() {
        Publishers.CombineLatest(
            PermissionsService.shared.$accessibility,
            PermissionsService.shared.$screenCapture
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.refreshMinimizedWindows()
                self?.refreshSwitchableWindowPrefetchIfNeeded(force: true)
            }
            .store(in: &cancellables)
    }

    private func subscribeToWindowSwitcherPreferences() {
        DockyPreferences.shared.$enablesWindowSwitcher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSwitchableWindowPrefetchIfNeeded(force: true)
            }
            .store(in: &cancellables)
    }

    private func subscribeToRefreshTimer() {
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshMinimizedWindows()
                self?.refreshSwitchableWindowPrefetchIfNeeded()
            }
            .store(in: &cancellables)
    }

    private var hasFreshSwitchableWindowPrefetch: Bool {
        guard let lastPrefetchedSwitchableWindowsAt else {
            return false
        }

        return Date().timeIntervalSince(lastPrefetchedSwitchableWindowsAt) <= switchableWindowPrefetchMaxAge
    }

    private func refreshSwitchableWindowPrefetchIfNeeded(force: Bool = false) {
        guard DockyPreferences.shared.enablesWindowSwitcher,
              PermissionsService.shared.accessibility == .granted else {
            clearSwitchableWindowPrefetch()
            return
        }

        guard force || !hasFreshSwitchableWindowPrefetch else {
            return
        }

        _ = refreshSwitchableWindowSnapshot()
    }

    private func clearSwitchableWindowPrefetch() {
        prefetchedSwitchableWindows = []
        lastPrefetchedSwitchableWindowsAt = nil

        if !appWindowPreviews.isEmpty {
            appWindowPreviews = [:]
        }

        attemptedAppWindowPreviewIDs = []
    }

    private func refreshMinimizedWindows() {
        guard PermissionsService.shared.accessibility == .granted else {
            logMinimizedWindowsDebugSummary("Accessibility not granted")
            if !minimizedWindows.isEmpty {
                minimizedWindows = []
            }
            if !minimizedWindowPreviews.isEmpty {
                minimizedWindowPreviews = [:]
            }
            attemptedMinimizedWindowPreviewIDs = []
            return
        }

        var debugEntries: [String] = []
        let currentWindows = runningApps.flatMap { runningApp in
            minimizedWindowTiles(for: runningApp, debugEntries: &debugEntries)
        }

        if currentWindows.isEmpty {
            logMinimizedWindowsDebugSummary(([
                "No minimized windows detected",
                "runningApps=\(runningApps.count)"
            ] + debugEntries).joined(separator: " | "))
        } else {
            let titles = currentWindows.map { "\($0.appDisplayName):\($0.windowTitle)" }.joined(separator: ", ")
            logMinimizedWindowsDebugSummary("Detected \(currentWindows.count) minimized window(s): \(titles)")
        }

        let currentByIdentifier = Dictionary(uniqueKeysWithValues: currentWindows.map { ($0.windowIdentifier, $0) })
        let existingIdentifiers = Set(minimizedWindows.map(\.windowIdentifier))

        var orderedWindows = minimizedWindows.compactMap { currentByIdentifier[$0.windowIdentifier] }
        for window in currentWindows where !existingIdentifiers.contains(window.windowIdentifier) {
            orderedWindows.append(window)
        }

        if orderedWindows != minimizedWindows {
            minimizedWindows = orderedWindows
        }

        refreshMinimizedWindowPreviews(for: currentWindows)
    }

    private func refreshMinimizedWindowPreviews(for windows: [MinimizedWindowTile]) {
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

    private func minimizedWindowTiles(
        for runningApp: RunningApp,
        debugEntries: inout [String]
    ) -> [MinimizedWindowTile] {
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: runningApp.bundleIdentifier).first else {
            debugEntries.append("\(runningApp.localizedName): not running")
            return []
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let windows = minimizedWindowElements(applicationElement: applicationElement)
        let minimizedWindows = windows.enumerated().compactMap { index, windowElement in
            minimizedWindowTile(from: windowElement, runningApp: runningApp, fallbackIndex: index)
        }

        debugEntries.append("\(runningApp.localizedName): axWindows=\(windows.count), minimized=\(minimizedWindows.count)")
        return minimizedWindows
    }

    private func minimizedWindowElements(applicationElement: AXUIElement) -> [AXUIElement] {
        windowElements(applicationElement: applicationElement).filter { window in
            boolAttribute(kAXMinimizedAttribute as CFString, of: window) == true
        }
    }

    private func windowElements(applicationElement: AXUIElement) -> [AXUIElement] {
        guard let windows = arrayAttribute(kAXWindowsAttribute as CFString, of: applicationElement) as? [AXUIElement] else {
            return []
        }

        return windows.filter { window in
            roleAttribute(of: window) == (kAXWindowRole as String)
        }
    }

    private func appWindow(
        from windowElement: AXUIElement,
        runningApp: RunningApp,
        fallbackIndex: Int
    ) -> AppWindow? {
        guard let windowSize = cgSizeAttribute(kAXSizeAttribute as CFString, of: windowElement),
              windowSize.width >= minimumSwitchableWindowSize.width,
              windowSize.height >= minimumSwitchableWindowSize.height else {
            return nil
        }

        let title = stringAttribute(kAXTitleAttribute as CFString, of: windowElement)
            ?? runningApp.localizedName
        let windowNumber = intAttribute(axWindowNumberAttribute, of: windowElement)
        let fallbackToken = title.isEmpty ? "window-\(fallbackIndex)" : "\(title):\(fallbackIndex)"

        return AppWindow(
            windowIdentifier: windowNumber.map { "\(runningApp.bundleIdentifier):\($0)" }
                ?? "\(runningApp.bundleIdentifier):\(fallbackToken)",
            windowNumber: windowNumber,
            bundleIdentifier: runningApp.bundleIdentifier,
            processIdentifier: runningApp.processIdentifier,
            appDisplayName: runningApp.localizedName,
            windowTitle: title.isEmpty ? runningApp.localizedName : title,
            isMinimized: boolAttribute(kAXMinimizedAttribute as CFString, of: windowElement) == true,
            previewLookupIndex: fallbackIndex,
            screenBounds: nil
        )
    }

    private func minimizedWindowTile(
        from windowElement: AXUIElement,
        runningApp: RunningApp,
        fallbackIndex: Int
    ) -> MinimizedWindowTile? {
        let title = stringAttribute(kAXTitleAttribute as CFString, of: windowElement)
            ?? runningApp.localizedName
        let windowNumber = intAttribute(axWindowNumberAttribute, of: windowElement)
        let fallbackToken = title.isEmpty ? "window-\(fallbackIndex)" : "\(title):\(fallbackIndex)"

        return MinimizedWindowTile(
            windowIdentifier: windowNumber.map { "\(runningApp.bundleIdentifier):\($0)" }
                ?? "\(runningApp.bundleIdentifier):\(fallbackToken)",
            windowNumber: windowNumber,
            bundleIdentifier: runningApp.bundleIdentifier,
            processIdentifier: runningApp.processIdentifier,
            appDisplayName: runningApp.localizedName,
            windowTitle: title.isEmpty ? runningApp.localizedName : title,
            previewLookupIndex: fallbackIndex
        )
    }

    private func minimizedWindowTarget(for window: MinimizedWindowTile) -> (NSRunningApplication, AXUIElement)? {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: window.bundleIdentifier).first else {
            return nil
        }
        guard let runningAppSnapshot = runningByBundleID[window.bundleIdentifier] else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        guard let windowElement = minimizedWindowElements(applicationElement: applicationElement)
            .enumerated()
            .first(where: { index, element in
                minimizedWindowTile(from: element, runningApp: runningAppSnapshot, fallbackIndex: index)?.windowIdentifier == window.windowIdentifier
            })?
            .element else {
            return nil
        }

        return (runningApp, windowElement)
    }

    private func appWindowTarget(for window: AppWindow) -> (NSRunningApplication, AXUIElement)? {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: window.bundleIdentifier).first else {
            return nil
        }
        guard let runningAppSnapshot = runningByBundleID[window.bundleIdentifier] else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        guard let windowElement = windowElements(applicationElement: applicationElement)
            .enumerated()
            .first(where: { index, element in
                appWindow(from: element, runningApp: runningAppSnapshot, fallbackIndex: index)?.windowIdentifier == window.windowIdentifier
            })?
            .element else {
            return nil
        }

        return (runningApp, windowElement)
    }

    private func closeWindowViaButton(_ windowElement: AXUIElement) -> Bool {
        guard let closeButtonValue = valueAttribute(kAXCloseButtonAttribute as CFString, of: windowElement) else {
            return false
        }

        let closeButton = unsafeBitCast(closeButtonValue, to: AXUIElement.self)

        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
    }

    private func roleAttribute(of element: AXUIElement) -> String? {
        stringAttribute(kAXRoleAttribute as CFString, of: element)
    }

    private func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        valueAttribute(attribute, of: element) as? String
    }

    private func boolAttribute(_ attribute: CFString, of element: AXUIElement) -> Bool? {
        (valueAttribute(attribute, of: element) as? NSNumber)?.boolValue
    }

    private func intAttribute(_ attribute: CFString, of element: AXUIElement) -> Int? {
        (valueAttribute(attribute, of: element) as? NSNumber)?.intValue
    }

    private func cgSizeAttribute(_ attribute: CFString, of element: AXUIElement) -> CGSize? {
        guard let value = valueAttribute(attribute, of: element) else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func arrayAttribute(_ attribute: CFString, of element: AXUIElement) -> AnyObject? {
        valueAttribute(attribute, of: element)
    }

    private func valueAttribute(_ attribute: CFString, of element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private func captureMinimizedWindowPreviewIfNeeded(for window: MinimizedWindowTile) {
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
        guard PermissionsService.shared.screenCapture == .granted else {
            if !appWindowPreviews.isEmpty {
                appWindowPreviews = [:]
            }
            attemptedAppWindowPreviewIDs = []
            return
        }

        let activeWindowIdentifiers = Set(windows.map(\.windowIdentifier))
        var updatedPreviews = appWindowPreviews
        var didChange = false

        for windowIdentifier in updatedPreviews.keys where !activeWindowIdentifiers.contains(windowIdentifier) {
            updatedPreviews.removeValue(forKey: windowIdentifier)
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
            configuration.captureMicrophone = false
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
            configuration.captureMicrophone = false
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

    private func captureMinimizedWindowPreview(for window: MinimizedWindowTile) async -> NSImage? {
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
            configuration.captureMicrophone = false
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

    private func matchingShareableWindow(for window: MinimizedWindowTile, in windows: [SCWindow]) -> SCWindow? {
        if let windowNumber = window.windowNumber,
           let exactMatch = windows.first(where: { Int($0.windowID) == windowNumber }) {
            return exactMatch
        }

        let appWindows = windows.filter { shareableWindow in
            guard let owningApplication = shareableWindow.owningApplication else {
                return false
            }

            return owningApplication.processID == window.processIdentifier
                || owningApplication.bundleIdentifier == window.bundleIdentifier
        }

        let titledWindows = appWindows.filter { shareableWindow in
            normalizedWindowTitle(shareableWindow.title) == normalizedWindowTitle(window.windowTitle)
        }

        if titledWindows.indices.contains(window.previewLookupIndex) {
            return titledWindows[window.previewLookupIndex]
        }

        if let titleMatch = titledWindows.first {
            return titleMatch
        }

        if appWindows.indices.contains(window.previewLookupIndex) {
            return appWindows[window.previewLookupIndex]
        }

        return appWindows.first
    }

    private func matchingShareableWindow(for window: AppWindow, in windows: [SCWindow]) -> SCWindow? {
        if let windowNumber = window.windowNumber,
           let exactMatch = windows.first(where: { Int($0.windowID) == windowNumber }) {
            return exactMatch
        }

        let appWindows = windows.filter { shareableWindow in
            guard let owningApplication = shareableWindow.owningApplication else {
                return false
            }

            return owningApplication.processID == window.processIdentifier
                || owningApplication.bundleIdentifier == window.bundleIdentifier
        }

        let titledWindows = appWindows.filter { shareableWindow in
            normalizedWindowTitle(shareableWindow.title) == normalizedWindowTitle(window.windowTitle)
        }

        if titledWindows.indices.contains(window.previewLookupIndex) {
            return titledWindows[window.previewLookupIndex]
        }

        if let titleMatch = titledWindows.first {
            return titleMatch
        }

        if appWindows.indices.contains(window.previewLookupIndex) {
            return appWindows[window.previewLookupIndex]
        }

        return appWindows.first
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
        try await withCheckedThrowingContinuation { continuation in
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

    private func logMinimizedWindowsDebugSummary(_ summary: String) {
        guard summary != lastMinimizedWindowsDebugSummary else {
            return
        }

        lastMinimizedWindowsDebugSummary = summary
        NSLog("[Docky] Minimized windows: \(summary)")
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
        configuration.captureMicrophone = false
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
