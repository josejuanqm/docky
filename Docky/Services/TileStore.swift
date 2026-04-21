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

final class TileStore: ObservableObject {
    static let shared = TileStore()

    @Published private(set) var tiles: [Tile] = []

    private static let changeNotification = Notification.Name("com.apple.dock.prefchanged")

    private var pinnedTiles: [Tile] = []
    private var otherTiles: [Tile] = []
    private var dockPinnedTilesByBundleIdentifier: [String: Tile] = [:]
    /// Currently displayed unpinned running apps, in visual order. May contain
    /// one "ghost" entry at the end — an app that recently exited but sat at
    /// the rightmost position, preserved until something newer takes its slot.
    private var displayedRunning: [RunningApp] = []

    private var notificationObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private let preferences = DockyPreferences.shared
    private let mediaPlayback = MediaPlaybackService.shared

    private init() {
        refresh()
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.changeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        WorkspaceService.shared.$runningApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildTiles() }
            .store(in: &cancellables)
        preferences.$pinnedItems
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPinnedTilesFromPreferences()
                self?.rebuildTiles()
            }
            .store(in: &cancellables)
        preferences.$widgetPlacements
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildTiles()
            }
            .store(in: &cancellables)
        mediaPlayback.$statesByBundleIdentifier
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
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
        guard let plist = DockPlistReader.read() else {
            pinnedTiles = []
            otherTiles = []
            rebuildTiles()
            return
        }
        let apps = (plist["persistent-apps"] as? [[String: Any]]) ?? []
        let others = (plist["persistent-others"] as? [[String: Any]]) ?? []
        let refreshedPinnedTiles = apps.enumerated().compactMap { index, entry in
            Self.parse(entry: entry, fallbackID: Self.fallbackTileID(for: entry, at: index, section: "persistent-apps"))
        }
        dockPinnedTilesByBundleIdentifier = Dictionary(uniqueKeysWithValues: refreshedPinnedTiles.compactMap { tile in
            bundleIdentifier(of: tile).map { ($0, tile) }
        })
        seedPinnedPreferencesIfNeeded(from: refreshedPinnedTiles)
        refreshPinnedTilesFromPreferences()
        otherTiles = others.enumerated().compactMap { index, entry in
            Self.parse(entry: entry, fallbackID: Self.fallbackTileID(for: entry, at: index, section: "persistent-others"))
        }
        rebuildTiles()
    }

    func isPinnedReorderable(tileID: String) -> Bool {
        pinnedTiles.contains { $0.id == tileID }
    }

    func isPinned(bundleIdentifier: String) -> Bool {
        preferences.pinnedItems.contains {
            $0.kind == .app && $0.bundleIdentifier == bundleIdentifier
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
        guard ids.count == pinnedTiles.count else {
            return
        }

        let tilesByID = Dictionary(uniqueKeysWithValues: pinnedTiles.map { ($0.id, $0) })
        let reorderedTiles = ids.compactMap { tilesByID[$0] }
        guard reorderedTiles.count == pinnedTiles.count else {
            return
        }

        let itemsByID = Dictionary(uniqueKeysWithValues: preferences.pinnedItems.map { (Self.pinnedTileID(for: $0), $0) })
        let reorderedItems = ids.compactMap { itemsByID[$0] }
        guard reorderedItems.count == preferences.pinnedItems.count else {
            return
        }

        pinnedTiles = reorderedTiles
        preferences.pinnedItems = reorderedItems
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

    func insertPinnedItem(kind: PinnedTileItemKind, at destinationIndex: Int) {
        let item: PinnedTileItem
        switch kind {
        case .app:
            return
        case .spacer:
            item = .spacer()
        case .divider:
            item = .divider()
        }

        var pinnedItems = preferences.pinnedItems
        let clampedDestinationIndex = min(max(destinationIndex, 0), pinnedItems.count)
        pinnedItems.insert(item, at: clampedDestinationIndex)
        preferences.pinnedItems = pinnedItems
        refreshPinnedTilesFromPreferences()
        rebuildTiles()
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

    private static let finderBundleID = "com.apple.finder"

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

    private func tile(for item: PinnedTileItem) -> Tile? {
        switch item.kind {
        case .app:
            guard let bundleIdentifier = item.bundleIdentifier else {
                return nil
            }
            if let tile = dockPinnedTilesByBundleIdentifier[bundleIdentifier] {
                return Self.makePinnedTile(from: tile, item: item)
            }
            return Self.makePinnedTile(bundleIdentifier: bundleIdentifier, item: item)
        case .spacer:
            return Tile(id: Self.pinnedTileID(for: item), content: .spacer)
        case .divider:
            return Tile(id: Self.pinnedTileID(for: item), content: .divider)
        }
    }

    private func rebuildTiles() {
        let pinnedWithoutFinder = pinnedTiles.filter { !Self.isFinder($0) }
        let pinnedBundleIDs = Self.bundleIdentifiers(in: pinnedWithoutFinder)

        let currentUnpinned = WorkspaceService.shared.runningApps
            .filter { $0.bundleIdentifier != Self.finderBundleID && !pinnedBundleIDs.contains($0.bundleIdentifier) }

        displayedRunning = resolveDisplayedRunning(
            currentUnpinned: currentUnpinned,
            pinnedBundleIDs: pinnedBundleIDs
        )

        let runningTiles = displayedRunning.map(Self.tile(for:))
        let trailingSmartStackTile = smartStackTile()

        var result: [Tile] = tilesWithWidgets(appendedTo: [Self.finderTile()])
        result.append(contentsOf: tilesWithWidgets(appendedTo: pinnedWithoutFinder))
        if !runningTiles.isEmpty {
            result.append(Tile(id: "divider:running", content: .divider))
        }
        result.append(contentsOf: tilesWithWidgets(appendedTo: runningTiles))
        result.append(Tile(id: "divider:trailing", content: .divider))
        if let trailingSmartStackTile {
            result.append(trailingSmartStackTile)
        }
        result.append(contentsOf: otherTiles)
        result.append(Tile(id: "trash", content: .trash))
        tiles = result
    }

    private func tilesWithWidgets(appendedTo baseTiles: [Tile]) -> [Tile] {
        var result: [Tile] = []

        for tile in baseTiles {
            result.append(tile)
            guard let bundleIdentifier = bundleIdentifier(of: tile) else {
                continue
            }
            result.append(contentsOf: widgetTiles(for: bundleIdentifier))
        }

        return result
    }

    private func widgetTiles(for bundleIdentifier: String) -> [Tile] {
        preferences.widgetPlacements
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

    private func smartStackTile() -> Tile? {
        let widgets = mediaPlayback.statesByBundleIdentifier.values
            .filter(\.hasContent)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { state in
                WidgetTile(
                    identifier: "\(state.bundleIdentifier):nowPlaying",
                    title: WidgetKind.nowPlaying.title,
                    kind: .nowPlaying,
                    ownerBundleIdentifier: state.bundleIdentifier,
                    span: .three
                )
            }

        guard !widgets.isEmpty else {
            return nil
        }

        return Tile(
            id: "smart-stack:media",
            content: .smartStack(SmartStackTile(
                identifier: "media",
                title: "Smart Stack",
                widgets: widgets,
                span: .three
            ))
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
        let currentMap = Dictionary(
            uniqueKeysWithValues: currentUnpinned.map { ($0.bundleIdentifier, $0) }
        )
        let lastIndex = displayedRunning.count - 1

        var survived: [RunningApp] = []
        var pendingGhost: RunningApp?

        for (index, existing) in displayedRunning.enumerated() {
            if pinnedBundleIDs.contains(existing.bundleIdentifier) {
                continue
            }
            if let live = currentMap[existing.bundleIdentifier] {
                survived.append(live)
            } else if index == lastIndex {
                pendingGhost = existing
            }
        }

        let existingIDs = Set(displayedRunning.map(\.bundleIdentifier))
        for app in currentUnpinned where !existingIDs.contains(app.bundleIdentifier) {
            survived.append(app)
        }

        if let ghost = pendingGhost {
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

    nonisolated private static func pinnedItem(from tile: Tile) -> PinnedTileItem? {
        switch tile.content {
        case .app(let app):
            guard !app.bundleIdentifier.isEmpty else {
                return nil
            }
            return .app(bundleIdentifier: app.bundleIdentifier)
        case .spacer:
            return PinnedTileItem(id: tile.id, kind: .spacer, bundleIdentifier: nil)
        case .divider:
            return PinnedTileItem(id: tile.id, kind: .divider, bundleIdentifier: nil)
        case .widget, .smartStack, .folder, .trash:
            return nil
        }
    }

    private static func pinnedTileID(for item: PinnedTileItem) -> String {
        "pinned:\(item.id)"
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
        guard !bundleIdentifier.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        return Tile(
            id: pinnedTileID(for: item),
            content: .app(AppTile(
                bundleIdentifier: bundleIdentifier,
                displayName: FileManager.default.displayName(atPath: url.path)
            ))
        )
    }

    private static func parseFolderTile(id: String, data: [String: Any]) -> Tile? {
        let label = (data["file-label"] as? String) ?? "Folder"
        let fileData = data["file-data"] as? [String: Any]
        guard let urlString = fileData?["_CFURLString"] as? String,
              let url = URL(string: urlString) else {
            return nil
        }
        return Tile(id: id, content: .folder(FolderTile(url: url, displayName: label)))
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
