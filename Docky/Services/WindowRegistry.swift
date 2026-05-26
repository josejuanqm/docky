//
//  WindowRegistry.swift
//  Docky
//
//  Single source of truth for "what windows exist right now" across all
//  running apps. Subscribes per-app to AX notifications and maintains a
//  long-lived `[AppWindow]` whose identity is the underlying `AXUIElement`.
//
//  Why this exists:
//  - The poll-and-rebuild approach (re-enumerate AX windows on each call,
//    match by derived identifier strings) is fragile under title changes,
//    AX reordering, or rapid focus cycling. Identifying a window by the
//    actual AXUIElement is stable for the lifetime of the window, so a
//    raise/minimize/close call always targets the picked window or fails
//    cleanly when the window is gone.
//  - The list is kept fresh in the background, so consumers (window
//    switcher, tile click logic) read a ready snapshot instead of paying
//    the enumeration cost each interaction.
//
//  Threading: this class is not `@MainActor`-annotated (matching the rest
//  of the services) but all mutation happens on main — AX observers are
//  added to the main run loop, and `NSWorkspace` notifications are
//  delivered on the main queue.
//

import AppKit
import ApplicationServices
import Combine

private let axWindowNumberAttribute = "AXWindowNumber" as CFString
private let axCloseAction = "AXClose" as CFString
private let minimumTrackedWindowSize = CGSize(width: 100, height: 100)

/// System helpers whose AX windows would leak into the switcher / preview if
/// we treated them like regular apps. Most are filtered by activation policy
/// already; this is a defensive belt-and-braces layer for cases where an
/// agent transiently flips to `.regular` (Notification Center has done this
/// in the past).
private let filteredBundleIdentifiers: Set<String> = [
    "com.apple.notificationcenterui",
    "com.apple.WindowManager",
    "com.apple.dock",
]

/// Stable, opaque identity for an `AppWindow`. Backed by the
/// `AXUIElement`'s CF identity — equal and hashable across the lifetime
/// of the underlying window.
nonisolated struct WindowID: Hashable {
    nonisolated fileprivate let element: AXUIElement

    nonisolated static func == (lhs: WindowID, rhs: WindowID) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(Int(bitPattern: CFHash(element)))
    }

    /// Stable string form for callers that need a string key (preview cache
    /// keys, debug logs). Stable within a single process run but not across
    /// launches.
    nonisolated var stableString: String {
        String(format: "ax:%lx", CFHash(element))
    }
}

/// A window observed in the registry. Identity is the underlying
/// `AXUIElement`; all other fields are best-effort snapshots updated as
/// AX notifications arrive.
struct AppWindow: Identifiable, Hashable {
    nonisolated fileprivate let element: AXUIElement
    nonisolated let bundleIdentifier: String
    nonisolated let processIdentifier: pid_t
    nonisolated let appDisplayName: String
    nonisolated let windowTitle: String
    nonisolated let isMinimized: Bool
    nonisolated let windowNumber: Int?
    nonisolated let cgWindowID: CGWindowID?
    nonisolated let frame: CGRect?

    nonisolated var id: WindowID { WindowID(element: element) }

    /// Compatibility alias matching the previous API surface.
    nonisolated var windowIdentifier: String { id.stableString }

    /// Compatibility alias matching the previous API surface.
    nonisolated var screenBounds: CGRect? { frame }

    nonisolated static func == (lhs: AppWindow, rhs: AppWindow) -> Bool {
        CFEqual(lhs.element, rhs.element)
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.processIdentifier == rhs.processIdentifier
            && lhs.appDisplayName == rhs.appDisplayName
            && lhs.windowTitle == rhs.windowTitle
            && lhs.isMinimized == rhs.isMinimized
            && lhs.windowNumber == rhs.windowNumber
            && lhs.cgWindowID == rhs.cgWindowID
            && lhs.frame == rhs.frame
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(WindowID(element: element))
    }
}

final class WindowRegistry: ObservableObject {
    static let shared = WindowRegistry()

