//
//  TileStore.swift
//  Docky
//
//  Composes the visible dock tile row from three sources:
//    - `persistent-apps`   → pinned apps + spacers (left section)
//    - running apps that aren't pinned → injected between pinned and folders
//    - `persistent-others` → folders + spacers (right section)
//
//  Refresh signals: dock plist change and workspace running-apps changes.
//

import AppKit
import Combine
import os.log

final class TileStore: ObservableObject {
    static let shared = TileStore()

    private static let logger = Logger(subsystem: "gt.quintero.Docky", category: "TileStore")

    @Published private(set) var tiles: [Tile] = []

    private static let changeNotification = Notification.Name("com.apple.dock.prefchanged")
    private static let hasImportedSystemDockPreferencesKey = "docky.tileStore.hasImportedSystemDockPreferences"
    private static let demoDebugPinnedAppNames = [
        "Dia",
        "Notes",
        "Calendar",
        "Music",
        "Messages",
        "Slack",
        "Mail",
        "Xcode",
        "Figma",
        "Ghostty",
        "Linear"
    ]

    private var pinnedTiles: [Tile] = []
    private var systemOtherTiles: [Tile] = []
    private var systemOtherTilesByID: [String: Tile] = [:]
    private var trailingTiles: [Tile] = []
    private var dockPinnedTilesByBundleIdentifier: [String: Tile] = [:]
    private var expandedInlineAppFolderIDs: Set<String> = []
    /// Currently displayed unpinned running apps, in visual order. May contain
    /// one "ghost" entry at the end, an app that recently exited but sat at
    /// the rightmost position, preserved until something newer takes its slot.
    private var displayedRunning: [RunningApp] = []

    private var notificationObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private let preferences = DockyPreferences.shared
    private let mediaPlayback = MediaPlaybackService.shared
    private let defaults = UserDefaults.standard

