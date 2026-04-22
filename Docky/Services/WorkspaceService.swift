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
import ScreenCaptureKit

private let axWindowNumberAttribute = "AXWindowNumber" as CFString
private let axCloseAction = "AXClose" as CFString

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
    @Published private(set) var minimizedWindows: [MinimizedWindowTile] = []
    @Published private(set) var minimizedWindowPreviews: [String: NSImage] = [:]

    private var runningByBundleID: [String: RunningApp] = [:]

    var runningBundleIdentifiers: Set<String> { Set(runningByBundleID.keys) }

    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var lastMinimizedWindowsDebugSummary: String?
    private var attemptedMinimizedWindowPreviewIDs: Set<String> = []

    private init() {
        refresh()
        subscribe()
        subscribeToPermissions()
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
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            runningApp.activate(options: [.activateAllWindows])
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: NSWorkspace.OpenConfiguration(),
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
        runningApp.activate(options: [.activateAllWindows])
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
            || closeMinimizedWindowViaButton(windowElement)

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
        PermissionsService.shared.$accessibility
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshMinimizedWindows()
            }
            .store(in: &cancellables)
    }

    private func subscribeToRefreshTimer() {
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshMinimizedWindows()
            }
            .store(in: &cancellables)
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
        guard let windows = arrayAttribute(kAXWindowsAttribute as CFString, of: applicationElement) as? [AXUIElement] else {
            return []
        }

        return windows.filter { window in
            boolAttribute(kAXMinimizedAttribute as CFString, of: window) == true
                && roleAttribute(of: window) == (kAXWindowRole as String)
        }
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

    private func minimizedWindowMatches(_ element: AXUIElement, target: MinimizedWindowTile) -> Bool {
        if let targetWindowNumber = target.windowNumber,
           intAttribute(axWindowNumberAttribute, of: element) == targetWindowNumber {
            return true
        }

        return stringAttribute(kAXTitleAttribute as CFString, of: element) == target.windowTitle
    }

    private func minimizedWindowTarget(for window: MinimizedWindowTile) -> (NSRunningApplication, AXUIElement)? {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: window.bundleIdentifier).first else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        guard let windowElement = minimizedWindowElements(applicationElement: applicationElement)
            .first(where: { minimizedWindowMatches($0, target: window) }) else {
            return nil
        }

        return (runningApp, windowElement)
    }

    private func closeMinimizedWindowViaButton(_ windowElement: AXUIElement) -> Bool {
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

    private func logMinimizedWindowsDebugSummary(_ summary: String) {
        guard summary != lastMinimizedWindowsDebugSummary else {
            return
        }

        lastMinimizedWindowsDebugSummary = summary
        NSLog("[Docky] Minimized windows: \(summary)")
    }
}
