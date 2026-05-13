//
//  AppDelegate.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import ApplicationServices
import Cocoa
import Sentry

import Combine
import Sparkle

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    @IBOutlet var window: NSWindow!
    private var mainWindowController: MainWindowController?
    private var permissionsWindowController: PermissionsWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var debugSnapshotWindowController: NSWindowController?
    private var debugStatusItem: NSStatusItem?
    private var debugSnapshotTextView: NSTextView?
    private var debugSnapshotCancellables = Set<AnyCancellable>()
    private let sessionID = UUID().uuidString.lowercased()
    private let sessionStartedAt = Date()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        configureSentry()

        // Bound every AX call to 1s so a hung app can't stall the main run loop.
        // Must precede any other AX work — applies process-wide.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)

        window?.orderOut(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        configureMainMenu()
        SystemDockVisibilityService.shared.recoverStaleSnapshotIfNeeded()

        if ApplicationInstallService.shared.promptToMoveToApplicationsIfNeeded() {
            return
        }

        _ = AppUpdateService.shared
        _ = ProductService.shared
        _ = LaunchpadHotKeyService.shared
        _ = LaunchpadOverlayService.shared
        AppUpdateService.shared.checkForUpdatesInBackground()
        WindowReservationService.shared.start()

        DockyPreferences.shared.applySystemDockVisibilityPreference()
        DockyPreferences.shared.applyOpenAtLoginPreference()
        TileStore.shared.syncPreferencesFromSystemDockIfNeeded()

        PermissionsService.shared.refresh()
        logSessionStart()

        if PermissionsService.shared.setupComplete {
            PermissionsService.shared.markInitialOnboardingCompleted()
            showMainWindow()
        } else {
            showPermissionsWindow(
                steps: PermissionsService.shared.setupPermissions,
                marksInitialOnboardingCompleted: true,
                showsMainWindowOnCompletion: true
            )
        }
    }

    /// Handles double-clicking a `.dockytheme` bundle (or a plain
    /// `.zip` of one) in Finder. Imports each via `ThemeManager` and
    /// opens the Themes settings pane so the user can apply the
    /// freshly installed theme.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        var importedAny = false
        var firstError: String?

        for url in urls {
            do {
                try ThemeManager.shared.importTheme(from: url)
                importedAny = true
            } catch {
                if firstError == nil {
                    firstError = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }

        if importedAny {
            showSettingsWindow(nil)
        }

        if let firstError {
            let alert = NSAlert()
            alert.messageText = "Could not import theme"
            alert.informativeText = firstError
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        logSessionEnd()

        if SystemDockVisibilityService.shared.hasSnapshot {
            SystemDockVisibilityService.shared.restore()
        }

        #if !DEBUG
        SentrySDK.close()
        #endif
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)

        if settingsWindowController == nil {
            let controller = SettingsWindowController()
            controller.onClose = { [weak self] in
                NSApp.setActivationPolicy(.accessory)
                self?.settingsWindowController = nil
            }
            settingsWindowController = controller
        }

        settingsWindowController?.showWindow(sender)
        settingsWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        AppUpdateService.shared.checkForUpdates()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) {
            return AppUpdateService.shared.canCheckForUpdates
        }

        #if DEBUG
        if menuItem.action == #selector(setFreeProductMode(_:)) {
            menuItem.state = ProductService.shared.currentTier == .free ? .on : .off
            return true
        }

        if menuItem.action == #selector(setProProductMode(_:)) {
            menuItem.state = ProductService.shared.currentTier == .pro ? .on : .off
            return true
        }
        #endif

        return true
    }

    private func showPermissionsWindow(
        steps: [Permission],
        marksInitialOnboardingCompleted: Bool,
        showsMainWindowOnCompletion: Bool
    ) {
        NSApp.setActivationPolicy(.regular)
        let controller = PermissionsWindowController(steps: steps)
        controller.onComplete = { [weak self] in
            NSApp.setActivationPolicy(.accessory)
            self?.permissionsWindowController = nil

            if marksInitialOnboardingCompleted {
                PermissionsService.shared.markInitialOnboardingCompleted()
            }

            if showsMainWindowOnCompletion {
                self?.showMainWindow()
            }
        }
        permissionsWindowController = controller
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMainWindow() {
        mainWindowController = makeMainWindowController()
        mainWindowController?.showWindow(self)
        DockyPreferences.shared.enableOpenAtLoginOnFirstLaunchIfNeeded()
    }

    private func makeMainWindowController() -> MainWindowController? {
        var topLevelObjects: NSArray?
        let didLoadNib = Bundle.main.loadNibNamed(
            "MainWindow",
            owner: nil,
            topLevelObjects: &topLevelObjects
        )

        guard
            didLoadNib,
            let mainWindow = (topLevelObjects as? [Any])?.first(where: { $0 is MainWindow }) as? MainWindow
        else {
            assertionFailure("Failed to load MainWindow.xib")
            return nil
        }

        return MainWindowController(window: mainWindow)
    }

    private func configureMainMenu() {
        let appMenu = NSApp.mainMenu?.items.first?.submenu
        if let item = appMenu?.item(withTitle: "Preferences…") ?? appMenu?.item(withTitle: "Settings…") {
            item.title = "Settings…"
            item.action = #selector(showSettingsWindow(_:))
            item.target = self
        }

        if appMenu?.item(withTitle: "Check for Updates…") == nil {
            let item = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(checkForUpdates(_:)),
                keyEquivalent: ""
            )
            item.target = self
            appMenu?.insertItem(item, at: 1)
        }

        #if DEBUG
        installDebugStatusItem()
        #endif
    }

    private func configureSentry() {
        #if DEBUG
        return
        #else
        SentrySDK.start { options in
            options.dsn = "https://5eebd9ca17d595aa7c9cdebc54a0746a@o4511308909510656.ingest.us.sentry.io/4511308910952448"
            options.sendDefaultPii = false
            options.enableCrashHandler = false
            options.enableAutoSessionTracking = false
            options.enableWatchdogTerminationTracking = false
            options.enableAppHangTracking = false
            options.enableNetworkBreadcrumbs = false
            options.tracesSampleRate = 0
            options.shutdownTimeInterval = 2
            options.experimental.enableLogs = true
            options.beforeSend = { _ in nil }
            options.beforeSendSpan = { _ in nil }
            options.beforeSendLog = { log in
                guard log.attributes["scope"]?.value as? String == "session" else {
                    return nil
                }

                return log
            }
        }
        #endif
    }

    private func logSessionStart() {
        #if !DEBUG
        SentrySDK.logger.info("Docky session started", attributes: sessionLogAttributes(phase: "start"))
        #endif
    }

    private func logSessionEnd() {
        #if !DEBUG
        var attributes = sessionLogAttributes(phase: "end")
        attributes["session.duration_ms"] = Int(Date().timeIntervalSince(sessionStartedAt) * 1000)
        SentrySDK.logger.info("Docky session ended", attributes: attributes)
        #endif
    }

    private func sessionLogAttributes(phase: String) -> [String: Any] {
        [
            "scope": "session",
            "session.id": sessionID,
            "session.phase": phase,
            "app.version": shortVersion,
            "app.build": buildNumber,
            "product.tier": ProductService.shared.currentTier.rawValue,
            "permissions.required_granted": PermissionsService.shared.allRequiredGranted,
            "permissions.setup_complete": PermissionsService.shared.setupComplete,
            "permissions.onboarding_completed": PermissionsService.shared.hasCompletedInitialOnboarding,
            "permissions.missing_required_count": PermissionsService.shared.missingRequiredPermissions.count,
            "permissions.missing_count": PermissionsService.shared.missingPermissions.count,
        ]
    }

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    #if DEBUG
    @objc private func showDebugSnapshot(_ sender: Any?) {
        DockSettingsService.shared.refresh()

        if debugSnapshotWindowController == nil {
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.importsGraphics = false
            textView.usesFindBar = true
            textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            debugSnapshotTextView = textView

            let scrollView = NSScrollView(frame: textView.frame)
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.documentView = textView

            let viewController = NSViewController()
            viewController.view = scrollView

            let window = NSWindow(contentViewController: viewController)
            window.title = "Dock Debug Snapshot"
            window.setContentSize(scrollView.frame.size)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false

            debugSnapshotWindowController = NSWindowController(window: window)
            installDebugSnapshotObservers()
        }

        refreshDebugSnapshotText()

        debugSnapshotWindowController?.showWindow(sender)
        debugSnapshotWindowController?.window?.center()
        debugSnapshotWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func pinDefaultDockAppsForLoadTest(_ sender: Any?) {
        let pinnedCount = TileStore.shared.replacePinnedAppsWithDefaultDockAppsForLoadTest()
        NSLog("[Docky] Debug load test pinned \(pinnedCount) default Dock apps")
    }

    @objc private func pinEveryAppForLoadTest(_ sender: Any?) {
        let pinnedCount = TileStore.shared.replacePinnedAppsWithEveryInstalledAppForLoadTest()
        NSLog("[Docky] Debug load test pinned \(pinnedCount) installed apps")
    }

    @objc private func resetPinnedItemsToSystemDock(_ sender: Any?) {
        let pinnedCount = TileStore.shared.resetPinnedItemsToSystemDock()
        NSLog("[Docky] Reset pinned items to \(pinnedCount) system Dock entries")
    }

    @objc private func seedDummyDebugLayout(_ sender: Any?) {
        TileStore.shared.seedDummyDebugLayout()
        NSLog("[Docky] Seeded dummy debug layout")
    }

    @objc private func loadDemoDebugLayout(_ sender: Any?) {
        TileStore.shared.loadDemoDebugLayout()
        NSLog("[Docky] Loaded demo debug layout")
    }

    @objc private func seedDummyWidgetDebugContent(_ sender: Any?) {
        RemindersService.shared.seedDummyDebugSnapshot()
        CalendarService.shared.seedDummyDebugSnapshot()
        WeatherService.shared.seedDummyDebugSnapshot()
        NSLog("[Docky] Seeded dummy widget debug content")
    }

    @objc private func showDebugOnboarding(_ sender: Any?) {
        PermissionsService.shared.refresh()
        showPermissionsWindow(
            steps: Permission.allCases,
            marksInitialOnboardingCompleted: false,
            showsMainWindowOnCompletion: false
        )
    }

    @objc private func setFreeProductMode(_ sender: Any?) {
        ProductService.shared.setDebugTier(.free)
        NSLog("[Docky] Switched debug product tier to Free")
    }

    @objc private func setProProductMode(_ sender: Any?) {
        ProductService.shared.setDebugTier(.pro)
        NSLog("[Docky] Switched debug product tier to Pro")
    }

    private func installDebugStatusItem() {
        guard debugStatusItem == nil else {
            return
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Docky"

        let debugMenu = NSMenu(title: "Docky")
        let snapshotItem = NSMenuItem(
            title: "Show Dock Preferences and Settings",
            action: #selector(showDebugSnapshot(_:)),
            keyEquivalent: ""
        )
        snapshotItem.target = self

        let loadTestItem = NSMenuItem(
            title: "Pin Default Dock Apps",
            action: #selector(pinDefaultDockAppsForLoadTest(_:)),
            keyEquivalent: ""
        )
        loadTestItem.target = self

        let pinEveryAppItem = NSMenuItem(
            title: "Pin Every App",
            action: #selector(pinEveryAppForLoadTest(_:)),
            keyEquivalent: ""
        )
        pinEveryAppItem.target = self

        let resetPinnedItemsItem = NSMenuItem(
            title: "Reset Pinned Items to System Dock",
            action: #selector(resetPinnedItemsToSystemDock(_:)),
            keyEquivalent: ""
        )
        resetPinnedItemsItem.target = self

        let seedDummyLayoutItem = NSMenuItem(
            title: "Seed Dummy Layout",
            action: #selector(seedDummyDebugLayout(_:)),
            keyEquivalent: ""
        )
        seedDummyLayoutItem.target = self

        let loadDemoLayoutItem = NSMenuItem(
            title: "Load Demo Layout",
            action: #selector(loadDemoDebugLayout(_:)),
            keyEquivalent: ""
        )
        loadDemoLayoutItem.target = self

        let seedDummyWidgetContentItem = NSMenuItem(
            title: "Seed Widget Demo Content",
            action: #selector(seedDummyWidgetDebugContent(_:)),
            keyEquivalent: ""
        )
        seedDummyWidgetContentItem.target = self

        let showOnboardingItem = NSMenuItem(
            title: "Show Onboarding",
            action: #selector(showDebugOnboarding(_:)),
            keyEquivalent: ""
        )
        showOnboardingItem.target = self

        let productModeMenu = NSMenu(title: "Product Mode")

        let freeModeItem = NSMenuItem(
            title: "Free",
            action: #selector(setFreeProductMode(_:)),
            keyEquivalent: ""
        )
        freeModeItem.target = self

        let proModeItem = NSMenuItem(
            title: "Pro",
            action: #selector(setProProductMode(_:)),
            keyEquivalent: ""
        )
        proModeItem.target = self

        productModeMenu.addItem(freeModeItem)
        productModeMenu.addItem(proModeItem)

        let productModeItem = NSMenuItem(
            title: "Product Mode",
            action: nil,
            keyEquivalent: ""
        )
        productModeItem.submenu = productModeMenu

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettingsWindow(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self

        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self

        let quitItem = NSMenuItem(
            title: "Quit Docky",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp

        debugMenu.addItem(settingsItem)
        debugMenu.addItem(checkForUpdatesItem)
        debugMenu.addItem(snapshotItem)
        debugMenu.addItem(loadTestItem)
        debugMenu.addItem(pinEveryAppItem)
        debugMenu.addItem(resetPinnedItemsItem)
        debugMenu.addItem(seedDummyLayoutItem)
        debugMenu.addItem(loadDemoLayoutItem)
        debugMenu.addItem(seedDummyWidgetContentItem)
        debugMenu.addItem(showOnboardingItem)
        debugMenu.addItem(productModeItem)
#if DEBUG
        debugMenu.addItem(makeSimulatedOSVersionMenuItem())
#endif
        debugMenu.addItem(.separator())
        debugMenu.addItem(quitItem)

        statusItem.menu = debugMenu
        debugStatusItem = statusItem
    }

#if DEBUG
    /// "Simulated OS Version" submenu. Selecting a version writes it to
    /// `FeatureGate.preferredOSVersion` and relaunches Docky so every
    /// gated path re-evaluates against the new value. Items above the
    /// real running OS are disabled — `#available` paired with the gate
    /// can clamp down but never up, so simulating a higher version
    /// would silently fall through to the real OS anyway.
    private func makeSimulatedOSVersionMenuItem() -> NSMenuItem {
        let submenu = NSMenu(title: "Simulated OS Version")
        let host = ProcessInfo.processInfo.operatingSystemVersion
        let preferred = FeatureGate.shared.preferredOSVersion

        let realOSItem = NSMenuItem(
            title: "Use Real OS (\(Self.formatOSVersion(host)))",
            action: #selector(clearSimulatedOSVersion(_:)),
            keyEquivalent: ""
        )
        realOSItem.target = self
        realOSItem.state = (preferred == nil) ? .on : .off
        submenu.addItem(realOSItem)
        submenu.addItem(.separator())

        let candidates: [(major: Int, minor: Int, name: String)] = [
            (14, 0, "Sonoma"),
            (14, 6, "Sonoma"),
            (15, 0, "Sequoia"),
            (26, 0, "Tahoe"),
        ]

        for entry in candidates {
            let version = OperatingSystemVersion(majorVersion: entry.major, minorVersion: entry.minor, patchVersion: 0)
            let item = NSMenuItem(
                title: "macOS \(entry.major).\(entry.minor) (\(entry.name))",
                action: #selector(applySimulatedOSVersion(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = version
            item.state = (preferred.map {
                $0.majorVersion == version.majorVersion && $0.minorVersion == version.minorVersion
            } ?? false) ? .on : .off
            // Can only simulate going down: a paired `#available` would
            // clamp anything above the real host back to "unavailable".
            item.isEnabled = !Self.isVersion(version, greaterThan: host)
            submenu.addItem(item)
        }

        let item = NSMenuItem(title: "Simulated OS Version", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func clearSimulatedOSVersion(_ sender: Any?) {
        FeatureGate.shared.setPreferredOSVersion(nil)
        relaunchApp()
    }

    @objc private func applySimulatedOSVersion(_ sender: NSMenuItem) {
        guard let version = sender.representedObject as? OperatingSystemVersion else { return }
        FeatureGate.shared.setPreferredOSVersion(version)
        relaunchApp()
    }

    private func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", "-a", bundlePath]
        do {
            try task.run()
        } catch {
            NSLog("[Docky] Relaunch failed: \(error.localizedDescription)")
            return
        }
        NSApp.terminate(nil)
    }

    private static func formatOSVersion(_ version: OperatingSystemVersion) -> String {
        if version.patchVersion > 0 {
            return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        }
        return "\(version.majorVersion).\(version.minorVersion)"
    }

    private static func isVersion(_ lhs: OperatingSystemVersion, greaterThan rhs: OperatingSystemVersion) -> Bool {
        if lhs.majorVersion != rhs.majorVersion { return lhs.majorVersion > rhs.majorVersion }
        if lhs.minorVersion != rhs.minorVersion { return lhs.minorVersion > rhs.minorVersion }
        return lhs.patchVersion > rhs.patchVersion
    }
#endif

    private func debugSnapshotText() -> String {
        let preferences = DockyPreferences.shared
        let dockSettings = DockSettingsService.shared

        return [
            "Docky Preferences",
            "---------------",
            "tileVerticalPadding: \(preferences.tileVerticalPadding)",
            "tileSpacing: \(preferences.tileSpacing)",
            "windowCornerRadius: \(preferences.windowCornerRadius)",
            "windowTintColor: \(preferences.windowTintColor.map { "r=\($0.red), g=\($0.green), b=\($0.blue)" } ?? "system")",
            "windowTintOpacity: \(preferences.effectiveWindowTintOpacity)",
            "windowBackgroundImagePath: \(preferences.windowBackgroundImagePath ?? "none")",
            "windowPosition: \(preferences.windowPosition.rawValue)",
            "windowDisplayTarget: \(preferences.windowDisplayTarget.rawValue)",
            "windowSpaceBehavior: \(preferences.windowSpaceBehavior.rawValue)",
            "autohidesWindow: \(preferences.autohidesWindow)",
            "autohideWindowDelay: \(preferences.autohideWindowDelay)",
            "showsActivePinnedSeparator: \(preferences.showsActivePinnedSeparator)",
            "activeIndicatorShape: \(preferences.activeIndicatorShape.rawValue)",
            "pinnedAppBundleIdentifiers: \(formattedJSON(preferences.pinnedAppBundleIdentifiers))",
            "pinnedItems: \(formattedJSON(preferences.pinnedItems))",
            "widgetPlacements: \(formattedJSON(preferences.widgetPlacements))",
            "",
            "Dock Settings",
            "-------------",
            "orientation: \(dockSettings.orientation.rawValue)",
            "tileSize: \(dockSettings.tileSize)",
            "largeSize: \(dockSettings.largeSize)",
            "magnification: \(dockSettings.magnification)",
            "autohide: \(dockSettings.autohide)",
            "autohideDelay: \(dockSettings.autohideDelay)",
            "autohideTimeModifier: \(dockSettings.autohideTimeModifier)",
            "minimizeEffect: \(dockSettings.minimizeEffect.rawValue)",
            "minimizeToApplication: \(dockSettings.minimizeToApplication)",
            "showRecents: \(dockSettings.showRecents)",
            "showProcessIndicators: \(dockSettings.showProcessIndicators)"
        ].joined(separator: "\n")
    }

    private func formattedJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }

        return string
    }

    private func installDebugSnapshotObservers() {
        guard debugSnapshotCancellables.isEmpty else {
            return
        }

        // `DockyPreferences` is `@Observable` (no `objectWillChange`).
        // Refresh on any read of `debugSnapshotText()` — the
        // Observation framework tracks every property the snapshot
        // touches and re-runs this closure when any of them change.
        observeChanges { [weak self] in
            self?.refreshDebugSnapshotText()
        }
        .store(in: &debugSnapshotCancellables)

        DockSettingsService.shared.objectWillChange
            .sink { [weak self] _ in
                self?.refreshDebugSnapshotText()
            }
            .store(in: &debugSnapshotCancellables)
    }

    private func refreshDebugSnapshotText() {
        debugSnapshotTextView?.string = debugSnapshotText()
    }
    #endif
}