    /// Observed-order window list across all tracked apps. Order is stable:
    /// new windows are appended; updates land in place; removals leave a
    /// hole that the next snapshot fills.
    @Published private(set) var windows: [AppWindow] = []

    /// Fires when a window's cached preview should be evicted and re-
    /// captured, even though the registry's `$windows` array hasn't
    /// changed shape. Emitted on resize (aspect ratio changed) and on
    /// focus-out (capture the outgoing window while it's still on top).
    /// The associated value is `AppWindow.windowIdentifier`.
    let previewInvalidations = PassthroughSubject<String, Never>()

    /// Per-pid tracking of the AX-focused window so we can name the
    /// outgoing window when focus changes. Only used to drive preview
    /// invalidation; the canonical list ordering still lives in `windows`.
    private var lastFocusedWindowIDByPID: [pid_t: WindowID] = [:]

    /// Windows currently minimized, in observation order. Newest minimized
    /// last — `last(where: bundleID:)` gives the most-recently minimized.
    var minimized: [AppWindow] {
        windows.filter(\.isMinimized)
    }

    /// Windows that are visible (non-minimized) and large enough to be
    /// interactable — the natural "switchable" set. Also gated by
    /// `isCapturable`, so windows the switcher / preview pipeline can't
    /// usefully represent never leak through.
    var visible: [AppWindow] {
        windows.filter { window in
            guard !window.isMinimized else { return false }
            return isCapturable(window)
        }
    }

    /// Same as `visible` but optionally folds minimized windows back in
    /// so the switcher / hover preview can present them under a
    /// "(minimized)" badge. Minimized windows skip the strict
    /// `isCapturable` test (CGWindowServer often omits bounds for them,
    /// which would otherwise filter them out) and are kept whenever
    /// they have a `cgWindowID` to identify them.
    func switchable(includeMinimized: Bool) -> [AppWindow] {
        windows.filter { window in
            if window.isMinimized {
                return includeMinimized && window.cgWindowID != nil
            }
            return isCapturable(window)
        }
    }

    /// True when a window has a working CGWindowID, the WindowServer
    /// still reports bounds for it, and those bounds are large enough
    /// to be a real content window (>= 100x100). Filters out auxiliary
    /// overlays, menu-bar strips, and AX entries whose underlying CG
    /// window has already gone away. Independent of minimized state —
    /// per-tile hover previews legitimately want minimized windows so
    /// long as they're real windows.
    func isCapturable(_ window: AppWindow) -> Bool {
        if let size = window.frame?.size,
           size.width < minimumTrackedWindowSize.width
            || size.height < minimumTrackedWindowSize.height {
            return false
        }
        guard let cgWindowID = window.cgWindowID,
              let cgFrame = cgWindowFrame(forID: cgWindowID) else {
            return false
        }
        return cgFrame.width >= minimumTrackedWindowSize.width
            && cgFrame.height >= minimumTrackedWindowSize.height
    }

