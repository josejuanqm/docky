//
//  AppDelegate.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import ApplicationServices
import Cocoa

import Combine
import Sparkle
import UniformTypeIdentifiers

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

    func applicationDidFinishLaunching(_ aNotification: Notification) {
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
        _ = LaunchpadHotKeyService.shared
        _ = LaunchpadOverlayService.shared
        AppUpdateService.shared.checkForUpdatesInBackground()
        WindowReservationService.shared.start()
        DockBadgeService.shared.start()

        // Must precede TileStore.syncPreferencesFromSystemDockIfNeeded
        // below: persisted dock contents may reference external widget
        // identifiers, and TileStore filters out unknown widgets when
        // rehydrating.
        ExternalWidgetLoader.shared.discoverAndLoad()

        DockyPreferences.shared.applySystemDockVisibilityPreference()
        DockyPreferences.shared.applyOpenAtLoginPreference()
        TileStore.shared.syncPreferencesFromSystemDockIfNeeded()
        ProfileTriggerEngine.shared.start()

        PermissionsService.shared.refresh()

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

    /// Handles two entry points:
    ///  - Double-clicking a `.dockytheme` bundle (or `.zip` of one) in
    ///    Finder → imports each via `ThemeManager` and opens Settings.
    ///  - `docky://<host>/<path>` deep links from automation tools
    ///    (BTT, Raycast, Shortcuts, Stream Deck, ...). See
    ///    `handleDockyURL` for the routing table.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }

        let dockyURLs = urls.filter { $0.scheme == "docky" }
        let themeURLs = urls.filter { $0.scheme != "docky" }

        for url in dockyURLs {
            handleDockyURL(url)
        }

        guard !themeURLs.isEmpty else { return }

        var importedAny = false
        var firstError: String?

        for url in themeURLs {
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
            alert.messageText = String(localized: "Could not import theme")
            alert.informativeText = firstError
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
        }
    }

    /// Routes a `docky://` URL to the matching handler.
    ///
    /// Routing table:
    ///  - `docky://install-widget?url=<https://...>` — Widget Store install.
    ///  - `docky://launchpad[/show|/hide|/toggle]` — launchpad overlay.
    ///  - `docky://start-menu[/show|/hide|/toggle]` — start menu overlay.
    ///  - `docky://dock[/show|/hide|/toggle]` — flips `autohidesWindow`.
    ///  - `docky://profile/next` or `/previous` — cycle the active profile.
    ///  - `docky://profile/<id-or-name>` or `?id=…` / `?name=…` — set the
    ///    active profile directly.
    ///
    /// Bare host with no path defaults to toggle for the overlay actions.
    /// Unknown actions are ignored silently so external automations don't
    /// surface user-visible errors when Docky doesn't recognize the URL.
    private func handleDockyURL(_ url: URL) {
        let action = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch action {
        case "install-widget":
            handleInstallWidgetURL(url)
        case "launchpad":
            applyOverlayAction(
                path: path,
                show: { LaunchpadOverlayService.shared.present() },
                hide: { LaunchpadOverlayService.shared.dismiss() },
                toggle: { LaunchpadOverlayService.shared.toggle() }
            )
        case "start-menu":
            applyOverlayAction(
                path: path,
                show: { StartMenuService.shared.present() },
                hide: { StartMenuService.shared.dismiss() },
                toggle: { StartMenuService.shared.toggle() }
            )
        case "dock":
            applyDockAction(path: path)
        case "profile":
            applyProfileAction(path: path, queryItems: queryItems)
        default:
            break
        }
    }

    private func applyOverlayAction(
        path: String,
        show: () -> Void,
        hide: () -> Void,
        toggle: () -> Void
    ) {
        switch path {
        case "/show", "/present":
            show()
        case "/hide", "/dismiss":
            hide()
        default:
            toggle()
        }
    }

    private func applyDockAction(path: String) {
        let preferences = DockyPreferences.shared
        switch path {
        case "/show":
            preferences.autohidesWindow = false
        case "/hide":
            preferences.autohidesWindow = true
        default:
            preferences.autohidesWindow.toggle()
        }
    }

    private func applyProfileAction(path: String, queryItems: [URLQueryItem]) {
        let service = ProfileService.shared
        let profiles = service.profiles
        guard !profiles.isEmpty else { return }

        if let id = queryItems.first(where: { $0.name == "id" })?.value,
           profiles.contains(where: { $0.id == id }) {
            service.setActiveProfile(id: id)
            return
        }

        if let name = queryItems.first(where: { $0.name == "name" })?.value,
           let match = profiles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            service.setActiveProfile(id: match.id)
            return
        }

        let currentIndex = profiles.firstIndex(where: { $0.id == service.activeProfileID }) ?? 0
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        switch trimmedPath {
        case "next":
            let next = profiles[(currentIndex + 1) % profiles.count]
            service.setActiveProfile(id: next.id)
        case "previous", "prev":
            let prev = profiles[(currentIndex - 1 + profiles.count) % profiles.count]
            service.setActiveProfile(id: prev.id)
        case "":
            break
        default:
            if let exact = profiles.first(where: { $0.id == trimmedPath }) {
                service.setActiveProfile(id: exact.id)
            } else if let nameMatch = profiles.first(where: { $0.name.caseInsensitiveCompare(trimmedPath) == .orderedSame }) {
                service.setActiveProfile(id: nameMatch.id)
            }
        }
    }

    /// `docky://install-widget?url=<downloadURL>` from the marketplace
    /// website. Gated on Pro tier; surfaces an alert with the install
    /// outcome so the user knows whether to restart Docky.
    private func handleInstallWidgetURL(_ url: URL) {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let downloadString = components.queryItems?.first(where: { $0.name == "url" })?.value,
            let downloadURL = URL(string: downloadString),
            let scheme = downloadURL.scheme?.lowercased(),
            scheme == "https"
        else {
            presentInstallAlert(title: "Invalid widget install link", message: "The link did not include a valid HTTPS download URL.", style: .warning)
            return
        }

        Task { @MainActor in
            do {
                let staged = try await MarketplaceClient.shared.downloadBundle(from: downloadURL)
                _ = try ExternalWidgetLoader.shared.installBundle(from: staged)
                try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())

                let alert = NSAlert()
                alert.messageText = String(localized: "Widget installed")
                alert.informativeText = String(localized: "Restart Docky to start using \(downloadURL.lastPathComponent).")
                alert.alertStyle = .informational
                alert.addButton(withTitle: String(localized: "Restart Docky"))
                alert.addButton(withTitle: String(localized: "Later"))
                if alert.runModal() == .alertFirstButtonReturn {
                    NSApp.terminate(nil)
                }
            } catch {
                presentInstallAlert(
                    title: String(localized: "Couldn't install widget"),
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                    style: .warning
                )
            }
        }
    }

    private func presentInstallAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if SystemDockVisibilityService.shared.hasSnapshot {
            SystemDockVisibilityService.shared.restore()
        }
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
        // Locate the standard Preferences/Settings item by its "," key equivalent
        // rather than its title, so the lookup keeps working once the menu is
        // localized (a title-based lookup would miss the translated item).
        if let item = appMenu?.items.first(where: { $0.keyEquivalent == "," }) {
            item.title = String(localized: "Settings…")
            item.action = #selector(showSettingsWindow(_:))
            item.target = self
        }

        let checkForUpdatesTitle = String(localized: "Check for Updates…")
        if appMenu?.item(withTitle: checkForUpdatesTitle) == nil {
            let item = NSMenuItem(
                title: checkForUpdatesTitle,
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

        let overrideSettingsItem = NSMenuItem(
            title: "Override Docky Settings with plist…",
            action: #selector(overrideSettingsWithPlist(_:)),
            keyEquivalent: ""
        )
        overrideSettingsItem.target = self

        let windowPreviewsItem = NSMenuItem(
            title: "Window Previews…",
            action: #selector(showWindowPreviewsDebug(_:)),
            keyEquivalent: ""
        )
        windowPreviewsItem.target = self

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
        debugMenu.addItem(overrideSettingsItem)
        debugMenu.addItem(windowPreviewsItem)
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

    /// Opens the DEBUG-only window-previews inspector: a table of
    /// every tracked `AppWindow` paired with the thumbnail Docky is
    /// currently caching for it. Useful for diagnosing wrong /
    /// stale capture content (e.g. the menu bar standing in for an
    /// app's actual window).
    @objc private func showWindowPreviewsDebug(_ sender: Any?) {
        #if DEBUG
        WindowPreviewsDebugWindowController.shared.show()
        #endif
    }

    /// Replace every `docky.*` UserDefaults key with the contents of
    /// a plist (e.g. `docky-defaults.plist` from a user's feedback
    /// bundle). The user is prompted to pick the file; existing
    /// `docky.*` keys are cleared first so the resulting state is a
    /// faithful reproduction of the source, not a merge. Docky then
    /// relaunches so every preference observer re-reads.
    @objc private func overrideSettingsWithPlist(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Override"
        panel.message = "Pick a docky-defaults.plist (from a feedback bundle, etc.) to replace all docky.* UserDefaults keys."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let raw = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dict = raw as? [String: Any] else {
                throw NSError(domain: "DockyDebugOverride", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Top-level plist value isn't a dictionary."
                ])
            }

            let dockyKeys = dict.filter { $0.key.hasPrefix("docky.") }
            guard !dockyKeys.isEmpty else {
                throw NSError(domain: "DockyDebugOverride", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "No docky.* keys found in \(url.lastPathComponent)."
                ])
            }

            let confirm = NSAlert()
            confirm.messageText = "Override \(dockyKeys.count) docky.* keys?"
            confirm.informativeText = "Existing docky.* UserDefaults will be cleared first, then replaced with the values from \(url.lastPathComponent). Docky will relaunch after."
            confirm.addButton(withTitle: "Override and Relaunch")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }

            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("docky.") {
                defaults.removeObject(forKey: key)
            }
            for (key, value) in dockyKeys {
                defaults.set(value, forKey: key)
            }
            defaults.synchronize()

            relaunchApp()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't apply override"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
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

        observeChanges { [weak self] in
            // Touch the properties the debug snapshot prints so the
            // Observation framework wires this closure to re-fire on
            // every relevant DockSettingsService change.
            let settings = DockSettingsService.shared
            _ = settings.orientation
            _ = settings.tileSize
            _ = settings.largeSize
            _ = settings.magnification
            _ = settings.autohide
            _ = settings.autohideDelay
            _ = settings.autohideTimeModifier
            _ = settings.minimizeEffect
            _ = settings.minimizeToApplication
            _ = settings.showRecents
            _ = settings.showProcessIndicators
            self?.refreshDebugSnapshotText()
        }
        .store(in: &debugSnapshotCancellables)
    }

    private func refreshDebugSnapshotText() {
        debugSnapshotTextView?.string = debugSnapshotText()
    }
    #endif
}