    private init() {
        reloadSystemDockState(syncPreferencesFromSystemDock: false)
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.changeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadSystemDockState(syncPreferencesFromSystemDock: false)
        }
        WorkspaceService.shared.$runningApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildTiles() }
            .store(in: &cancellables)
        WorkspaceService.shared.$minimizedWindows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildTiles() }
            .store(in: &cancellables)
        // `DockyPreferences` is `@Observable`. We observe each
        // property bundle through `observeChanges` so the same change
        // signal fires only when the relevant property mutates.
        // (`.dropFirst()` skipped the Combine initial emission; the
        // Observation closure runs once on install to register reads
        //, calling `rebuildTiles` etc. then is safe and idempotent.)
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.pinnedItems
            self?.synchronizeAppWidgetDisplaysWithFolders()
            self?.refreshPinnedTilesFromPreferences()
            self?.rebuildTiles()
        }
        .store(in: &cancellables)
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.widgetPlacements
            self?.rebuildTiles()
        }
        .store(in: &cancellables)
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.appWidgetDisplays
            self?.rebuildTiles()
        }
        .store(in: &cancellables)
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.hiddenAppBundleIdentifiers
            self?.refreshPinnedTilesFromPreferences()
            self?.rebuildTiles()
        }
        .store(in: &cancellables)
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.trailingItems
            self?.refreshTrailingTilesFromPreferences()
            self?.rebuildTiles()
        }
        .store(in: &cancellables)
        observeChanges { [weak self] in
            _ = DockyPreferences.shared.showsGroupedOpenedAppsInDock
            _ = DockyPreferences.shared.effectiveShowsActivePinnedSeparator
            _ = DockyPreferences.shared.showsRunningApps
            _ = DockyPreferences.shared.showsMinimizedWindows
            _ = DockyPreferences.shared.enablesShelveMode
            _ = DockyPreferences.shared.shelveHidesFinder
            _ = DockyPreferences.shared.shelveHidesTrash
            _ = DockyPreferences.shared.hidesRecentApps
            self?.rebuildTiles()
        }
        .store(in: &cancellables)
        mediaPlayback.$statesByBundleIdentifier
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPinnedTilesFromPreferences()
                self?.refreshTrailingTilesFromPreferences()
                self?.rebuildTiles()
            }
            .store(in: &cancellables)
    }

    deinit {
        if let notificationObserver {
            DistributedNotificationCenter.default().removeObserver(notificationObserver)
        }
    }

    func refresh() {
        reloadSystemDockState(syncPreferencesFromSystemDock: false)
    }

    func refreshAfterDockyEditedSystemDock() {
        reloadSystemDockState(syncPreferencesFromSystemDock: true)
    }

    func syncPreferencesFromSystemDockIfNeeded() {
        guard !hasImportedSystemDockPreferences else {
            return
        }

        guard preferences.pinnedItems.isEmpty, preferences.trailingItems.isEmpty else {
            hasImportedSystemDockPreferences = true
            return
        }

        reloadSystemDockState(syncPreferencesFromSystemDock: true)
        hasImportedSystemDockPreferences = true
    }

    private func reloadSystemDockState(syncPreferencesFromSystemDock: Bool) {
        guard let plist = DockPlistReader.read() else {
            dockPinnedTilesByBundleIdentifier = [:]
            pinnedTiles = []
            systemOtherTiles = []
            systemOtherTilesByID = [:]
            refreshPinnedTilesFromPreferences()
            refreshTrailingTilesFromPreferences()
            rebuildTiles()
            return
        }
        let apps = (plist["persistent-apps"] as? [[String: Any]]) ?? []
        let others = (plist["persistent-others"] as? [[String: Any]]) ?? []
        let refreshedPinnedTiles = apps.enumerated().compactMap { index, entry in
            Self.parse(entry: entry, fallbackID: Self.fallbackTileID(for: entry, at: index, section: "persistent-apps"))
        }
        dockPinnedTilesByBundleIdentifier = Dictionary(
            refreshedPinnedTiles.compactMap { tile in
                bundleIdentifier(of: tile).map { ($0, tile) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        if syncPreferencesFromSystemDock {
            seedPinnedPreferencesIfNeeded(from: refreshedPinnedTiles)
            mergePinnedPreferencesAdditionsIfNeeded(from: refreshedPinnedTiles)
        }
        synchronizeAppWidgetDisplaysWithFolders()
        refreshPinnedTilesFromPreferences()
        systemOtherTiles = others.enumerated().compactMap { index, entry in
            Self.parse(entry: entry, fallbackID: Self.fallbackTileID(for: entry, at: index, section: "persistent-others"))
        }
        systemOtherTilesByID = Dictionary(uniqueKeysWithValues: systemOtherTiles.map { ($0.id, $0) })
        if syncPreferencesFromSystemDock {
            refreshTrailingPreferencesIfNeeded()
        }
        refreshTrailingTilesFromPreferences()
        rebuildTiles()
    }

    private var hasImportedSystemDockPreferences: Bool {
        get { defaults.bool(forKey: Self.hasImportedSystemDockPreferencesKey) }
        set { defaults.set(newValue, forKey: Self.hasImportedSystemDockPreferencesKey) }
    }

    func isPinnedReorderable(tileID: String) -> Bool {
        pinnedTiles.contains { $0.id == tileID }
    }

    func isTrailingReorderable(tileID: String) -> Bool {
        trailingTiles.contains { $0.id == tileID }
    }

    func isPinned(bundleIdentifier: String) -> Bool {
        preferences.pinnedItems.contains {
            ($0.kind == .app && $0.bundleIdentifier == bundleIdentifier)
                || ($0.kind == .appFolder && $0.folderBundleIdentifiers.contains(bundleIdentifier))
        }
    }

    func isAppInFolder(bundleIdentifier: String) -> Bool {
        guard !bundleIdentifier.isEmpty else {
            return false
        }

        return preferences.pinnedItems.contains {
            $0.kind == .appFolder && $0.folderBundleIdentifiers.contains(bundleIdentifier)
        }
    }

    @discardableResult
    func setPinnedApp(bundleIdentifier: String, pinned: Bool) -> Bool {
        guard !bundleIdentifier.isEmpty, bundleIdentifier != Self.finderBundleID else {
            return false
        }

        var pinnedItems = preferences.pinnedItems

        if pinned {
            guard !pinnedItems.contains(where: { $0.kind == .app && $0.bundleIdentifier == bundleIdentifier }) else {
                return false
            }
            pinnedItems.append(.app(bundleIdentifier: bundleIdentifier))
        } else {
            guard pinnedItems.contains(where: { $0.kind == .app && $0.bundleIdentifier == bundleIdentifier }) else {
                return false
            }
            pinnedItems.removeAll { $0.kind == .app && $0.bundleIdentifier == bundleIdentifier }
        }

        preferences.pinnedItems = pinnedItems
        refreshPinnedTilesFromPreferences()
        rebuildTiles()
        return true
    }

    func setPinnedTileOrder(ids: [String]) {
        TileStore.logger.info("setPinnedTileOrder called with ids.count=\(ids.count) pinnedTiles.count=\(self.pinnedTiles.count)")
        guard ids.count == pinnedTiles.count else {
            TileStore.logger.warning("setPinnedTileOrder early return: count mismatch ids=\(ids.count) pinnedTiles=\(self.pinnedTiles.count)")
            return
        }

        let tilesByID = Dictionary(uniqueKeysWithValues: pinnedTiles.map { ($0.id, $0) })
        let reorderedTiles = ids.compactMap { tilesByID[$0] }
        guard reorderedTiles.count == pinnedTiles.count else {
            TileStore.logger.warning("setPinnedTileOrder: reorderedTiles count mismatch: \(reorderedTiles.count) vs \(self.pinnedTiles.count)")
            return
        }

        let allItemIDs = preferences.pinnedItems.map { Self.pinnedTileID(for: $0) }
        let idsSet = Set(ids)
        let filteredItems = preferences.pinnedItems.filter { idsSet.contains(Self.pinnedTileID(for: $0)) }

        let itemsByID = Dictionary(uniqueKeysWithValues: filteredItems.map { (Self.pinnedTileID(for: $0), $0) })
        let reorderedItems = ids.compactMap { itemsByID[$0] }

        TileStore.logger.info("setPinnedTileOrder: applying reorder, reorderedItems count=\(reorderedItems.count)")
        pinnedTiles = reorderedTiles
        preferences.pinnedItems = reorderedItems
        rebuildTiles()
    }

    @discardableResult
    func replacePinnedAppsWithDefaultDockAppsForLoadTest() -> Int {
        let installedBundleIdentifiers = Self.defaultDockLoadTestBundleIdentifiers.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }

        preferences.pinnedItems = installedBundleIdentifiers.map(PinnedTileItem.app(bundleIdentifier:))
        refreshPinnedTilesFromPreferences()
        rebuildTiles()
        return installedBundleIdentifiers.count
    }

    @discardableResult
    func replacePinnedAppsWithEveryInstalledAppForLoadTest() -> Int {
        let installedBundleIdentifiers = Self.installedApplicationBundleIdentifiers()
        preferences.pinnedItems = installedBundleIdentifiers.map(PinnedTileItem.app(bundleIdentifier:))
        refreshPinnedTilesFromPreferences()
        rebuildTiles()
        return installedBundleIdentifiers.count
    }

    @discardableResult
    func resetPinnedItemsToSystemDock() -> Int {
        guard let plist = DockPlistReader.read() else {
            return 0
        }

        let apps = (plist["persistent-apps"] as? [[String: Any]]) ?? []
        let systemPinnedTiles = apps.enumerated().compactMap { index, entry in
            Self.parse(entry: entry, fallbackID: Self.fallbackTileID(for: entry, at: index, section: "persistent-apps"))
        }
        let systemPinnedItems = systemPinnedTiles.compactMap(Self.pinnedItem(from:))
        guard !systemPinnedItems.isEmpty else {
            return 0
        }

        preferences.pinnedItems = systemPinnedItems
        refreshPinnedTilesFromPreferences()
        rebuildTiles()
        return systemPinnedItems.count
    }

    func seedDummyDebugLayout() {
        let diaBundleIdentifier = Self.resolveInstalledAppBundleIdentifier(named: "Dia")
        let slackBundleIdentifier = Self.resolveInstalledAppBundleIdentifier(named: "Slack")
        let appFolderBundleIdentifiers = ["Xcode", "Ghostty", "Symbols"].compactMap {
            Self.resolveInstalledAppBundleIdentifier(named: $0)
        }

        var pinnedItems: [PinnedTileItem] = []
        if let diaBundleIdentifier {
            pinnedItems.append(.app(bundleIdentifier: diaBundleIdentifier))
        }
        if let slackBundleIdentifier {
            pinnedItems.append(.app(bundleIdentifier: slackBundleIdentifier))
        }
        if appFolderBundleIdentifiers.count >= 2 {
            pinnedItems.append(.appFolder(
                displayName: "Folder",
                bundleIdentifiers: appFolderBundleIdentifiers,
                displayMode: .grid,
                contentViewMode: .grid
            ))
        } else {
            pinnedItems.append(contentsOf: appFolderBundleIdentifiers.map(PinnedTileItem.app(bundleIdentifier:)))
        }

        let downloadsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
        preferences.pinnedItems = pinnedItems
        var trailingItems: [TrailingTileItem] = []
        if ProductService.shared.availability(for: .smartStack, context: .newPlacement).allowsNewPlacement {
            trailingItems.append(.smartStack())
        }
        trailingItems.append(.folder(
            url: downloadsURL,
            displayName: "Downloads",
            displayMode: .folder,
            contentViewMode: .grid
        ))
        preferences.trailingItems = trailingItems
        refreshPinnedTilesFromPreferences()
        refreshTrailingTilesFromPreferences()
        rebuildTiles()
    }

    func loadDemoDebugLayout() {
        let pinnedAppBundleIdentifiers = Self.demoDebugPinnedAppNames.compactMap {
            Self.resolveInstalledAppBundleIdentifier(named: $0)
        }
        let downloadsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)

        preferences.pinnedItems = pinnedAppBundleIdentifiers.map(PinnedTileItem.app(bundleIdentifier:))

        var trailingItems: [TrailingTileItem] = []
        if ProductService.shared.availability(for: .smartStack, context: .newPlacement).allowsNewPlacement {
            trailingItems.append(.smartStack())
        }
        trailingItems.append(.folder(
            url: downloadsURL,
            displayName: "Downloads",
            displayMode: .folder,
            contentViewMode: .grid
        ))
        trailingItems.append(.trash())
        preferences.trailingItems = trailingItems

        refreshPinnedTilesFromPreferences()
        refreshTrailingTilesFromPreferences()
        rebuildTiles()
    }

    @discardableResult
    func pinApp(bundleIdentifier: String, at destinationIndex: Int) -> Bool {
        guard !bundleIdentifier.isEmpty else {
            return false
        }

        if !isPinned(bundleIdentifier: bundleIdentifier) {
            guard setPinnedApp(bundleIdentifier: bundleIdentifier, pinned: true) else {
                return false
            }
        }

        guard let pinnedTile = pinnedTiles.first(where: { self.bundleIdentifier(of: $0) == bundleIdentifier }) else {
            return false
        }

        var reorderedIDs = pinnedTiles.map(\.id)
        reorderedIDs.removeAll { $0 == pinnedTile.id }
        let clampedDestinationIndex = min(max(destinationIndex, 0), reorderedIDs.count)
        reorderedIDs.insert(pinnedTile.id, at: clampedDestinationIndex)
        setPinnedTileOrder(ids: reorderedIDs)
        return true
    }

    @discardableResult
    func groupApp(bundleIdentifier: String, intoTileID targetTileID: String) -> Bool {
        groupApps(bundleIdentifiers: [bundleIdentifier], intoTileID: targetTileID)
    }

    @discardableResult
    func groupApps(bundleIdentifiers: [String], intoTileID targetTileID: String) -> Bool {
        guard let targetIndex = preferences.pinnedItems.firstIndex(where: { Self.pinnedTileID(for: $0) == targetTileID }) else {
            return false
        }

        let targetItem = preferences.pinnedItems[targetIndex]
        let normalizedBundleIdentifiers = normalizedGroupedAppBundleIdentifiers(bundleIdentifiers)

        switch targetItem.kind {
        case .app:
            guard let targetBundleIdentifier = targetItem.bundleIdentifier else {
                return false
            }

            let sourceBundleIdentifiers = normalizedBundleIdentifiers.filter { $0 != targetBundleIdentifier }
            guard !sourceBundleIdentifiers.isEmpty else {
                return false
            }

            let folderBundleIdentifiers = [targetBundleIdentifier] + sourceBundleIdentifiers
            let folderApps = folderBundleIdentifiers.compactMap(Self.makeAppTile(bundleIdentifier:))
            let seededFolderName = appFolderSeedName(for: folderApps)
            let createdFolder = PinnedTileItem.appFolder(
                displayName: seededFolderName,
                bundleIdentifiers: folderBundleIdentifiers,
                displayMode: .grid,
                contentViewMode: .grid
            )

            var updatedItems = removingGroupedApps(sourceBundleIdentifiers, replacingTargetTileID: targetTileID)
            let insertionIndex = min(
                groupedAppInsertionIndex(before: targetIndex, removing: sourceBundleIdentifiers),
                updatedItems.count
            )
            updatedItems.insert(createdFolder, at: insertionIndex)
            preferences.pinnedItems = updatedItems
            refreshPinnedTilesFromPreferences()
            rebuildTiles()
            suggestAppFolderNameIfNeeded(
                folderID: createdFolder.id,
                expectedDisplayName: seededFolderName,
                apps: folderApps
            )
            return true
        case .appFolder:
            let sourceBundleIdentifiers = normalizedBundleIdentifiers.filter {
                !targetItem.folderBundleIdentifiers.contains($0)
            }
            guard !sourceBundleIdentifiers.isEmpty else {
                return false
            }

            var updatedItems = removingGroupedApps(sourceBundleIdentifiers)
            guard let folderIndex = updatedItems.firstIndex(where: { Self.pinnedTileID(for: $0) == targetTileID }) else {
                return false
            }

            let folderItem = updatedItems[folderIndex]
            updatedItems[folderIndex] = .appFolder(
                id: folderItem.id,
                displayName: folderItem.folderDisplayName ?? "Folder",
                bundleIdentifiers: folderItem.folderBundleIdentifiers + sourceBundleIdentifiers,
                displayMode: folderItem.appFolderDisplayMode ?? .grid,
                contentViewMode: folderItem.folderContentViewMode ?? .grid
            )
            preferences.pinnedItems = updatedItems
            refreshPinnedTilesFromPreferences()
            rebuildTiles()
            return true
        case .launchpad, .widget, .smartStack, .spacer, .flexibleSpacer, .divider:
            return false
        }
    }

    func ungroupAppFolder(tileID: String) {
        guard let itemIndex = preferences.pinnedItems.firstIndex(where: { Self.pinnedTileID(for: $0) == tileID }),
              preferences.pinnedItems[itemIndex].kind == .appFolder else {
            return
        }

        let folderItem = preferences.pinnedItems[itemIndex]
        expandedInlineAppFolderIDs.remove(folderItem.id)
        let replacementItems = folderItem.folderBundleIdentifiers.map(PinnedTileItem.app(bundleIdentifier:))
        var pinnedItems = preferences.pinnedItems
        pinnedItems.remove(at: itemIndex)
        pinnedItems.insert(contentsOf: replacementItems, at: itemIndex)
        preferences.pinnedItems = pinnedItems
        refreshPinnedTilesFromPreferences()
        rebuildTiles()
    }

    func renameAppFolder(tileID: String, displayName: String) {
        guard let itemIndex = preferences.pinnedItems.firstIndex(where: { Self.pinnedTileID(for: $0) == tileID }),
              preferences.pinnedItems[itemIndex].kind == .appFolder else {
            return
        }

        let normalizedDisplayName = normalizeAppFolderDisplayName(displayName)
        let existingItem = preferences.pinnedItems[itemIndex]
        guard existingItem.folderDisplayName != normalizedDisplayName else {
            return
        }

        var pinnedItems = preferences.pinnedItems
        pinnedItems[itemIndex] = .appFolder(
            id: existingItem.id,
            displayName: normalizedDisplayName,
            bundleIdentifiers: existingItem.folderBundleIdentifiers,
            displayMode: existingItem.appFolderDisplayMode ?? .grid,
            contentViewMode: existingItem.folderContentViewMode ?? .grid
        )
        preferences.pinnedItems = pinnedItems
        refreshPinnedTilesFromPreferences()
        rebuildTiles()
    }

    func presentRenameAppFolderPrompt(tileID: String) {
        guard let item = pinnedItem(forTileID: tileID),
              item.kind == .appFolder else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Rename Folder"
        alert.informativeText = "Choose a name for this app folder."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = item.folderDisplayName ?? "Folder"
        textField.placeholderString = "Folder"
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        renameAppFolder(tileID: tileID, displayName: textField.stringValue)
    }

    func removeAppFromFolder(tileID: String, bundleIdentifier: String) {
        guard let itemIndex = preferences.pinnedItems.firstIndex(where: { Self.pinnedTileID(for: $0) == tileID }),
              preferences.pinnedItems[itemIndex].kind == .appFolder else {
            return
        }

        let existingItem = preferences.pinnedItems[itemIndex]
        let remainingBundleIdentifiers = existingItem.folderBundleIdentifiers.filter { $0 != bundleIdentifier }
        guard remainingBundleIdentifiers.count != existingItem.folderBundleIdentifiers.count else {
            return
        }

        var pinnedItems = preferences.pinnedItems
        switch remainingBundleIdentifiers.count {
        case 0:
            expandedInlineAppFolderIDs.remove(existingItem.id)
            pinnedItems.remove(at: itemIndex)
        case 1:
            expandedInlineAppFolderIDs.remove(existingItem.id)
            pinnedItems[itemIndex] = .app(bundleIdentifier: remainingBundleIdentifiers[0])
        default:
            pinnedItems[itemIndex] = .appFolder(
                id: existingItem.id,
                displayName: existingItem.folderDisplayName ?? "Folder",
                bundleIdentifiers: remainingBundleIdentifiers,
                displayMode: existingItem.appFolderDisplayMode ?? .grid,
                contentViewMode: existingItem.folderContentViewMode ?? .grid
            )
        }

        preferences.pinnedItems = pinnedItems
        refreshPinnedTilesFromPreferences()
        rebuildTiles()
    }

    func setAppFolderContentViewMode(tileID: String, mode: FolderTileContentViewMode) {
        guard let itemIndex = preferences.pinnedItems.firstIndex(where: { Self.pinnedTileID(for: $0) == tileID }),
              preferences.pinnedItems[itemIndex].kind == .appFolder else {
            return
        }

        let existingItem = preferences.pinnedItems[itemIndex]
        guard (existingItem.folderContentViewMode ?? .grid) != mode else {
            return
        }

        var pinnedItems = preferences.pinnedItems
        if mode != .inline {
            expandedInlineAppFolderIDs.remove(existingItem.id)
        }
        pinnedItems[itemIndex] = PinnedTileItem(
            id: existingItem.id,
            kind: existingItem.kind,
            bundleIdentifier: existingItem.bundleIdentifier,
            folderDisplayName: existingItem.folderDisplayName,
            folderBundleIdentifiers: existingItem.folderBundleIdentifiers,
            appFolderDisplayMode: existingItem.appFolderDisplayMode,
            folderContentViewMode: mode,
            widgetKind: existingItem.widgetKind,
            widgetOwnerBundleIdentifier: existingItem.widgetOwnerBundleIdentifier,
            widgetSpan: existingItem.widgetSpan,
            hiddenWidgetOwnerBundleIdentifiers: existingItem.hiddenWidgetOwnerBundleIdentifiers
        )
        preferences.pinnedItems = pinnedItems
        refreshPinnedTilesFromPreferences()
        rebuildTiles()
    }

    func appFolderContentViewMode(tileID: String) -> FolderTileContentViewMode {
        guard let item = preferences.pinnedItems.first(where: { Self.pinnedTileID(for: $0) == tileID }),
              item.kind == .appFolder else {
            return .grid
        }

        return item.folderContentViewMode ?? .grid
    }

    func setAppFolderDisplayMode(tileID: String, mode: AppFolderTileDisplayMode) {
        guard let itemIndex = preferences.pinnedItems.firstIndex(where: { Self.pinnedTileID(for: $0) == tileID }),
              preferences.pinnedItems[itemIndex].kind == .appFolder else {
            return
        }

        let existingItem = preferences.pinnedItems[itemIndex]
        guard (existingItem.appFolderDisplayMode ?? .grid) != mode else {
            return
        }

        var pinnedItems = preferences.pinnedItems
        pinnedItems[itemIndex] = PinnedTileItem(
            id: existingItem.id,
            kind: existingItem.kind,
            bundleIdentifier: existingItem.bundleIdentifier,
            folderDisplayName: existingItem.folderDisplayName,
            folderBundleIdentifiers: existingItem.folderBundleIdentifiers,
            appFolderDisplayMode: mode,
            folderContentViewMode: existingItem.folderContentViewMode,
            widgetKind: existingItem.widgetKind,
            widgetOwnerBundleIdentifier: existingItem.widgetOwnerBundleIdentifier,
            widgetSpan: existingItem.widgetSpan,
            hiddenWidgetOwnerBundleIdentifiers: existingItem.hiddenWidgetOwnerBundleIdentifiers
        )
        preferences.pinnedItems = pinnedItems
        refreshPinnedTilesFromPreferences()
        rebuildTiles()
    }

    func appFolderDisplayMode(tileID: String) -> AppFolderTileDisplayMode {
        guard let item = preferences.pinnedItems.first(where: { Self.pinnedTileID(for: $0) == tileID }),
              item.kind == .appFolder else {
            return .grid
        }

        return item.appFolderDisplayMode ?? .grid
    }

    func toggleInlineAppFolderExpansion(folderID: String) {
        if expandedInlineAppFolderIDs.contains(folderID) {
            expandedInlineAppFolderIDs.remove(folderID)
        } else {
            expandedInlineAppFolderIDs.insert(folderID)
        }

        rebuildTiles()
    }

    func isInlineAppFolderExpanded(folderID: String) -> Bool {
        expandedInlineAppFolderIDs.contains(folderID)
    }

    func widgetPlacement(
        kind: WidgetKind,
        ownerBundleIdentifier: String
    ) -> WidgetPlacement? {
        preferences.widgetPlacements.first {
            $0.kind == kind && $0.ownerBundleIdentifier == ownerBundleIdentifier
        }
    }

    func hasWidget(kind: WidgetKind, ownerBundleIdentifier: String) -> Bool {
        widgetPlacement(kind: kind, ownerBundleIdentifier: ownerBundleIdentifier) != nil
    }

    func setWidget(
        kind: WidgetKind,
        ownerBundleIdentifier: String,
        span: TileSpan
    ) {
        guard ProductService.shared.availability(for: kind.productFeature, context: .newPlacement).allowsNewPlacement else {
            return
        }

        var placements = preferences.widgetPlacements.filter {
            !($0.kind == kind && $0.ownerBundleIdentifier == ownerBundleIdentifier)
        }
        placements.append(WidgetPlacement(
            kind: kind,
            ownerBundleIdentifier: ownerBundleIdentifier,
            span: span
        ))
        preferences.widgetPlacements = placements
    }

    func removeWidget(kind: WidgetKind, ownerBundleIdentifier: String) {
        preferences.widgetPlacements.removeAll {
            $0.kind == kind && $0.ownerBundleIdentifier == ownerBundleIdentifier
        }
    }

    func appWidgetCandidates(bundleIdentifier: String) -> [WidgetTile] {
        guard !bundleIdentifier.isEmpty,
              !isAppInFolder(bundleIdentifier: bundleIdentifier) else {
            return []
        }

        var candidates = WidgetCatalog.staticRegistrations
            .filter {
                ProductService.shared.availability(for: $0.kind.productFeature, context: .newPlacement).allowsNewPlacement
            }
            .filter { $0.ownerBundleIdentifier == bundleIdentifier }
            .map { $0.makeTile() }

        let canPlaceNowPlayingWidget = ProductService.shared.availability(
            for: WidgetKind.nowPlaying.productFeature,
            context: .newPlacement
        ).allowsNewPlacement

        if canPlaceNowPlayingWidget,
           mediaPlayback.state(for: bundleIdentifier) != nil || appWidgetDisplay(bundleIdentifier: bundleIdentifier)?.kind == .nowPlaying {
            candidates.append(Self.makeWidgetTile(
                kind: .nowPlaying,
                ownerBundleIdentifier: bundleIdentifier,
                span: defaultAppWidgetSpan(kind: .nowPlaying, ownerBundleIdentifier: bundleIdentifier)
            ))
        }

        return candidates
    }

    func appWidgetDisplay(bundleIdentifier: String) -> AppWidgetDisplay? {
        preferences.appWidgetDisplays.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func setAppWidgetDisplay(bundleIdentifier: String, kind: WidgetKind) {
        guard !bundleIdentifier.isEmpty,
              ProductService.shared.availability(for: kind.productFeature, context: .newPlacement).allowsNewPlacement,
              !isAppInFolder(bundleIdentifier: bundleIdentifier) else {
            return
        }

        let existingSpan = appWidgetDisplay(bundleIdentifier: bundleIdentifier)
            .flatMap { $0.kind == kind ? $0.span : nil }
        let span = existingSpan ?? defaultAppWidgetSpan(kind: kind, ownerBundleIdentifier: bundleIdentifier)

        var displays = preferences.appWidgetDisplays.filter { $0.bundleIdentifier != bundleIdentifier }
        displays.append(AppWidgetDisplay(
            bundleIdentifier: bundleIdentifier,
            kind: kind,
            span: span
        ))
        preferences.appWidgetDisplays = displays.sorted {
            $0.bundleIdentifier.localizedCaseInsensitiveCompare($1.bundleIdentifier) == .orderedAscending
        }
    }

    func removeAppWidgetDisplay(bundleIdentifier: String) {
        preferences.appWidgetDisplays.removeAll { $0.bundleIdentifier == bundleIdentifier }
    }

    func setAppWidgetDisplaySpan(bundleIdentifier: String, span: TileSpan) {
        guard let existingDisplay = appWidgetDisplay(bundleIdentifier: bundleIdentifier),
              !isAppInFolder(bundleIdentifier: bundleIdentifier),
              existingDisplay.span != span else {
            return
        }

        let resolvedSpan = existingDisplay.kind.supportedSpans.contains(span)
            ? span
            : existingDisplay.kind.supportedSpans.last ?? .one
        guard existingDisplay.span != resolvedSpan else {
            return
        }

        var displays = preferences.appWidgetDisplays
        guard let displayIndex = displays.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return
        }

        displays[displayIndex] = AppWidgetDisplay(
            bundleIdentifier: existingDisplay.bundleIdentifier,
            kind: existingDisplay.kind,
            span: resolvedSpan
        )
        preferences.appWidgetDisplays = displays
    }

    func insertPinnedItem(kind: PinnedTileItemKind, at destinationIndex: Int) {
        let item: PinnedTileItem
        switch kind {
        case .app, .appFolder, .widget:
            return
        case .launchpad:
            guard ProductService.shared.availability(for: .launchpad, context: .newPlacement).allowsNewPlacement else {
                return
            }
            item = .launchpad()
        case .smartStack:
            guard ProductService.shared.availability(for: .smartStack, context: .newPlacement).allowsNewPlacement else {
                return
            }
            item = .smartStack()
        case .spacer:
            item = .spacer()
        case .flexibleSpacer:
            item = .flexibleSpacer()
        case .divider:
            item = .divider()
        }

        insertPinnedItem(item, at: destinationIndex)
    }

    func insertPinnedItem(_ item: PinnedTileItem, at destinationIndex: Int) {

        var pinnedItems = preferences.pinnedItems
        let clampedDestinationIndex = min(max(destinationIndex, 0), pinnedItems.count)
        pinnedItems.insert(item, at: clampedDestinationIndex)
        preferences.pinnedItems = pinnedItems
        refreshPinnedTilesFromPreferences()
        rebuildTiles()
    }

    func smartOrganizePinnedItems() {
        // Smart-organize is FoundationModels-backed (macOS 26+). On
        // older systems, or when the feature is force-disabled via
        // `FeatureGate` for testing, the action is a no-op; callers
        // should hide or disable the entry point via the same gate.
        guard FeatureGate.shared.isAvailable(.foundationModelsSmartOrganize),
              #available(macOS 26.0, *) else { return }
        let existingItems = preferences.pinnedItems
        Task { @MainActor [weak self] in
            guard let self else { return }
            let organizedItems = await PinnedDockSmartOrganizerService.shared.organize(items: existingItems)
            guard organizedItems != self.preferences.pinnedItems else {
                return
            }

            self.preferences.pinnedItems = organizedItems
            self.refreshPinnedTilesFromPreferences()
            self.rebuildTiles()
        }
    }

    func setTrailingTileOrder(ids: [String]) {
        guard ids.count == trailingTiles.count else {
            return
        }

        let itemsByID = Dictionary(uniqueKeysWithValues: preferences.trailingItems.map { (Self.trailingTileID(for: $0), $0) })
        let reorderedItems = ids.compactMap { itemsByID[$0] }
        guard reorderedItems.count == preferences.trailingItems.count else {
            return
        }

        preferences.trailingItems = reorderedItems
        refreshTrailingTilesFromPreferences()
        rebuildTiles()
    }

    func insertTrailingItem(_ item: TrailingTileItem, at destinationIndex: Int) {
        if item.kind == .folder,
           ProductService.shared.currentTier == .free,
           preferences.trailingItems.filter({ $0.kind == .folder }).count >= ProductService.maximumFreeFolderCount {
            NSLog("[Docky] Blocked folder insertion in free tier at folder limit=\(ProductService.maximumFreeFolderCount)")
            return
        }

        var trailingItems = preferences.trailingItems
        logTrailingItems("Before insertTrailingItem")
        let clampedDestinationIndex = min(max(destinationIndex, 0), trailingItems.count)
        trailingItems.insert(item, at: clampedDestinationIndex)
        preferences.trailingItems = trailingItems
        logTrailingItems("After insertTrailingItem")
        refreshTrailingTilesFromPreferences()
        rebuildTiles()
    }

    func makePinnedItem(from tile: Tile) -> PinnedTileItem? {
        switch itemScope(forTileID: tile.id) {
        case .pinned(let item):
            return item
        case .trailing(let item):
            switch item.kind {
            case .widget:
                guard let widgetKind = item.widgetKind,
                      let ownerBundleIdentifier = item.widgetOwnerBundleIdentifier else {
                    return nil
                }
                return PinnedTileItem(
                    id: item.id,
                    kind: .widget,
                    bundleIdentifier: nil,
                    folderDisplayName: nil,
                    folderBundleIdentifiers: [],
                    appFolderDisplayMode: nil,
                    folderContentViewMode: nil,
                    widgetKind: widgetKind,
                    widgetOwnerBundleIdentifier: ownerBundleIdentifier,
                    widgetSpan: item.widgetSpan,
                    hiddenWidgetOwnerBundleIdentifiers: []
                )
            case .smartStack:
                return PinnedTileItem(
                    id: item.id,
                    kind: .smartStack,
                    bundleIdentifier: nil,
                    folderDisplayName: nil,
                    folderBundleIdentifiers: [],
                    appFolderDisplayMode: nil,
                    folderContentViewMode: nil,
                    widgetKind: nil,
                    widgetOwnerBundleIdentifier: nil,
                    widgetSpan: nil,
                    hiddenWidgetOwnerBundleIdentifiers: item.hiddenWidgetOwnerBundleIdentifiers
                )
            case .spacer:
                return PinnedTileItem(
                    id: item.id,
                    kind: .spacer,
                    bundleIdentifier: nil,
                    folderDisplayName: nil,
                    folderBundleIdentifiers: [],
                    appFolderDisplayMode: nil,
                    folderContentViewMode: nil,
                    widgetKind: nil,
                    widgetOwnerBundleIdentifier: nil,
                    widgetSpan: nil,
                    hiddenWidgetOwnerBundleIdentifiers: []
                )
            case .flexibleSpacer:
                return PinnedTileItem(
                    id: item.id,
                    kind: .flexibleSpacer,
                    bundleIdentifier: nil,
                    folderDisplayName: nil,
                    folderBundleIdentifiers: [],
                    appFolderDisplayMode: nil,
                    folderContentViewMode: nil,
                    widgetKind: nil,
                    widgetOwnerBundleIdentifier: nil,
                    widgetSpan: nil,
                    hiddenWidgetOwnerBundleIdentifiers: []
                )
            case .divider:
                return PinnedTileItem(
                    id: item.id,
                    kind: .divider,
                    bundleIdentifier: nil,
                    folderDisplayName: nil,
                    folderBundleIdentifiers: [],
                    appFolderDisplayMode: nil,
                    folderContentViewMode: nil,
                    widgetKind: nil,
                    widgetOwnerBundleIdentifier: nil,
                    widgetSpan: nil,
                    hiddenWidgetOwnerBundleIdentifiers: []
                )
            case .folder, .trash:
                return nil
            }
        case .none:
            return nil
        }
    }

    func makeTrailingItem(from tile: Tile) -> TrailingTileItem? {
        switch itemScope(forTileID: tile.id) {
        case .trailing(let item):
            return item
        case .pinned(let item):
            switch item.kind {
            case .launchpad:
                return nil
            case .widget:
                guard let widgetKind = item.widgetKind,
                      let ownerBundleIdentifier = item.widgetOwnerBundleIdentifier else {
                    return nil
                }
                return TrailingTileItem(
                    id: item.id,
                    kind: .widget,
                    sourceTileID: nil,
                    folderURL: nil,
                    folderDisplayName: nil,
                    folderDisplayMode: nil,
                    folderContentViewMode: nil,
                    widgetKind: widgetKind,
                    widgetOwnerBundleIdentifier: ownerBundleIdentifier,
                    widgetSpan: item.widgetSpan,
                    hiddenWidgetOwnerBundleIdentifiers: []
                )
            case .smartStack:
                return TrailingTileItem(
                    id: item.id,
                    kind: .smartStack,
                    sourceTileID: nil,
                    folderURL: nil,
                    folderDisplayName: nil,
                    folderDisplayMode: nil,
                    folderContentViewMode: nil,
                    widgetKind: nil,
                    widgetOwnerBundleIdentifier: nil,
                    widgetSpan: nil,
                    hiddenWidgetOwnerBundleIdentifiers: item.hiddenWidgetOwnerBundleIdentifiers
                )
            case .spacer:
                return TrailingTileItem(
                    id: item.id,
                    kind: .spacer,
                    sourceTileID: nil,
                    folderURL: nil,
                    folderDisplayName: nil,
                    folderDisplayMode: nil,
                    folderContentViewMode: nil,
                    widgetKind: nil,
                    widgetOwnerBundleIdentifier: nil,
                    widgetSpan: nil,
                    hiddenWidgetOwnerBundleIdentifiers: []
                )
            case .flexibleSpacer:
                return TrailingTileItem(
                    id: item.id,
                    kind: .flexibleSpacer,
                    sourceTileID: nil,
                    folderURL: nil,
                    folderDisplayName: nil,
                    folderDisplayMode: nil,
                    folderContentViewMode: nil,
                    widgetKind: nil,
                    widgetOwnerBundleIdentifier: nil,
                    widgetSpan: nil,
                    hiddenWidgetOwnerBundleIdentifiers: []
                )
            case .divider:
                return TrailingTileItem(
                    id: item.id,
                    kind: .divider,
                    sourceTileID: nil,
                    folderURL: nil,
                    folderDisplayName: nil,
                    folderDisplayMode: nil,
                    folderContentViewMode: nil,
                    widgetKind: nil,
                    widgetOwnerBundleIdentifier: nil,
                    widgetSpan: nil,
                    hiddenWidgetOwnerBundleIdentifiers: []
                )
            case .app, .appFolder:
                return nil
            }
        case .none:
            return nil
        }
    }

    func smartStackWidgetCandidates(tileID: String) -> [WidgetTile] {
        switch itemScope(forTileID: tileID) {
        case .pinned(let item):
            guard item.kind == .smartStack else {
                return []
            }
            let hiddenOwnerBundleIdentifierSet = Set(item.hiddenWidgetOwnerBundleIdentifiers)
            let visibleWidgets = allSmartStackWidgets().filter {
                !hiddenOwnerBundleIdentifierSet.contains($0.ownerBundleIdentifier)
            }
            let hiddenWidgets = allSmartStackWidgets().filter {
                hiddenOwnerBundleIdentifierSet.contains($0.ownerBundleIdentifier)
            }
            return visibleWidgets + hiddenWidgets
        case .trailing(let item):
            guard item.kind == .smartStack else {
                return []
            }
            let hiddenOwnerBundleIdentifierSet = Set(item.hiddenWidgetOwnerBundleIdentifiers)
            let visibleWidgets = allSmartStackWidgets().filter {
                !hiddenOwnerBundleIdentifierSet.contains($0.ownerBundleIdentifier)
            }
            let hiddenWidgets = allSmartStackWidgets().filter {
                hiddenOwnerBundleIdentifierSet.contains($0.ownerBundleIdentifier)
            }
            return visibleWidgets + hiddenWidgets
        case .none:
            return []
        }
    }

    func isSmartStackWidgetVisible(tileID: String, ownerBundleIdentifier: String) -> Bool {
        switch itemScope(forTileID: tileID) {
        case .pinned(let item):
            guard item.kind == .smartStack else {
                return false
            }
            return !item.hiddenWidgetOwnerBundleIdentifiers.contains(ownerBundleIdentifier)
        case .trailing(let item):
            guard item.kind == .smartStack else {
                return false
            }
            return !item.hiddenWidgetOwnerBundleIdentifiers.contains(ownerBundleIdentifier)
        case .none:
            return false
        }
    }

    func setSmartStackWidgetVisibility(tileID: String, ownerBundleIdentifier: String, isVisible: Bool) {
        if let itemIndex = preferences.pinnedItems.firstIndex(where: { Self.pinnedTileID(for: $0) == tileID }),
           preferences.pinnedItems[itemIndex].kind == .smartStack {
            var pinnedItems = preferences.pinnedItems
            let existingItem = pinnedItems[itemIndex]
            var hiddenOwnerBundleIdentifiers = Set(existingItem.hiddenWidgetOwnerBundleIdentifiers)
            if isVisible {
                hiddenOwnerBundleIdentifiers.remove(ownerBundleIdentifier)
            } else {
                hiddenOwnerBundleIdentifiers.insert(ownerBundleIdentifier)
            }

            pinnedItems[itemIndex] = PinnedTileItem(
                id: existingItem.id,
                kind: existingItem.kind,
                bundleIdentifier: existingItem.bundleIdentifier,
                folderDisplayName: existingItem.folderDisplayName,
                folderBundleIdentifiers: existingItem.folderBundleIdentifiers,
                appFolderDisplayMode: existingItem.appFolderDisplayMode,
                folderContentViewMode: existingItem.folderContentViewMode,
                widgetKind: existingItem.widgetKind,
                widgetOwnerBundleIdentifier: existingItem.widgetOwnerBundleIdentifier,
                widgetSpan: existingItem.widgetSpan,
                hiddenWidgetOwnerBundleIdentifiers: hiddenOwnerBundleIdentifiers.sorted()
            )
            preferences.pinnedItems = pinnedItems
            refreshPinnedTilesFromPreferences()
            rebuildTiles()
            return
        }

        guard let itemIndex = preferences.trailingItems.firstIndex(where: { Self.trailingTileID(for: $0) == tileID }),
              preferences.trailingItems[itemIndex].kind == .smartStack else {
            return
        }

        var trailingItems = preferences.trailingItems
        let existingItem = trailingItems[itemIndex]
        var hiddenOwnerBundleIdentifiers = Set(existingItem.hiddenWidgetOwnerBundleIdentifiers)
        if isVisible {
            hiddenOwnerBundleIdentifiers.remove(ownerBundleIdentifier)
        } else {
            hiddenOwnerBundleIdentifiers.insert(ownerBundleIdentifier)
        }

        trailingItems[itemIndex] = TrailingTileItem(
            id: existingItem.id,
            kind: existingItem.kind,
            sourceTileID: existingItem.sourceTileID,
            folderURL: existingItem.folderURL,
            folderDisplayName: existingItem.folderDisplayName,
            folderDisplayMode: existingItem.folderDisplayMode,
            folderContentViewMode: existingItem.folderContentViewMode,
            widgetKind: existingItem.widgetKind,
            widgetOwnerBundleIdentifier: existingItem.widgetOwnerBundleIdentifier,
            widgetSpan: existingItem.widgetSpan,
            hiddenWidgetOwnerBundleIdentifiers: hiddenOwnerBundleIdentifiers.sorted()
        )
        preferences.trailingItems = trailingItems
        refreshTrailingTilesFromPreferences()
        rebuildTiles()
    }

    func setPinnedWidgetSpan(tileID: String, span: TileSpan) {
        guard let itemIndex = preferences.pinnedItems.firstIndex(where: { Self.pinnedTileID(for: $0) == tileID }),
              preferences.pinnedItems[itemIndex].kind == .widget else {
            return
        }

        let existingItem = preferences.pinnedItems[itemIndex]
        guard existingItem.widgetSpan != span else {
            return
        }

        var pinnedItems = preferences.pinnedItems
        pinnedItems[itemIndex] = PinnedTileItem(
            id: existingItem.id,
            kind: existingItem.kind,
            bundleIdentifier: existingItem.bundleIdentifier,
            folderDisplayName: existingItem.folderDisplayName,
            folderBundleIdentifiers: existingItem.folderBundleIdentifiers,
            appFolderDisplayMode: existingItem.appFolderDisplayMode,
            folderContentViewMode: existingItem.folderContentViewMode,
            widgetKind: existingItem.widgetKind,
            widgetOwnerBundleIdentifier: existingItem.widgetOwnerBundleIdentifier,
            widgetSpan: span,
            hiddenWidgetOwnerBundleIdentifiers: existingItem.hiddenWidgetOwnerBundleIdentifiers
        )
        preferences.pinnedItems = pinnedItems
        refreshPinnedTilesFromPreferences()
        rebuildTiles()
    }

    func setTrailingWidgetSpan(tileID: String, span: TileSpan) {
        guard let itemIndex = preferences.trailingItems.firstIndex(where: { Self.trailingTileID(for: $0) == tileID }),
              preferences.trailingItems[itemIndex].kind == .widget else {
            return
        }

        let existingItem = preferences.trailingItems[itemIndex]
        guard existingItem.widgetSpan != span else {
            return
        }

        var trailingItems = preferences.trailingItems
        trailingItems[itemIndex] = TrailingTileItem(
            id: existingItem.id,
            kind: existingItem.kind,
            sourceTileID: existingItem.sourceTileID,
            folderURL: existingItem.folderURL,
            folderDisplayName: existingItem.folderDisplayName,
            folderDisplayMode: existingItem.folderDisplayMode,
            folderContentViewMode: existingItem.folderContentViewMode,
            widgetKind: existingItem.widgetKind,
            widgetOwnerBundleIdentifier: existingItem.widgetOwnerBundleIdentifier,
            widgetSpan: span,
            hiddenWidgetOwnerBundleIdentifiers: existingItem.hiddenWidgetOwnerBundleIdentifiers
        )
        preferences.trailingItems = trailingItems
        refreshTrailingTilesFromPreferences()
        rebuildTiles()
    }

    func setFolderDisplayMode(tileID: String, folderURL: URL, mode: FolderTileDisplayMode) {
        let normalizedFolderURL = folderURL.standardizedFileURL

        if let itemIndex = preferences.trailingItems.firstIndex(where: {
            matchesFolderItem($0, tileID: tileID, normalizedFolderURL: normalizedFolderURL)
        }) {
            updateFolderDisplayMode(at: itemIndex, mode: mode)
            return
        }

        if let systemFolder = systemFolderEntry(normalizedFolderURL: normalizedFolderURL) {
            var trailingItems = preferences.trailingItems
            trailingItems.insert(
                .folder(
                    sourceTileID: systemFolder.tileID,
                    displayMode: mode,
                    contentViewMode: systemFolder.folder.contentViewMode
                ),
                at: trailingItems.firstIndex(where: { $0.kind == .trash }) ?? trailingItems.count
            )
            preferences.trailingItems = trailingItems
            refreshTrailingTilesFromPreferences()
            rebuildTiles()
        }
    }

    func folderDisplayMode(tileID: String, folderURL: URL) -> FolderTileDisplayMode {
        let normalizedFolderURL = folderURL.standardizedFileURL
        if let item = preferences.trailingItems.first(where: {
            matchesFolderItem($0, tileID: tileID, normalizedFolderURL: normalizedFolderURL)
        }) {
            return resolvedFolderDisplayMode(for: item)
        }

        return systemFolderEntry(normalizedFolderURL: normalizedFolderURL)?.folder.displayMode ?? .contents
    }

    func setFolderContentViewMode(tileID: String, folderURL: URL, mode: FolderTileContentViewMode) {
        let normalizedFolderURL = folderURL.standardizedFileURL

        if let itemIndex = preferences.trailingItems.firstIndex(where: {
            matchesFolderItem($0, tileID: tileID, normalizedFolderURL: normalizedFolderURL)
        }) {
            updateFolderContentViewMode(at: itemIndex, mode: mode)
            return
        }

        if let systemFolder = systemFolderEntry(normalizedFolderURL: normalizedFolderURL) {
            var trailingItems = preferences.trailingItems
            trailingItems.insert(
                .folder(
                    sourceTileID: systemFolder.tileID,
                    displayMode: systemFolder.folder.displayMode,
                    contentViewMode: mode
                ),
                at: trailingItems.firstIndex(where: { $0.kind == .trash }) ?? trailingItems.count
            )
            preferences.trailingItems = trailingItems
            refreshTrailingTilesFromPreferences()
            rebuildTiles()
        }
    }

    func folderContentViewMode(tileID: String, folderURL: URL) -> FolderTileContentViewMode {
        let normalizedFolderURL = folderURL.standardizedFileURL
        if let item = preferences.trailingItems.first(where: {
            matchesFolderItem($0, tileID: tileID, normalizedFolderURL: normalizedFolderURL)
        }) {
            return resolvedFolderContentViewMode(for: item)
        }

        return systemFolderEntry(normalizedFolderURL: normalizedFolderURL)?.folder.contentViewMode ?? .grid
    }

    func setFolderSortMode(tileID: String, folderURL: URL, mode: FolderTileSortMode) {
        let normalizedFolderURL = folderURL.standardizedFileURL

        if let itemIndex = preferences.trailingItems.firstIndex(where: {
            matchesFolderItem($0, tileID: tileID, normalizedFolderURL: normalizedFolderURL)
        }) {
            updateFolderSortMode(at: itemIndex, mode: mode)
            return
        }

        if let systemFolder = systemFolderEntry(normalizedFolderURL: normalizedFolderURL) {
            var trailingItems = preferences.trailingItems
            trailingItems.insert(
                .folder(
                    sourceTileID: systemFolder.tileID,
                    displayMode: systemFolder.folder.displayMode,
                    contentViewMode: systemFolder.folder.contentViewMode,
                    sortMode: mode
                ),
                at: trailingItems.firstIndex(where: { $0.kind == .trash }) ?? trailingItems.count
            )
            preferences.trailingItems = trailingItems
            refreshTrailingTilesFromPreferences()
            rebuildTiles()
        }
    }

    func folderSortMode(tileID: String, folderURL: URL) -> FolderTileSortMode {
        let normalizedFolderURL = folderURL.standardizedFileURL
        if let item = preferences.trailingItems.first(where: {
            matchesFolderItem($0, tileID: tileID, normalizedFolderURL: normalizedFolderURL)
        }) {
            return resolvedFolderSortMode(for: item)
        }

        return systemFolderEntry(normalizedFolderURL: normalizedFolderURL)?.folder.sortMode ?? .dateAdded
    }

    private func updateFolderDisplayMode(at itemIndex: Int, mode: FolderTileDisplayMode) {
        let existingItem = preferences.trailingItems[itemIndex]
        guard resolvedFolderDisplayMode(for: existingItem) != mode else {
            return
        }

        var trailingItems = preferences.trailingItems
        trailingItems[itemIndex] = TrailingTileItem(
            id: existingItem.id,
            kind: existingItem.kind,
            sourceTileID: existingItem.sourceTileID,
            folderURL: existingItem.folderURL,
            folderDisplayName: existingItem.folderDisplayName,
            folderDisplayMode: mode,
            folderContentViewMode: existingItem.folderContentViewMode,
            folderSortMode: existingItem.folderSortMode,
            widgetKind: existingItem.widgetKind,
            widgetOwnerBundleIdentifier: existingItem.widgetOwnerBundleIdentifier,
            widgetSpan: existingItem.widgetSpan,
            hiddenWidgetOwnerBundleIdentifiers: existingItem.hiddenWidgetOwnerBundleIdentifiers
        )
        preferences.trailingItems = trailingItems
        refreshTrailingTilesFromPreferences()
        rebuildTiles()
    }

    private func updateFolderContentViewMode(at itemIndex: Int, mode: FolderTileContentViewMode) {
        let existingItem = preferences.trailingItems[itemIndex]
        guard resolvedFolderContentViewMode(for: existingItem) != mode else {
            return
        }

        var trailingItems = preferences.trailingItems
        trailingItems[itemIndex] = TrailingTileItem(
            id: existingItem.id,
            kind: existingItem.kind,
            sourceTileID: existingItem.sourceTileID,
            folderURL: existingItem.folderURL,
            folderDisplayName: existingItem.folderDisplayName,
            folderDisplayMode: existingItem.folderDisplayMode,
            folderContentViewMode: mode,
            folderSortMode: existingItem.folderSortMode,
            widgetKind: existingItem.widgetKind,
            widgetOwnerBundleIdentifier: existingItem.widgetOwnerBundleIdentifier,
            widgetSpan: existingItem.widgetSpan,
            hiddenWidgetOwnerBundleIdentifiers: existingItem.hiddenWidgetOwnerBundleIdentifiers
        )
        preferences.trailingItems = trailingItems
        refreshTrailingTilesFromPreferences()
        rebuildTiles()
    }

    private func updateFolderSortMode(at itemIndex: Int, mode: FolderTileSortMode) {
        let existingItem = preferences.trailingItems[itemIndex]
        guard resolvedFolderSortMode(for: existingItem) != mode else {
            return
        }

        var trailingItems = preferences.trailingItems
        trailingItems[itemIndex] = TrailingTileItem(
            id: existingItem.id,
            kind: existingItem.kind,
            sourceTileID: existingItem.sourceTileID,
            folderURL: existingItem.folderURL,
            folderDisplayName: existingItem.folderDisplayName,
            folderDisplayMode: existingItem.folderDisplayMode,
            folderContentViewMode: existingItem.folderContentViewMode,
            folderSortMode: mode,
            widgetKind: existingItem.widgetKind,
            widgetOwnerBundleIdentifier: existingItem.widgetOwnerBundleIdentifier,
            widgetSpan: existingItem.widgetSpan,
            hiddenWidgetOwnerBundleIdentifiers: existingItem.hiddenWidgetOwnerBundleIdentifiers
        )
        preferences.trailingItems = trailingItems
        refreshTrailingTilesFromPreferences()
        rebuildTiles()
    }

    private func resolvedFolderDisplayMode(for item: TrailingTileItem) -> FolderTileDisplayMode {
        if let mode = item.folderDisplayMode {
            return mode
        }

        return systemFolder(for: item)?.displayMode ?? .contents
    }

    private func resolvedFolderContentViewMode(for item: TrailingTileItem) -> FolderTileContentViewMode {
        if let mode = item.folderContentViewMode {
            return mode
        }

        return systemFolder(for: item)?.contentViewMode ?? .grid
    }

    private func resolvedFolderSortMode(for item: TrailingTileItem) -> FolderTileSortMode {
        if let mode = item.folderSortMode {
            return mode
        }

        return systemFolder(for: item)?.sortMode ?? .dateAdded
    }

    private func systemFolder(for item: TrailingTileItem) -> FolderTile? {
        guard let sourceTileID = item.sourceTileID,
              let tile = systemOtherTilesByID[sourceTileID],
              case .folder(let folder) = tile.content else {
            return nil
        }

        return folder
    }

    private func systemFolderEntry(normalizedFolderURL: URL) -> (tileID: String, folder: FolderTile)? {
        for tile in systemOtherTiles {
            guard case .folder(let folder) = tile.content,
                  folder.url.standardizedFileURL == normalizedFolderURL else {
                continue
            }

            return (tile.id, folder)
        }

        return nil
    }

    private func matchesFolderItem(_ item: TrailingTileItem, tileID: String, normalizedFolderURL: URL) -> Bool {
        guard item.kind == .folder else {
            return false
        }
        if Self.trailingTileID(for: item) == tileID {
            return true
        }
        if let itemFolderURL = item.folderURL?.standardizedFileURL {
            return itemFolderURL == normalizedFolderURL
        }
        guard let sourceTileID = item.sourceTileID,
              let tile = systemOtherTilesByID[sourceTileID],
              case .folder(let folder) = tile.content else {
            return false
        }
        return folder.url.standardizedFileURL == normalizedFolderURL
    }

    func removePinnedItem(tileID: String) {
        var pinnedItems = preferences.pinnedItems
        let originalCount = pinnedItems.count
        pinnedItems.removeAll { Self.pinnedTileID(for: $0) == tileID }
        guard pinnedItems.count != originalCount else {
            return
        }
        preferences.pinnedItems = pinnedItems
        refreshPinnedTilesFromPreferences()
        rebuildTiles()
    }

    func removeTrailingItem(tileID: String) {
        var trailingItems = preferences.trailingItems
        logTrailingItems("Before removeTrailingItem")
        let originalCount = trailingItems.count
        trailingItems.removeAll { Self.trailingTileID(for: $0) == tileID }
        guard trailingItems.count != originalCount else {
            return
        }
        preferences.trailingItems = trailingItems
        logTrailingItems("After removeTrailingItem")
        refreshTrailingTilesFromPreferences()
        rebuildTiles()
    }

    private static let finderBundleID = "com.apple.finder"
    private static let appSearchDirectories = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    ]
    private static let defaultDockLoadTestBundleIdentifiers = [
        "com.apple.launchpad.launcher",
        "com.apple.Safari",
        "com.apple.MobileSMS",
        "com.apple.mail",
        "com.apple.iCal",
        "com.apple.AddressBook",
        "com.apple.reminders",
        "com.apple.Notes",
        "com.apple.freeform",
        "com.apple.FaceTime",
        "com.apple.Photos",
        "com.apple.Maps",
        "com.apple.TV",
        "com.apple.Music",
        "com.apple.podcasts",
        "com.apple.AppStore",
        "com.apple.systempreferences"
    ]

    @MainActor
    private static func installedApplications() -> [(bundleIdentifier: String, displayName: String)] {
        // Spotlight scan, sandbox-safe; no read access required to
        // `/Applications`, `/System/Applications`, or `~/Applications`.
        let selfBundleID = Bundle.main.bundleIdentifier
        return ApplicationBundleScanner.shared.installedApps
            .filter { $0.bundleIdentifier != finderBundleID && $0.bundleIdentifier != selfBundleID }
            .map { (bundleIdentifier: $0.bundleIdentifier, displayName: $0.displayName) }
        .sorted { lhs, rhs in
            let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if comparison == .orderedSame {
                return lhs.bundleIdentifier.localizedCaseInsensitiveCompare(rhs.bundleIdentifier) == .orderedAscending
            }
            return comparison == .orderedAscending
        }
    }

    private static func installedApplicationBundleIdentifiers() -> [String] {
        installedApplications().map(\.bundleIdentifier)
    }

    private static func resolveInstalledAppBundleIdentifier(named name: String) -> String? {
        let normalizedName = normalizedApplicationName(name)
        let applications = installedApplications()

        if let exactMatch = applications.first(where: {
            normalizedApplicationName($0.displayName) == normalizedName
        }) {
            return exactMatch.bundleIdentifier
        }

        let partialMatches = applications.filter {
            normalizedApplicationName($0.displayName).contains(normalizedName)
        }
        guard partialMatches.count == 1 else {
            return nil
        }
        return partialMatches[0].bundleIdentifier
    }

    private static func normalizedApplicationName(_ name: String) -> String {
        name
            .replacingOccurrences(of: ".app", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func bundleIdentifier(of tile: Tile) -> String? {
        if case .app(let app) = tile.content {
            return app.bundleIdentifier
        }
        return nil
    }

    private func seedPinnedPreferencesIfNeeded(from refreshed: [Tile]) {
        guard preferences.pinnedItems.isEmpty else {
            return
        }

        let pinnedItems = refreshed.compactMap(Self.pinnedItem(from:))
        guard !pinnedItems.isEmpty else {
            return
        }

        preferences.pinnedItems = pinnedItems
    }

    private func refreshPinnedTilesFromPreferences() {
        pinnedTiles = preferences.pinnedItems.compactMap(tile(for:))
    }

    private func mergePinnedPreferencesAdditionsIfNeeded(from refreshed: [Tile]) {
        guard !preferences.pinnedItems.isEmpty else {
            return
        }

        let importedItems = refreshed
            .compactMap(Self.pinnedItem(from:))
            .filter { item in
                item.kind != .app || item.bundleIdentifier != Self.finderBundleID
            }
        guard !importedItems.isEmpty else {
            return
        }

        let existingItems = preferences.pinnedItems
        let additions = importedItems.filter { importedItem in
            !existingItems.contains { existingItem in
                Self.matchesImportedPinnedItem(existingItem, importedItem)
            }
        }
        guard !additions.isEmpty else {
            return
        }

        preferences.pinnedItems = existingItems + additions
    }

    private func synchronizeAppWidgetDisplaysWithFolders() {
        let folderBundleIdentifiers = Set(preferences.pinnedItems.flatMap { item in
            item.kind == .appFolder ? item.folderBundleIdentifiers : []
        })
        guard !folderBundleIdentifiers.isEmpty else {
            return
        }

        let filteredDisplays = preferences.appWidgetDisplays.filter {
            !folderBundleIdentifiers.contains($0.bundleIdentifier)
        }
        guard filteredDisplays != preferences.appWidgetDisplays else {
            return
        }

        preferences.appWidgetDisplays = filteredDisplays
    }

    private func refreshTrailingPreferencesIfNeeded() {
        let systemItems = systemOtherTiles.compactMap(Self.trailingItem(from:)) + [.trash()]
        guard !systemItems.isEmpty else {
            preferences.trailingItems = []
            logTrailingItems("After refreshTrailingPreferencesIfNeeded cleared")
            return
        }

        guard !preferences.trailingItems.isEmpty else {
            preferences.trailingItems = systemItems
            logTrailingItems("After refreshTrailingPreferencesIfNeeded seeded")
            return
        }

        let availableFolderIDs = Set(systemOtherTiles.map(\.id))
        var mergedItems: [TrailingTileItem] = preferences.trailingItems.filter { item in
            switch item.kind {
            case .folder:
                if let sourceTileID = item.sourceTileID {
                    return availableFolderIDs.contains(sourceTileID)
                }
                return item.folderURL != nil
            case .trash, .widget, .smartStack, .spacer, .flexibleSpacer, .divider:
                return true
            }
        }

        if !mergedItems.contains(where: { $0.kind == .trash }) {
            mergedItems.append(.trash())
        }

        let existingSystemSourceIDs = Set(mergedItems.compactMap(\.sourceTileID))
        let additions = systemItems.filter { item in
            guard let sourceTileID = item.sourceTileID else {
                return item.kind == .trash && !mergedItems.contains(where: { $0.kind == .trash })
            }

            return !existingSystemSourceIDs.contains(sourceTileID)
        }
        if !additions.isEmpty {
            mergedItems.append(contentsOf: additions)
        }

        guard mergedItems != preferences.trailingItems else {
            return
        }

        preferences.trailingItems = mergedItems
        logTrailingItems("After refreshTrailingPreferencesIfNeeded merged")
    }

    private func logTrailingItems(_ message: String) {
        let summary = preferences.trailingItems.map(Self.trailingItemDebugDescription(_:))
        NSLog("[Docky] \(message): \(summary)")
    }

    private static func trailingItemDebugDescription(_ item: TrailingTileItem) -> String {
        switch item.kind {
        case .folder:
            if let sourceTileID = item.sourceTileID {
                return "folder(system:\(sourceTileID))"
            }
            if let folderURL = item.folderURL {
                return "folder(custom:\(folderURL.path))"
            }
            return "folder(unknown)"
        case .trash:
            return "trash"
        case .widget:
            return "widget(\(item.widgetOwnerBundleIdentifier ?? "unknown"))"
        case .smartStack:
            return "smartStack"
        case .spacer:
            return "spacer"
        case .flexibleSpacer:
            return "flexibleSpacer"
        case .divider:
            return "divider"
        }
    }

    private func refreshTrailingTilesFromPreferences() {
        var visibleItems = preferences.trailingItems
        if !visibleItems.contains(where: { $0.kind == .trash }) {
            visibleItems.append(.trash())
        }

        trailingTiles = visibleItems.compactMap(trailingTile(for:))
    }

    private func suggestAppFolderNameIfNeeded(folderID: String, expectedDisplayName: String, apps: [AppTile]) {
        guard apps.count >= 2 else {
            return
        }

        // The LLM-powered suggester is macOS 26+, or force-disabled
        // via `FeatureGate` for testing. On earlier systems the
        // deterministic seed name set at folder-creation time is what
        // the user keeps until they rename manually.
        guard FeatureGate.shared.isAvailable(.foundationModelsFolderNaming),
              #available(macOS 26.0, *) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let suggestedName = await AppFolderNamingService.shared.suggestInitialName(for: apps) else {
                return
            }

            guard let itemIndex = self.preferences.pinnedItems.firstIndex(where: { $0.id == folderID }) else {
                return
            }

            let existingItem = self.preferences.pinnedItems[itemIndex]
            guard existingItem.kind == .appFolder,
                  (existingItem.folderDisplayName ?? "Folder") == expectedDisplayName else {
                return
            }

            self.renameAppFolder(
                tileID: Self.pinnedTileID(for: existingItem),
                displayName: suggestedName
            )
        }
    }

    private func pinnedItem(forTileID tileID: String) -> PinnedTileItem? {
        preferences.pinnedItems.first { Self.pinnedTileID(for: $0) == tileID }
    }

    private func normalizedGroupedAppBundleIdentifiers(_ bundleIdentifiers: [String]) -> [String] {
        var seen: Set<String> = []

        return bundleIdentifiers.filter { bundleIdentifier in
            guard !bundleIdentifier.isEmpty,
                  bundleIdentifier != Self.finderBundleID else {
                return false
            }

            return seen.insert(bundleIdentifier).inserted
        }
    }

    private func groupedAppInsertionIndex(before targetIndex: Int, removing bundleIdentifiers: [String]) -> Int {
        let removedBundleIdentifiers = Set(bundleIdentifiers)

        return preferences.pinnedItems.prefix(targetIndex).reduce(into: 0) { count, item in
            switch item.kind {
            case .app:
                if let bundleIdentifier = item.bundleIdentifier,
                   removedBundleIdentifiers.contains(bundleIdentifier) {
                    return
                }
                count += 1
            case .appFolder:
                let remainingBundleIdentifiers = item.folderBundleIdentifiers.filter {
                    !removedBundleIdentifiers.contains($0)
                }
                if remainingBundleIdentifiers.isEmpty {
                    return
                }
                count += 1
            case .launchpad, .widget, .smartStack, .spacer, .flexibleSpacer, .divider:
                count += 1
            }
        }
    }

    private func removingGroupedApps(
        _ bundleIdentifiers: [String],
        replacingTargetTileID targetTileID: String? = nil
    ) -> [PinnedTileItem] {
        let removedBundleIdentifiers = Set(bundleIdentifiers)

        return preferences.pinnedItems.compactMap { item in
            if let targetTileID, Self.pinnedTileID(for: item) == targetTileID {
                return nil
            }

            switch item.kind {
            case .app:
                guard let bundleIdentifier = item.bundleIdentifier else {
                    return item
                }
                return removedBundleIdentifiers.contains(bundleIdentifier) ? nil : item
            case .appFolder:
                let remainingBundleIdentifiers = item.folderBundleIdentifiers.filter {
                    !removedBundleIdentifiers.contains($0)
                }
                guard remainingBundleIdentifiers.count != item.folderBundleIdentifiers.count else {
                    return item
                }

                expandedInlineAppFolderIDs.remove(item.id)
                switch remainingBundleIdentifiers.count {
                case 0:
                    return nil
                case 1:
                    return .app(bundleIdentifier: remainingBundleIdentifiers[0])
                default:
                    return .appFolder(
                        id: item.id,
                        displayName: item.folderDisplayName ?? "Folder",
                        bundleIdentifiers: remainingBundleIdentifiers,
                        displayMode: item.appFolderDisplayMode ?? .grid,
                        contentViewMode: item.folderContentViewMode ?? .grid
                    )
                }
            case .launchpad, .widget, .smartStack, .spacer, .flexibleSpacer, .divider:
                return item
            }
        }
    }

    private func trailingItem(forTileID tileID: String) -> TrailingTileItem? {
        preferences.trailingItems.first { Self.trailingTileID(for: $0) == tileID }
    }

    private enum ItemScope {
        case pinned(PinnedTileItem)
        case trailing(TrailingTileItem)
    }

    private func itemScope(forTileID tileID: String) -> ItemScope? {
        if let item = pinnedItem(forTileID: tileID) {
            return .pinned(item)
        }
        if let item = trailingItem(forTileID: tileID) {
            return .trailing(item)
        }
        return nil
    }

    private func tile(for item: PinnedTileItem) -> Tile? {
        switch item.kind {
        case .app:
            guard let bundleIdentifier = item.bundleIdentifier else {
                return nil
            }
            guard !preferences.isAppHiddenInDocky(bundleIdentifier: bundleIdentifier) else {
                return nil
            }
            if let tile = dockPinnedTilesByBundleIdentifier[bundleIdentifier] {
                return Self.makePinnedTile(from: tile, item: item)
            }
            return Self.makePinnedTile(bundleIdentifier: bundleIdentifier, item: item)
        case .appFolder:
            let apps = item.folderBundleIdentifiers
                .filter { !preferences.isAppHiddenInDocky(bundleIdentifier: $0) }
                .compactMap(Self.makeAppTile(bundleIdentifier:))
            guard !apps.isEmpty else {
                return nil
            }
            if apps.count == 1, let app = apps.first {
                return Tile(id: Self.pinnedTileID(for: item), content: .app(app))
            }
            return Tile(
                id: Self.pinnedTileID(for: item),
                content: .appFolder(AppFolderTile(
                    identifier: item.id,
                    displayName: item.folderDisplayName ?? "Folder",
                    apps: apps,
                    displayMode: item.appFolderDisplayMode ?? .grid,
                    contentViewMode: item.folderContentViewMode ?? .grid
                ))
            )
        case .launchpad:
            return Tile(
                id: Self.pinnedTileID(for: item),
                content: .launchpad(LaunchpadTile(identifier: item.id))
            )
        case .widget:
            guard let widgetKind = item.widgetKind,
                  let ownerBundleIdentifier = item.widgetOwnerBundleIdentifier else {
                return nil
            }
            return Tile(
                id: Self.pinnedTileID(for: item),
                content: .widget(Self.makeWidgetTile(
                    kind: widgetKind,
                    ownerBundleIdentifier: ownerBundleIdentifier,
                    span: item.widgetSpan ?? .three
                ))
            )
        case .smartStack:
            return Tile(
                id: Self.pinnedTileID(for: item),
                content: .smartStack(Self.makeSmartStackTile(
                    identifier: item.id,
                    widgets: visibleSmartStackWidgets(hiddenOwnerBundleIdentifiers: item.hiddenWidgetOwnerBundleIdentifiers)
                ))
            )
        case .spacer:
            return Tile(id: Self.pinnedTileID(for: item), content: .spacer)
        case .flexibleSpacer:
            return Tile(id: Self.pinnedTileID(for: item), content: .flexibleSpacer)
        case .divider:
            return Tile(id: Self.pinnedTileID(for: item), content: .divider)
        }
    }

    private func trailingTile(for item: TrailingTileItem) -> Tile? {
        switch item.kind {
        case .folder:
            if let sourceTileID = item.sourceTileID,
               let tile = systemOtherTilesByID[sourceTileID],
               case .folder(let folder) = tile.content {
                return Tile(
                    id: Self.trailingTileID(for: item),
                    content: .folder(FolderTile(
                        url: folder.url,
                        displayName: folder.displayName,
                        displayMode: resolvedFolderDisplayMode(for: item),
                        contentViewMode: resolvedFolderContentViewMode(for: item),
                        sortMode: resolvedFolderSortMode(for: item)
                    ))
                )
            }

            guard let folderURL = item.folderURL else {
                return nil
            }
            return Tile(
                id: Self.trailingTileID(for: item),
                content: .folder(FolderTile(
                    url: folderURL,
                    displayName: item.folderDisplayName ?? FileManager.default.displayName(atPath: folderURL.path),
                    displayMode: resolvedFolderDisplayMode(for: item),
                    contentViewMode: resolvedFolderContentViewMode(for: item),
                    sortMode: resolvedFolderSortMode(for: item)
                ))
            )
        case .trash:
            return Tile(id: Self.trailingTileID(for: item), content: .trash)
        case .widget:
            guard let widgetKind = item.widgetKind,
                  let ownerBundleIdentifier = item.widgetOwnerBundleIdentifier else {
                return nil
            }
            return Tile(
                id: Self.trailingTileID(for: item),
                content: .widget(Self.makeWidgetTile(
                    kind: widgetKind,
                    ownerBundleIdentifier: ownerBundleIdentifier,
                    span: item.widgetSpan ?? .three
                ))
            )
        case .smartStack:
            return Tile(
                id: Self.trailingTileID(for: item),
                content: .smartStack(Self.makeSmartStackTile(
                    identifier: item.id,
                    widgets: visibleSmartStackWidgets(hiddenOwnerBundleIdentifiers: item.hiddenWidgetOwnerBundleIdentifiers)
                ))
            )
        case .spacer:
            return Tile(id: Self.trailingTileID(for: item), content: .spacer)
        case .flexibleSpacer:
            return Tile(id: Self.trailingTileID(for: item), content: .flexibleSpacer)
        case .divider:
            return Tile(id: Self.trailingTileID(for: item), content: .divider)
        }
    }

    private func rebuildTiles() {
        let pinnedWithoutFinder = pinnedTiles.filter { !Self.isFinder($0) }
        let pinnedBundleIDs = Self.bundleIdentifiers(in: pinnedWithoutFinder)
        let hiddenBundleIDs = Set(preferences.hiddenAppBundleIdentifiers)

        let currentUnpinned = WorkspaceService.shared.runningApps
            .filter {
                $0.bundleIdentifier != Self.finderBundleID
                    && !pinnedBundleIDs.contains($0.bundleIdentifier)
                    && !hiddenBundleIDs.contains($0.bundleIdentifier)
            }

        displayedRunning = resolveDisplayedRunning(
            currentUnpinned: currentUnpinned,
            pinnedBundleIDs: pinnedBundleIDs
        )

        let shelveMode = preferences.enablesShelveMode
        let hidesFinder = shelveMode && preferences.shelveHidesFinder
        let hidesTrash = shelveMode && preferences.shelveHidesTrash
        let runningTiles: [Tile]
        if !preferences.showsRunningApps {
            runningTiles = []
        } else if preferences.hidesRecentApps {
            // "Hide recent apps" only suppresses the non-running tail ,
            // currently running unpinned apps still belong in the dock.
            // The only non-running entry `displayedRunning` ever holds is
            // the trailing "ghost" preserved by `resolveDisplayedRunning`
            // so a just-quit app's slot doesn't snap shut; filter it out.
            let liveBundleIDs = WorkspaceService.shared.runningBundleIdentifiers
            runningTiles = displayedRunning
                .filter { liveBundleIDs.contains($0.bundleIdentifier) }
                .map(Self.tile(for:))
        } else {
            runningTiles = displayedRunning.map(Self.tile(for:))
        }
        let minimizedWindowTiles = preferences.showsMinimizedWindows
            ? WorkspaceService.shared.minimizedWindows.map(Self.tile(for:))
            : []
        let mergedPinnedTiles = preferences.effectiveShowsActivePinnedSeparator
            ? pinnedWithoutFinder
            : pinnedWithoutFinder + runningTiles

        let leadingFinder: [Tile] = hidesFinder ? [] : [Self.finderTile()]
        var result: [Tile] = tilesWithWidgets(appendedTo: leadingFinder)
        result.append(contentsOf: tilesWithWidgets(appendedTo: mergedPinnedTiles))
        if preferences.effectiveShowsActivePinnedSeparator, !runningTiles.isEmpty {
            result.append(Tile(id: "divider:running", content: .divider))
            result.append(contentsOf: tilesWithWidgets(appendedTo: runningTiles))
        }
        result.append(Tile(id: "divider:trailing", content: .divider))
        let trailing = trailingTiles(withInsertedMinimizedWindows: minimizedWindowTiles)
        result.append(contentsOf: hidesTrash ? trailing.filter { !Self.isTrash($0) } : trailing)
        tiles = result.map(applyingAppWidgetDisplay(to:))
    }

    /// Inserts every `layout.insertions` entry the active theme defines
    /// into the assembled tile list. Anchors are resolved against the
    /// current list, so themes can target stable structural ids
    /// (`divider:trailing`, `divider:running`) or any pinned/running
    /// app by its bundle identifier. Insertions whose anchor doesn't
    /// resolve are skipped silently, themes stay portable across
    /// docks that don't happen to contain the referenced app.
    ///
    /// Called by `TileContainerView.displayTiles` rather than from
    /// `rebuildTiles` so the inserted tiles survive the editor-preview
    /// merge that re-builds the trailing section from
    /// `previewTrailingSectionTiles` (anything in `tiles` past
    /// `divider:trailing` would otherwise be dropped).
    static func applyingThemeLayoutInsertions(to tiles: [Tile]) -> [Tile] {
        guard let insertions = ThemeManager.shared.activeManifest?.layout?.insertions,
              !insertions.isEmpty else {
            return tiles
        }
        var result = tiles
        for (index, insertion) in insertions.enumerated() {
            guard let content = themeInsertionContent(insertion) else { continue }
            let anchorAfter = insertion.after
            let anchorBefore = insertion.before
            guard let anchor = anchorAfter ?? anchorBefore else { continue }
            guard let anchorIdx = themeInsertionAnchorIndex(in: result, anchor: anchor) else { continue }
            let insertAt = anchorAfter != nil ? anchorIdx + 1 : anchorIdx
            let tile = Tile(
                id: "theme:insert:\(index):\(insertion.kind)",
                content: content
            )
            result.insert(tile, at: insertAt)
        }
        return result
    }

    /// Resolves a `ThemeLayoutInsertion` to a `TileContent`. Structural
    /// primitives win first; otherwise the kind is parsed as a
    /// `WidgetKind` raw value and materialized via `WidgetCatalog` so
    /// a theme can drop e.g. a Search bar after Finder with the right
    /// owner-bundle wiring without the user having to do anything.
    private static func themeInsertionContent(_ insertion: ThemeLayoutInsertion) -> TileContent? {
        switch insertion.kind {
        case "spacer": return .spacer
        case "flexibleSpacer": return .flexibleSpacer
        case "divider": return .divider
        default:
            guard let widgetKind = WidgetKind(rawValue: insertion.kind),
                  let registration = WidgetCatalog.staticRegistrations.first(where: { $0.kind == widgetKind }) else {
                return nil
            }
            let span: TileSpan = insertion.span
                .flatMap(TileSpan.init(rawValue:)) ?? registration.defaultSpan
            return .widget(registration.makeTile(span: span))
        }
    }

    private static func themeInsertionAnchorIndex(in tiles: [Tile], anchor: String) -> Int? {
        if let exact = tiles.firstIndex(where: { $0.id == anchor }) {
            return exact
        }
        return tiles.firstIndex { tile in
            if case .app(let app) = tile.content, app.bundleIdentifier == anchor {
                return true
            }
            return false
        }
    }

    private static func isTrash(_ tile: Tile) -> Bool {
        if case .trash = tile.content { return true }
        return false
    }

    private func trailingTiles(withInsertedMinimizedWindows minimizedWindowTiles: [Tile]) -> [Tile] {
        guard !minimizedWindowTiles.isEmpty else {
            return trailingTiles
        }

        var result: [Tile] = []
        var insertedMinimizedWindows = false

        for tile in trailingTiles {
            if !insertedMinimizedWindows, case .trash = tile.content {
                result.append(contentsOf: minimizedWindowTiles)
                insertedMinimizedWindows = true
            }
            result.append(tile)
        }

        if !insertedMinimizedWindows {
            result.append(contentsOf: minimizedWindowTiles)
        }

        return result
    }

    private func tilesWithWidgets(appendedTo baseTiles: [Tile]) -> [Tile] {
        var result: [Tile] = []

        for tile in baseTiles {
            result.append(tile)
            if let bundleIdentifier = bundleIdentifier(of: tile) {
                result.append(contentsOf: widgetTiles(for: bundleIdentifier))
            } else if case .appFolder(let folder) = tile.content {
                result.append(contentsOf: openedAppTiles(for: folder))
            }
        }

        return result
    }

    private func openedAppTiles(for folder: AppFolderTile) -> [Tile] {
        if folder.contentViewMode == .inline {
            guard expandedInlineAppFolderIDs.contains(folder.identifier) else {
                return []
            }

            return folder.apps.map { app in
                Tile(
                    id: "folder-running:\(folder.identifier):\(app.bundleIdentifier)",
                    content: .app(app)
                )
            }
        }

        guard ProductService.shared.isUnlocked(.groupedAppFolders), preferences.showsGroupedOpenedAppsInDock else {
            return []
        }

        let runningBundleIdentifiers = WorkspaceService.shared.runningBundleIdentifiers
        let hiddenBundleIdentifiers = Set(preferences.hiddenAppBundleIdentifiers)
        var result: [Tile] = []

        for app in folder.apps
        where runningBundleIdentifiers.contains(app.bundleIdentifier)
            && !hiddenBundleIdentifiers.contains(app.bundleIdentifier) {
            let tile = Tile(
                id: "folder-running:\(folder.identifier):\(app.bundleIdentifier)",
                content: .app(app)
            )
            result.append(tile)
            result.append(contentsOf: widgetTiles(for: app.bundleIdentifier))
        }

        return result
    }

    private func widgetTiles(for bundleIdentifier: String) -> [Tile] {
        guard !preferences.isAppHiddenInDocky(bundleIdentifier: bundleIdentifier) else {
            return []
        }

        return preferences.widgetPlacements
            .filter { $0.ownerBundleIdentifier == bundleIdentifier && $0.kind != .nowPlaying }
            .map { placement in
                Tile(
                    id: "widget:\(placement.id)",
                    content: .widget(WidgetTile(
                        identifier: placement.id,
                        title: placement.kind.title,
                        kind: placement.kind,
                        ownerBundleIdentifier: placement.ownerBundleIdentifier,
                        span: placement.span
                    ))
                )
            }
    }

    private func applyingAppWidgetDisplay(to tile: Tile) -> Tile {
        guard case .app(let app) = tile.content,
              let displayedWidget = displayedAppWidget(for: app.bundleIdentifier) else {
            return tile
        }

        return Tile(
            id: tile.id,
            content: .app(AppTile(
                bundleIdentifier: app.bundleIdentifier,
                displayName: app.displayName,
                displayedWidget: displayedWidget
            ))
        )
    }

    private func displayedAppWidget(for bundleIdentifier: String) -> WidgetTile? {
        guard let display = appWidgetDisplay(bundleIdentifier: bundleIdentifier),
              !isAppInFolder(bundleIdentifier: bundleIdentifier),
              isAppWidgetDisplayActive(display) else {
            return nil
        }

        return Self.makeWidgetTile(
            kind: display.kind,
            ownerBundleIdentifier: bundleIdentifier,
            span: display.span
        )
    }

    private func isAppWidgetDisplayActive(_ display: AppWidgetDisplay) -> Bool {
        switch display.kind {
        case .nowPlaying:
            mediaPlayback.state(for: display.bundleIdentifier)?.hasContent == true
        case .calendar, .calendarDate, .reminders, .batteries, .systemStatus, .weather, .search:
            true
        }
    }

    private func defaultAppWidgetSpan(kind: WidgetKind, ownerBundleIdentifier: String) -> TileSpan {
        WidgetCatalog.staticRegistrations.first {
            $0.kind == kind && $0.ownerBundleIdentifier == ownerBundleIdentifier
        }?.defaultSpan ?? .three
    }

    private func allSmartStackWidgets() -> [WidgetTile] {
        let staticWidgets = WidgetCatalog.smartStackRegistrations.map {
            $0.makeTile()
        }.filter {
            ProductService.shared.availability(for: $0.kind.productFeature).isUnlocked
        }

        let nowPlayingWidgets = mediaPlayback.statesByBundleIdentifier.values
            .filter(\.hasContent)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { state in
                Self.makeWidgetTile(
                    kind: .nowPlaying,
                    ownerBundleIdentifier: state.bundleIdentifier,
                    span: .three
                )
            }
            .filter {
                ProductService.shared.availability(for: $0.kind.productFeature).isUnlocked
            }

        return staticWidgets + nowPlayingWidgets
    }

    private func visibleSmartStackWidgets(hiddenOwnerBundleIdentifiers: [String]) -> [WidgetTile] {
        let hiddenOwnerBundleIdentifierSet = Set(hiddenOwnerBundleIdentifiers)
        return allSmartStackWidgets().filter { !hiddenOwnerBundleIdentifierSet.contains($0.ownerBundleIdentifier) }
    }

    private static func makeSmartStackTile(identifier: String, widgets: [WidgetTile]) -> SmartStackTile {
        SmartStackTile(
            identifier: identifier,
            title: "Smart Stack",
            widgets: widgets,
            span: .three
        )
    }

    /// Preserves rightmost-unpinned-app position across exits. Rules:
    ///   - Still-running apps keep their display slot.
    ///   - Newly-launched apps append to the end.
    ///   - A non-rightmost exit drops the tile (shifts remaining left).
    ///   - A rightmost exit holds the slot as a ghost until something newer
    ///     launches to take its place (or the ghost's bundle gets pinned).
    private func resolveDisplayedRunning(
        currentUnpinned: [RunningApp],
        pinnedBundleIDs: Set<String>
    ) -> [RunningApp] {
        let hiddenBundleIDs = Set(preferences.hiddenAppBundleIdentifiers)
        let currentMap = Dictionary(
            currentUnpinned.map { ($0.bundleIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let lastIndex = displayedRunning.count - 1

        var survived: [RunningApp] = []
        var pendingGhost: RunningApp?

        for (index, existing) in displayedRunning.enumerated() {
            if pinnedBundleIDs.contains(existing.bundleIdentifier)
                || hiddenBundleIDs.contains(existing.bundleIdentifier) {
                continue
            }
            if let live = currentMap[existing.bundleIdentifier] {
                survived.append(live)
            } else if index == lastIndex {
                pendingGhost = existing
            }
        }

        let existingIDs = Set(displayedRunning.map(\.bundleIdentifier))
        for app in currentUnpinned
        where !existingIDs.contains(app.bundleIdentifier)
            && !hiddenBundleIDs.contains(app.bundleIdentifier) {
            survived.append(app)
        }

        if let ghost = pendingGhost,
           !hiddenBundleIDs.contains(ghost.bundleIdentifier) {
            let ghostLaunch = ghost.launchDate ?? .distantPast
            let hasNewer = survived.contains { app in
                (app.launchDate ?? .distantPast) > ghostLaunch
            }
            if !hasNewer {
                survived.append(ghost)
            }
        }

        return survived
    }

    private static func bundleIdentifiers(in tiles: [Tile]) -> Set<String> {
        var ids: Set<String> = []
        for tile in tiles {
            if case .app(let app) = tile.content, !app.bundleIdentifier.isEmpty {
                ids.insert(app.bundleIdentifier)
            } else if case .appFolder(let folder) = tile.content {
                ids.formUnion(folder.bundleIdentifiers)
            }
        }
        return ids
    }

    private static func isFinder(_ tile: Tile) -> Bool {
        if case .app(let app) = tile.content {
            return app.bundleIdentifier == finderBundleID
        }
        return false
    }

    private static func finderTile() -> Tile {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: finderBundleID)
        let name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? "Finder"
        return Tile(
            id: "pinned:\(finderBundleID)",
            content: .app(AppTile(
                bundleIdentifier: finderBundleID,
                displayName: name
            ))
        )
    }

    nonisolated private static func tile(for minimizedWindow: AppWindow) -> Tile {
        Tile(id: "minimized-window:\(minimizedWindow.windowIdentifier)", content: .minimizedWindow(minimizedWindow))
    }

    nonisolated private static func pinnedItem(from tile: Tile) -> PinnedTileItem? {
        switch tile.content {
        case .app(let app):
            guard !app.bundleIdentifier.isEmpty else {
                return nil
            }
            return .app(bundleIdentifier: app.bundleIdentifier)
        case .appFolder(let folder):
            guard folder.bundleIdentifiers.count >= 2 else {
                return nil
            }
            return .appFolder(
                id: folder.identifier,
                displayName: folder.displayName,
                bundleIdentifiers: folder.bundleIdentifiers,
                displayMode: folder.displayMode,
                contentViewMode: folder.contentViewMode
            )
        case .launchpad(let launchpad):
            return .launchpad(id: launchpad.identifier)
        case .widget, .smartStack:
            return nil
        case .spacer:
            return PinnedTileItem(
                id: tile.id,
                kind: .spacer,
                bundleIdentifier: nil,
                folderDisplayName: nil,
                folderBundleIdentifiers: [],
                appFolderDisplayMode: nil,
                folderContentViewMode: nil,
                widgetKind: nil,
                widgetOwnerBundleIdentifier: nil,
                widgetSpan: nil,
                hiddenWidgetOwnerBundleIdentifiers: []
            )
        case .flexibleSpacer:
            return PinnedTileItem(
                id: tile.id,
                kind: .flexibleSpacer,
                bundleIdentifier: nil,
                folderDisplayName: nil,
                folderBundleIdentifiers: [],
                appFolderDisplayMode: nil,
                folderContentViewMode: nil,
                widgetKind: nil,
                widgetOwnerBundleIdentifier: nil,
                widgetSpan: nil,
                hiddenWidgetOwnerBundleIdentifiers: []
            )
        case .divider:
            return PinnedTileItem(
                id: tile.id,
                kind: .divider,
                bundleIdentifier: nil,
                folderDisplayName: nil,
                folderBundleIdentifiers: [],
                appFolderDisplayMode: nil,
                folderContentViewMode: nil,
                widgetKind: nil,
                widgetOwnerBundleIdentifier: nil,
                widgetSpan: nil,
                hiddenWidgetOwnerBundleIdentifiers: []
            )
        case .folder, .trash, .minimizedWindow:
            return nil
        }
    }

    private static func pinnedTileID(for item: PinnedTileItem) -> String {
        "pinned:\(item.id)"
    }

    private static func trailingTileID(for item: TrailingTileItem) -> String {
        "trailing:\(item.id)"
    }

    private static func matchesImportedPinnedItem(_ existing: PinnedTileItem, _ imported: PinnedTileItem) -> Bool {
        guard existing.kind == imported.kind else {
            return false
        }

        switch imported.kind {
        case .app:
            return existing.bundleIdentifier == imported.bundleIdentifier
        case .launchpad:
            return existing.id == imported.id
        case .spacer, .flexibleSpacer, .divider:
            return existing.id == imported.id
        case .appFolder:
            return existing.id == imported.id
        case .widget, .smartStack:
            return false
        }
    }

    func launchpadApps() -> [AppTile] {
        Self.installedApplications().map { app in
            AppTile(bundleIdentifier: app.bundleIdentifier, displayName: app.displayName)
        }
    }

    nonisolated private static func trailingItem(from tile: Tile) -> TrailingTileItem? {
        switch tile.content {
        case .folder(let folder):
            return .folder(
                sourceTileID: tile.id,
                displayMode: folder.displayMode,
                contentViewMode: folder.contentViewMode
            )
        case .trash:
            return .trash()
        case .launchpad, .widget, .smartStack, .app, .appFolder, .spacer, .flexibleSpacer, .divider, .minimizedWindow:
            return nil
        }
    }

    private func normalizeAppFolderDisplayName(_ value: String) -> String {
        let normalized = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "Folder" : normalized
    }

    // MARK: - Parsing plist entries

    private static func parse(entry: [String: Any], fallbackID: String) -> Tile? {
        let tileType = entry["tile-type"] as? String
        let tileData = entry["tile-data"] as? [String: Any] ?? [:]
        let guid = (entry["GUID"] as? NSNumber)?.stringValue ?? fallbackID

        switch tileType {
        case "file-tile":
            return parseAppTile(id: guid, data: tileData)
        case "directory-tile":
            return parseFolderTile(id: guid, data: tileData)
        case "spacer-tile", "small-spacer-tile":
            return Tile(id: guid, content: .spacer)
        default:
            return nil
        }
    }

    private static func parseAppTile(id: String, data: [String: Any]) -> Tile? {
        let label = (data["file-label"] as? String) ?? "Unknown"
        let fileData = data["file-data"] as? [String: Any]
        let urlString = fileData?["_CFURLString"] as? String
        let url = urlString.flatMap { URL(string: $0) }
        let bundleIdentifier = (data["bundle-identifier"] as? String)
            ?? inferBundleIdentifier(from: url)
            ?? ""
        return Tile(id: id, content: .app(AppTile(
            bundleIdentifier: bundleIdentifier,
            displayName: label
        )))
    }

    private static func makePinnedTile(from tile: Tile, item: PinnedTileItem) -> Tile? {
        guard case .app(let app) = tile.content else {
            return nil
        }

        return Tile(
            id: pinnedTileID(for: item),
            content: .app(AppTile(bundleIdentifier: item.bundleIdentifier ?? "", displayName: app.displayName))
        )
    }

    private static func makePinnedTile(bundleIdentifier: String, item: PinnedTileItem) -> Tile? {
        guard let app = makeAppTile(bundleIdentifier: bundleIdentifier) else {
            return nil
        }

        return Tile(
            id: pinnedTileID(for: item),
            content: .app(app)
        )
    }

    nonisolated private static func makeAppTile(bundleIdentifier: String) -> AppTile? {
        guard !bundleIdentifier.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        return AppTile(
            bundleIdentifier: bundleIdentifier,
            displayName: FileManager.default.displayName(atPath: url.path)
        )
    }

    private static func makeWidgetTile(
        kind: WidgetKind,
        ownerBundleIdentifier: String,
        span: TileSpan
    ) -> WidgetTile {
        WidgetTile(
            identifier: "\(ownerBundleIdentifier):\(kind.rawValue)",
            title: kind.title,
            kind: kind,
            ownerBundleIdentifier: ownerBundleIdentifier,
            span: span
        )
    }

    private static func parseFolderTile(id: String, data: [String: Any]) -> Tile? {
        let label = (data["file-label"] as? String) ?? "Folder"
        let fileData = data["file-data"] as? [String: Any]
        guard let urlString = fileData?["_CFURLString"] as? String,
              let url = URL(string: urlString) else {
            return nil
        }

        let displayMode = parseFolderDisplayMode(from: data["displayas"])
        let contentViewMode = parseFolderContentViewMode(from: data["showas"])
        return Tile(
            id: id,
            content: .folder(FolderTile(
                url: url,
                displayName: label,
                displayMode: displayMode,
                contentViewMode: contentViewMode
            ))
        )
    }

    private static func parseFolderDisplayMode(from rawValue: Any?) -> FolderTileDisplayMode {
        guard (rawValue as? NSNumber)?.intValue == 1 else {
            return .contents
        }

        return .folder
    }

    private static func parseFolderContentViewMode(from rawValue: Any?) -> FolderTileContentViewMode {
        switch (rawValue as? NSNumber)?.intValue {
        case 3:
            return .list
        case 1, 2, nil:
            return .grid
        default:
            return .grid
        }
    }

    private static func inferBundleIdentifier(from url: URL?) -> String? {
        guard let url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    private static func fallbackTileID(for entry: [String: Any], at index: Int, section: String) -> String {
        let tileType = (entry["tile-type"] as? String) ?? "unknown"
        let tileData = entry["tile-data"] as? [String: Any] ?? [:]
        let fileData = tileData["file-data"] as? [String: Any]
        let urlString = fileData?["_CFURLString"] as? String
        let bundleIdentifier = tileData["bundle-identifier"] as? String
        let label = tileData["file-label"] as? String

        let signature = [tileType, bundleIdentifier, urlString, label]
            .compactMap { $0?.replacingOccurrences(of: ":", with: "_") }
            .joined(separator: ":")

        if signature.isEmpty {
            return "\(section):\(index):\(tileType)"
        }

        return "\(section):\(index):\(signature)"
    }

    // MARK: - Running-but-not-pinned tiles

    nonisolated private static func tile(for app: RunningApp) -> Tile {
        Tile(
            id: "running:\(app.bundleIdentifier)",
            content: .app(AppTile(
                bundleIdentifier: app.bundleIdentifier,
                displayName: app.localizedName
            ))
        )
    }
}