    /// OS-reported bounds for a CGWindowID, or nil when the window no
    /// longer exists from the WindowServer's perspective.
    private func cgWindowFrame(forID cgWindowID: CGWindowID) -> CGRect? {
        let descriptions = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            cgWindowID
        ) as? [[String: Any]] ?? []
        guard let entry = descriptions.first,
              let boundsDict = entry[kCGWindowBounds as String] as? [String: Any] else {
            return nil
        }
        return CGRect(
            x: (boundsDict["X"] as? CGFloat) ?? 0,
            y: (boundsDict["Y"] as? CGFloat) ?? 0,
            width: (boundsDict["Width"] as? CGFloat) ?? 0,
            height: (boundsDict["Height"] as? CGFloat) ?? 0
        )
    }

    private var applicationObservers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var permissionsCancellable: AnyCancellable?
    private var observationsActive = false

    private init() {
        permissionsCancellable = PermissionsService.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if status == .granted {
                    self.startObservingIfNeeded()
                } else {
                    self.stopObserving()
                }
            }

        if PermissionsService.shared.accessibility == .granted {
            startObservingIfNeeded()
        }
    }

    deinit {
        stopObserving()
    }

    // MARK: - Lookup

    func windows(forBundleIdentifier bundleIdentifier: String) -> [AppWindow] {
        windows.filter { $0.bundleIdentifier == bundleIdentifier }
    }

    func windowsByRecency(forBundleIdentifier bundleIdentifier: String) -> [AppWindow] {
        // The registry's `windows` array is maintained in per-window MRU
        // order: focus/activation events bump only the actually-focused
        // window to the front (see `bumpWindowToTop`). For this app, the
        // first match is the most recently focused window — its other
        // windows sit wherever they were last seen.
        windows(forBundleIdentifier: bundleIdentifier)
    }

    // MARK: - Window operations

    /// Brings `window` to the front. Prefers the SLPS path (private SkyLight)
    /// because it targets a specific CGWindowID — only the picked window comes
    /// forward, instead of every window of the app. Falls back to AX-raise +
    /// `NSRunningApplication.activate()` when no CGWindowID is available
    /// (rare; see `WindowRegistry.cgWindowID`) or when SLPS is unavailable.
    @discardableResult
    func focus(_ window: AppWindow) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "focus app windows")
            return false
        }

        guard let element = liveElement(for: window) else {
            return false
        }

        let restored: Bool
        if window.isMinimized {
            restored = AXUIElementSetAttributeValue(
                element,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            ) == .success
        } else {
            restored = true
        }

        if let cgWindowID = window.cgWindowID,
           focusViaSLPS(pid: window.processIdentifier, cgWindowID: cgWindowID, element: element) {
            // SLPS doesn't unhide the app process itself; if it was hidden,
            // surface it now so its windows can actually display.
            if let runningApp = NSRunningApplication(processIdentifier: window.processIdentifier),
               runningApp.isHidden {
                runningApp.unhide()
            }
            return restored
        }

        // Legacy fallback: raise via AX, then activate the whole app. This
        // brings every window of the app forward — what we're trying to avoid
        // — but it's the only thing that works when CGWindowID lookup fails.
        let raised = AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success

        if let runningApp = NSRunningApplication(processIdentifier: window.processIdentifier) {
            DispatchQueue.main.async {
                runningApp.unhide()
                _ = runningApp.activate()
            }
        }

        return restored && raised
    }

    private func focusViaSLPS(pid: pid_t, cgWindowID: CGWindowID, element: AXUIElement) -> Bool {
        var psn = ProcessSerialNumber()
        guard GetProcessForPID(pid, &psn) == noErr else { return false }

        let result = _SLPSSetFrontProcessWithOptions(&psn, cgWindowID, SLPSMode.userGenerated.rawValue)
        guard result == .success else { return false }

        // Synthetic event handshake — without this the window comes up but
        // keyboard input still routes to the previous app.
        slpsMakeKeyWindow(psn: &psn, windowID: cgWindowID)

        // Best-effort: AX raise to confirm Z-order in AX, and mark as main so
        // the app's "main window changed" hooks fire. Failures here don't
        // unwind — the SLPS call already brought the window front.
        _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(element, kAXMainWindowAttribute as CFString, kCFBooleanTrue)

        return true
    }

    @discardableResult
    func minimize(_ window: AppWindow) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "minimize app windows")
            return false
        }

        guard let element = liveElement(for: window) else {
            return false
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        ) == .success
    }

    @discardableResult
    func close(_ window: AppWindow) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "close app windows")
            return false
        }

        guard let element = liveElement(for: window) else {
            return false
        }
        if AXUIElementPerformAction(element, axCloseAction) == .success {
            return true
        }
        return closeViaButton(element)
    }

    /// Presses the window's green zoom button via AX. Mirrors what the user
    /// would get clicking the title-bar button or selecting Window > Zoom —
    /// macOS handles the toggle between user-set size and visibleFrame fit.
    @discardableResult
    func zoom(_ window: AppWindow) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "zoom app windows")
            return false
        }

        guard let element = liveElement(for: window) else { return false }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                element,
                kAXZoomButtonAttribute as CFString,
                &value
              ) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return false
        }
        let zoomButton = value as! AXUIElement
        return AXUIElementPerformAction(zoomButton, kAXPressAction as CFString) == .success
    }

    /// Resize-and-move via AX. No permission alert: callers (background
    /// services) want a silent failure when permission is missing.
    @discardableResult
    func resize(_ window: AppWindow, to frame: CGRect) -> Bool {
        guard PermissionsService.shared.accessibility == .granted else { return false }

        var origin = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }

        guard let element = liveElement(for: window) else { return false }
        let posResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        return posResult == .success && sizeResult == .success
    }

    /// Returns a live `AXUIElement` for the window's logical identity, or nil
    /// when the window is truly gone. Probes the cached element with a cheap
    /// position read; if AX no longer answers, re-syncs the app and tries to
    /// relocate the same window by `cgWindowID` (the only stable cross-element
    /// identifier we keep). Skipping this lets stale element pointers silently
    /// no-op `focus`/`minimize`/`close`/`resize`.
    private func liveElement(for window: AppWindow) -> AXUIElement? {
        if isElementResponsive(window.element) {
            return window.element
        }
        syncWindows(for: window.processIdentifier)
        guard let cgID = window.cgWindowID else { return nil }
        return windows.first(where: {
            $0.processIdentifier == window.processIdentifier && $0.cgWindowID == cgID
        })?.element
    }

    private func isElementResponsive(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &value
        ) == .success
    }

    private func closeViaButton(_ windowElement: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                windowElement,
                kAXCloseButtonAttribute as CFString,
                &value
              ) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return false
        }

        let closeButton = value as! AXUIElement
        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
    }

    // MARK: - Observation lifecycle

    private func startObservingIfNeeded() {
        guard !observationsActive else { return }
        observationsActive = true

        subscribeToWorkspaceLifecycle()
        let apps = currentRegularApps()
        for app in apps {
            installObserver(for: app)
        }
        rebuildSnapshot()
    }

    private func stopObserving() {
        guard observationsActive else { return }
        observationsActive = false

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        for (_, observer) in applicationObservers {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        applicationObservers.removeAll()

        if !windows.isEmpty {
            windows = []
        }
    }

    private func subscribeToWorkspaceLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleAppLaunched(notification)
            },
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleAppTerminated(notification)
            },
            center.addObserver(
                forName: NSWorkspace.didHideApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
                self?.removeWindows(for: pid)
            },
            center.addObserver(
                forName: NSWorkspace.didUnhideApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
                self?.syncWindows(for: pid)
            },
            // AX's view of windows can drift after a Space switch — windows on
            // the now-inactive Space sometimes get hidden/shown inconsistently.
            // Re-snapshot so MRU and visibility reflect the new Space.
            center.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.rebuildSnapshot()
            },
        ]
    }

    private func handleAppLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              shouldTrack(app) else {
            return
        }
        installObserver(for: app)
        // AX may not be ready immediately after launch — defer one tick.
        DispatchQueue.main.async { [weak self] in
            self?.syncWindows(for: app.processIdentifier)
        }
    }

    private func handleAppTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        removeObserver(for: app.processIdentifier)
        removeWindows(for: app.processIdentifier)
    }

    private func currentRegularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter(shouldTrack)
    }

    private func shouldTrack(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular else { return false }
        if let bundleId = app.bundleIdentifier {
            if filteredBundleIdentifiers.contains(bundleId) { return false }
            // Docky itself is invisible to every Docky-owned surface
            // (dock tiles, window switcher). Excluded by bundle ID so
            // running the app as a debug helper from Xcode is filtered
            // out too.
            if bundleId == Bundle.main.bundleIdentifier { return false }
        }
        return true
    }

    // MARK: - Per-app AX observer

    private func installObserver(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid > 0,
              applicationObservers[pid] == nil else {
            return
        }

        var observer: AXObserver?
        let createStatus = AXObserverCreate(pid, axObserverCallback, &observer)
        guard createStatus == .success, let observer else {
            return
        }

        applicationObservers[pid] = observer

        let appElement = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()

        let notifications: [CFString] = [
            kAXWindowCreatedNotification as CFString,
            kAXUIElementDestroyedNotification as CFString,
            kAXWindowMovedNotification as CFString,
            kAXWindowResizedNotification as CFString,
            kAXWindowMiniaturizedNotification as CFString,
            kAXWindowDeminiaturizedNotification as CFString,
            kAXTitleChangedNotification as CFString,
            kAXFocusedWindowChangedNotification as CFString,
            kAXMainWindowChangedNotification as CFString,
            kAXApplicationActivatedNotification as CFString,
            kAXApplicationHiddenNotification as CFString,
            kAXApplicationShownNotification as CFString,
        ]

        for name in notifications {
            _ = AXObserverAddNotification(observer, appElement, name, context)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    private func removeObserver(for pid: pid_t) {
        guard let observer = applicationObservers.removeValue(forKey: pid) else {
            return
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    private func pid(for observer: AXObserver) -> pid_t? {
        applicationObservers.first(where: { $0.value === observer })?.key
    }

    fileprivate func handleNotification(
        observer: AXObserver,
        element: AXUIElement,
        notificationName: CFString
    ) {
        guard let pid = pid(for: observer) else { return }
        let name = notificationName as String

        switch name {
        case kAXFocusedWindowChangedNotification,
             kAXMainWindowChangedNotification:
            // Per-window MRU: the notification's element IS the now-focused
            // window. Move just that one to the front; the app's other
            // windows stay where they were in the global list.
            let newFocusedID = WindowID(element: element)
            invalidateOutgoingFocusedPreview(pid: pid, newFocusedID: newFocusedID)
            lastFocusedWindowIDByPID[pid] = newFocusedID
            bumpWindowToTop(element: element, pid: pid)

        case kAXApplicationActivatedNotification,
             kAXApplicationShownNotification:
            // App-level signal — query AX for the currently focused window
            // and bump only that one (not the app's whole block).
            bumpFocusedWindowToTop(pid: pid)

        case kAXWindowCreatedNotification,
             kAXWindowMiniaturizedNotification,
             kAXWindowDeminiaturizedNotification:
            // These can fire for background apps (e.g., "open in new window"
            // from a notification). Don't bump — just refresh in place.
            syncWindows(for: pid)

        case kAXWindowMovedNotification:
            updateFrameOrSync(element: element, pid: pid)

        case kAXWindowResizedNotification:
            // Aspect ratio likely changed; the cached thumbnail will look
            // squished in the preview card. Drop it before the frame
            // update so the refresh that follows kicks off a recapture.
            let target = WindowID(element: element)
            if let resized = windows.first(where: { $0.id == target }) {
                previewInvalidations.send(resized.windowIdentifier)
            }
            updateFrameOrSync(element: element, pid: pid)

        case kAXTitleChangedNotification:
            updateTitleOrSync(element: element, pid: pid)

        case kAXApplicationHiddenNotification:
            removeWindows(for: pid)

        case kAXUIElementDestroyedNotification:
            removeWindow(matching: element, pid: pid)

        default:
            break
        }
    }

    // MARK: - Snapshot mutation

    private func rebuildSnapshot() {
        var collected: [AppWindow] = []
        for app in currentRegularApps() {
            collected.append(contentsOf: enumerateWindows(for: app))
        }
        applyOrdered(collected)
    }

    private func syncWindows(for pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular else {
            removeWindows(for: pid)
            return
        }

        let updated = enumerateWindows(for: app)
        replaceWindows(forPID: pid, with: updated)
    }

    /// Moves a single window to the front of the registry. Identifies the
    /// window by AX element pointer first, falling back to CGWindowID if AX
    /// returned a different element instance for the same window. Bypasses
    /// `applyOrdered`, which deliberately preserves existing order — so this
    /// is the only mutation path that actually changes ordering.
    private func bumpWindowToTop(element: AXUIElement, pid: pid_t) {
        let target = WindowID(element: element)
        if let index = windows.firstIndex(where: { $0.id == target }) {
            // Already at the top — skip the mutation so we don't fire a
            // spurious @Published update.
            guard index != 0 else { return }
            let window = windows.remove(at: index)
            windows.insert(window, at: 0)
            return
        }

        // AX element identity didn't match — try the system CGWindowID.
        var wid: CGWindowID = 0
        if _AXUIElementGetWindow(element, &wid) == .success,
           wid != 0,
           let index = windows.firstIndex(where: { $0.cgWindowID == wid }) {
            guard index != 0 else { return }
            let window = windows.remove(at: index)
            windows.insert(window, at: 0)
            return
        }

        // Last resort: window isn't in the registry yet. Refresh the app's
        // windows so the next focus event (or the AX-create notification we
        // raced against) lands cleanly.
        syncWindows(for: pid)
    }

    /// Looks up the app's currently focused window via AX and bumps just
    /// that one to the front. Used when the notification carries the app
    /// element rather than a window element.
    private func bumpFocusedWindowToTop(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular else {
            removeWindows(for: pid)
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &value
              ) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            // No focused window reported — refresh in place so we at least
            // pick up state changes (hide/unhide, fresh windows).
            syncWindows(for: pid)
            return
        }

        let focusedElement = value as! AXUIElement
        bumpWindowToTop(element: focusedElement, pid: pid)
    }

    private func enumerateWindows(for app: NSRunningApplication) -> [AppWindow] {
        let pid = app.processIdentifier
        guard pid > 0 else { return [] }

        let bundleID = app.bundleIdentifier ?? "pid:\(pid)"
        let displayName = app.localizedName ?? bundleID

        let appElement = AXUIElementCreateApplication(pid)

        var rawWindows: CFArray?
        guard AXUIElementCopyAttributeValues(
                appElement,
                kAXWindowsAttribute as CFString,
                0,
                256,
                &rawWindows
              ) == .success,
              let elements = rawWindows as? [AXUIElement] else {
            return []
        }

        var seen = Set<WindowID>()
        var result: [AppWindow] = []
        for element in elements where role(of: element) == kAXWindowRole as String {
            let id = WindowID(element: element)
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            if let window = makeAppWindow(
                element: element,
                bundleIdentifier: bundleID,
                processIdentifier: pid,
                appDisplayName: displayName
            ) {
                result.append(window)
            }
        }
        return result
    }

    private func makeAppWindow(
        element: AXUIElement,
        bundleIdentifier: String,
        processIdentifier: pid_t,
        appDisplayName: String
    ) -> AppWindow? {
        let title = stringAttribute(kAXTitleAttribute as CFString, of: element)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (title?.isEmpty ?? true) ? appDisplayName : (title ?? appDisplayName)
        let isMinimized = boolAttribute(kAXMinimizedAttribute as CFString, of: element) ?? false
        let windowNumber = intAttribute(axWindowNumberAttribute, of: element)
        let cgWindowID = cgWindowID(of: element)
        let frame = frameAttribute(of: element)

        return AppWindow(
            element: element,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            appDisplayName: appDisplayName,
            windowTitle: resolvedTitle,
            isMinimized: isMinimized,
            windowNumber: windowNumber,
            cgWindowID: cgWindowID,
            frame: frame
        )
    }

    private func replaceWindows(forPID pid: pid_t, with updatedWindows: [AppWindow]) {
        var next = windows
        let insertIndex = next.firstIndex(where: { $0.processIdentifier == pid }) ?? next.count
        next.removeAll { $0.processIdentifier == pid }
        next.insert(contentsOf: updatedWindows, at: min(insertIndex, next.count))
        applyOrdered(next)
    }

    private func removeWindows(for pid: pid_t) {
        lastFocusedWindowIDByPID.removeValue(forKey: pid)
        guard windows.contains(where: { $0.processIdentifier == pid }) else { return }
        windows.removeAll { $0.processIdentifier == pid }
    }

    /// Emits a preview-invalidation for the window that just lost focus
    /// (the previous focused window of `pid`), so WorkspaceService can
    /// drop its stale capture and grab a fresh one while the window is
    /// still on top. No-op when the previous and new focused windows
    /// are the same, or when we have no prior record for this pid.
    private func invalidateOutgoingFocusedPreview(pid: pid_t, newFocusedID: WindowID) {
        guard let previousID = lastFocusedWindowIDByPID[pid],
              previousID != newFocusedID,
              let outgoing = windows.first(where: { $0.id == previousID }) else {
            return
        }
        previewInvalidations.send(outgoing.windowIdentifier)
    }

    private func removeWindow(matching element: AXUIElement, pid: pid_t) {
        let target = WindowID(element: element)
        if let index = windows.firstIndex(where: { $0.id == target }) {
            windows.remove(at: index)
        } else {
            // Element pointer mismatch can happen for some apps — fall back
            // to a per-app sync to keep state correct.
            syncWindows(for: pid)
        }
    }

    private func updateFrameOrSync(element: AXUIElement, pid: pid_t) {
        let target = WindowID(element: element)
        guard let index = windows.firstIndex(where: { $0.id == target }) else {
            syncWindows(for: pid)
            return
        }

        let existing = windows[index]
        let newFrame = frameAttribute(of: element)
        guard existing.frame != newFrame else { return }

        windows[index] = AppWindow(
            element: existing.element,
            bundleIdentifier: existing.bundleIdentifier,
            processIdentifier: existing.processIdentifier,
            appDisplayName: existing.appDisplayName,
            windowTitle: existing.windowTitle,
            isMinimized: existing.isMinimized,
            windowNumber: existing.windowNumber,
            cgWindowID: existing.cgWindowID,
            frame: newFrame
        )
    }

    private func updateTitleOrSync(element: AXUIElement, pid: pid_t) {
        let target = WindowID(element: element)
        guard let index = windows.firstIndex(where: { $0.id == target }) else {
            // Title-changed can fire for non-window elements (menu items,
            // sheets); ignore unless we know the window.
            return
        }

        let existing = windows[index]
        let newTitle = stringAttribute(kAXTitleAttribute as CFString, of: element)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedTitle = newTitle.isEmpty ? existing.appDisplayName : newTitle
        guard resolvedTitle != existing.windowTitle else { return }

        windows[index] = AppWindow(
            element: existing.element,
            bundleIdentifier: existing.bundleIdentifier,
            processIdentifier: existing.processIdentifier,
            appDisplayName: existing.appDisplayName,
            windowTitle: resolvedTitle,
            isMinimized: existing.isMinimized,
            windowNumber: existing.windowNumber,
            cgWindowID: existing.cgWindowID,
            frame: existing.frame
        )
    }

    private func applyOrdered(_ snapshot: [AppWindow]) {
        // Preserve insertion order: existing windows keep their slot and
        // pick up the latest fields from the snapshot; newly-observed
        // windows are appended in the order AX returned them.
        var remaining = Set(snapshot.map(\.id))
        var orderedExisting: [AppWindow] = []
        for window in windows where remaining.contains(window.id) {
            if let updated = snapshot.first(where: { $0.id == window.id }) {
                orderedExisting.append(updated)
            } else {
                orderedExisting.append(window)
            }
            remaining.remove(window.id)
        }
        let newcomers = snapshot.filter { remaining.contains($0.id) }
        let next = orderedExisting + newcomers
        if next != windows {
            windows = next
        }
    }

    // MARK: - AX attribute helpers

    private func role(of element: AXUIElement) -> String? {
        stringAttribute(kAXRoleAttribute as CFString, of: element)
    }

    private func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func boolAttribute(_ attribute: CFString, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return (value as? NSNumber)?.boolValue
    }

    private func intAttribute(_ attribute: CFString, of element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return (value as? NSNumber)?.intValue
    }

    private func cgWindowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    private func frameAttribute(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute as CFString, of: element),
              let size = sizeAttribute(kAXSizeAttribute as CFString, of: element) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func pointAttribute(_ attribute: CFString, of element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ attribute: CFString, of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}

// AXObserver requires a free C function — bounce into the registry singleton.
private func axObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notificationName: CFString,
    context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let registry = Unmanaged<WindowRegistry>.fromOpaque(context).takeUnretainedValue()
    registry.handleNotification(
        observer: observer,
        element: element,
        notificationName: notificationName
    )
}
