//
//  LaunchpadOverlayService.swift
//  Docky
//

import AppKit
import Combine
import CoreImage
import Foundation
import Observation

/// What the launchpad grid shows: either an app at the top of /Applications,
/// or a subfolder of /Applications represented as a dock-style app folder
/// tile (e.g. /Applications/Utilities). The launchpad mirrors the
/// /Applications directory structure one level deep — anything inside a
/// subfolder is reached through the folder tile, not flattened into the top
/// level.
enum LaunchpadEntry: Identifiable {
    case app(AppTile)
    case folder(AppFolderTile)

    var id: String {
        switch self {
        case .app(let app): return "app:\(app.bundleIdentifier)"
        case .folder(let folder): return "folder:\(folder.identifier)"
        }
    }

    var displayName: String {
        switch self {
        case .app(let app): return app.displayName
        case .folder(let folder): return folder.displayName
        }
    }

    var matchableBundleIdentifier: String {
        switch self {
        case .app(let app): return app.bundleIdentifier
        case .folder: return ""
        }
    }
}

/// Snapshot of the filesystem scan, consumed by the layout pipeline
/// to seed the initial layout and reconcile installs/removals.
struct LaunchpadScan {
    struct SeedGroup {
        let name: String
        let bundleIDs: [String]
    }

    let appsByBundleID: [String: AppTile]
    /// `.app` bundles that sat directly under an applications root
    /// (not inside a subdirectory). Used for initial seed only.
    let topLevelApps: [AppTile]
    /// Subdirectories under an applications root that contained at
    /// least one app, in scan order. Each becomes a virtual folder
    /// in the first-launch seed.
    let fsGroups: [SeedGroup]

    /// Initial layout items, alpha-sorted by display name. Top-level
    /// `.app` entries and FS folder groups are interleaved so the
    /// user lands on something close to what they had before.
    func seedLayoutItems() -> [LaunchpadLayoutItem] {
        struct Sortable {
            let name: String
            let item: LaunchpadLayoutItem
        }
        var sortables: [Sortable] = []
        sortables.reserveCapacity(topLevelApps.count + fsGroups.count)

        for app in topLevelApps {
            sortables.append(Sortable(
                name: app.displayName,
                item: .app(bundleID: app.bundleIdentifier)
            ))
        }
        for group in fsGroups {
            sortables.append(Sortable(
                name: group.name,
                item: .folder(LaunchpadFolder(
                    id: UUID().uuidString,
                    name: group.name,
                    bundleIDs: group.bundleIDs
                ))
            ))
        }

        sortables.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return sortables.map(\.item)
    }
}

final class LaunchpadOverlayService: ObservableObject {
    static let shared = LaunchpadOverlayService()

    @Published private(set) var isPresented = false
    @Published private(set) var entries: [LaunchpadEntry] = []
    /// Wallpaper for the screen the overlay is currently presented on. Driven
    /// by the window controller before the overlay animates in so the view
    /// can render the desktop image as the launchpad's blurred background.
    @Published var wallpaperURL: URL?
    /// Average wallpaper luminance in [0, 1] (Rec. 709 weights). Recomputed
    /// asynchronously off-main whenever `wallpaperURL` changes so the view
    /// can flip its color scheme for legibility on light wallpapers.
    @Published private(set) var wallpaperLuminance: Double = 0

    /// Roots scanned for launchpad entries. `/Applications` holds user-
    /// installed apps; `/System/Applications` holds Apple-provided ones
    /// (Calculator, Notes, Reminders, etc.) — without it the launchpad
    /// would be missing every built-in app. `~/Applications` is rare but
    /// some installers put per-user apps there.
    private static let applicationDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
    ]
    private let scanQueue = DispatchQueue(
        label: "gt.quintero.Docky.LaunchpadScan",
        qos: .utility
    )
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var pendingRescan: DispatchWorkItem?
    private var wallpaperLuminanceSubscription: AnyCancellable?
    private static let luminanceContext = CIContext(options: [.workingColorSpace: NSNull()])

    /// Cached app metadata from the most recent filesystem scan. The
    /// layout service can mutate independently of the scan (drag-and-drop,
    /// rename, ungroup); we re-resolve `entries` against this cache so
    /// the grid updates immediately without waiting for another scan.
    private var appsByBundleID: [String: AppTile] = [:]

    private init() {
        startWatchingApplicationDirectories()
        observeWallpaperURL()
        scheduleRescan(delay: 0)
    }

    func toggle() {
        isPresented ? dismiss() : present()
    }

    func present() {
        guard ProductService.shared.isUnlocked(.launchpad), DockyPreferences.shared.enablesLaunchpadOverlay else {
            dismiss()
            return
        }

        if entries.isEmpty {
            // Run a synchronous scan so the overlay has something to
            // render on first present; async rescans then keep it
            // fresh as the user installs / uninstalls apps.
            applyScan(Self.scanApplications())
        }
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }

    /// Recompute average wallpaper luminance whenever the URL changes.
    /// CIAreaAverage is GPU-accelerated and renders down to a 1×1 tile, so
    /// the work amortizes well — but the JPEG/HEIC decode in front of it
    /// can be tens of milliseconds, hence the user-initiated background
    /// queue and `switchToLatest` to drop in-flight work if the user flips
    /// to another screen mid-flight.
    private func observeWallpaperURL() {
        wallpaperLuminanceSubscription = $wallpaperURL
            .removeDuplicates()
            .map { url -> AnyPublisher<Double, Never> in
                guard let url else {
                    return Just(0).eraseToAnyPublisher()
                }
                return Future { promise in
                    DispatchQueue.global(qos: .userInitiated).async {
                        promise(.success(Self.computeAverageLuminance(of: url) ?? 0))
                    }
                }
                .eraseToAnyPublisher()
            }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] luminance in
                self?.wallpaperLuminance = luminance
            }
    }

    private static func computeAverageLuminance(of url: URL) -> Double? {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: ciImage.extent)
        ]),
              let output = filter.outputImage else {
            return nil
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        Self.luminanceContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        // Rec. 709 perceived luminance on gamma-encoded sRGB. Good enough
        // for a colorScheme threshold; not worth a precise sRGB→linear
        // round-trip when we just need a light-vs-dark decision.
        let r = Double(bitmap[0]) / 255
        let g = Double(bitmap[1]) / 255
        let b = Double(bitmap[2]) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private func startWatchingApplicationDirectories() {
        for directory in Self.applicationDirectories {
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }

            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .extend, .link],
                queue: DispatchQueue.main
            )
            source.setEventHandler { [weak self] in
                // Coalesce burst events (an install touches the directory many
                // times in quick succession) into one rescan.
                self?.scheduleRescan(delay: 0.5)
            }
            source.setCancelHandler { [descriptor] in
                close(descriptor)
            }
            source.resume()
            watchers.append(source)
        }
    }

    private func scheduleRescan(delay: TimeInterval) {
        pendingRescan?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.performRescan()
        }
        pendingRescan = task

        if delay <= 0 {
            scanQueue.async(execute: task)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, scanQueue] in
                guard let self, !task.isCancelled, self.pendingRescan === task else { return }
                scanQueue.async(execute: task)
            }
        }
    }

    private func performRescan() {
        let scan = Self.scanApplications()
        // Warm icon cache off the main thread (the icon service is
        // thread-safe; the actual NSImage materializes on first read).
        for app in scan.appsByBundleID.values {
            _ = IconCacheService.shared.icon(forBundleIdentifier: app.bundleIdentifier)
        }
        DispatchQueue.main.async { [weak self] in
            self?.applyScan(scan)
        }
    }

    @MainActor
    private func applyScan(_ scan: LaunchpadScan) {
        appsByBundleID = scan.appsByBundleID

        let layoutService = LaunchpadLayoutService.shared

        // First launch: import the alpha-sorted FS structure (apps +
        // FS-folder-derived virtual folders) into the user-editable
        // layout. From then on the layout drives ordering.
        if layoutService.layout.items.isEmpty {
            let seed = scan.seedLayoutItems()
            layoutService.seedIfEmpty(seed)
        }

        let installed = Set(scan.appsByBundleID.keys)
        layoutService.pruneMissingApps(installedBundleIDs: installed)
        layoutService.appendNewApps(scan.appsByBundleID.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        })

        recomputeEntries()
        observeLayoutChanges()
    }

    /// Pushes the freshest layout into `entries`. Triggered both by
    /// filesystem rescans (via `applyScan`) and by user-driven layout
    /// mutations (via the observation hook below).
    @MainActor
    private func recomputeEntries() {
        entries = Self.resolveEntries(
            layout: LaunchpadLayoutService.shared.layout,
            appsByBundleID: appsByBundleID
        )
    }

    /// Re-runs `recomputeEntries` whenever the layout service publishes
    /// a change. Re-registers the tracking closure each time because
    /// `withObservationTracking` is single-shot.
    @MainActor
    private func observeLayoutChanges() {
        withObservationTracking { [weak self] in
            // Touch the layout so Observation records a dependency.
            _ = LaunchpadLayoutService.shared.layout
            _ = self
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.recomputeEntries()
                self.observeLayoutChanges()
            }
        }
    }

    /// Resolves the persisted layout against the live filesystem
    /// scan into the renderable entry list. Folders with zero or one
    /// resolvable apps degrade gracefully.
    private static func resolveEntries(
        layout: LaunchpadLayout,
        appsByBundleID: [String: AppTile]
    ) -> [LaunchpadEntry] {
        var entries: [LaunchpadEntry] = []
        entries.reserveCapacity(layout.items.count)

        for item in layout.items {
            switch item {
            case .app(let bundleID):
                if let app = appsByBundleID[bundleID] {
                    entries.append(.app(app))
                }
            case .folder(let folder):
                let resolved = folder.bundleIDs.compactMap { appsByBundleID[$0] }
                guard !resolved.isEmpty else { continue }
                // A folder with one surviving app renders as a plain
                // app card; the layout service collapses these
                // permanently on the next prune, but we render the
                // current state correctly either way.
                if resolved.count == 1 {
                    entries.append(.app(resolved[0]))
                } else {
                    let folderTile = AppFolderTile(
                        identifier: "virtual:\(folder.id)",
                        displayName: folder.name,
                        apps: resolved,
                        displayMode: .grid,
                        contentViewMode: .grid
                    )
                    entries.append(.folder(folderTile))
                }
            }
        }

        return entries
    }

    /// Walk each application root one level deep. A `.app` bundle
    /// becomes a top-level app; any subdirectory containing apps
    /// becomes a named group that the layout service consumes as a
    /// seed for virtual folders. Duplicates across roots are
    /// deduped by bundle id.
    ///
    /// Backed by Spotlight (`ApplicationBundleScanner`) so the scan
    /// works inside the App Store sandbox without read access to
    /// `/Applications` etc. Groups are derived from each app's
    /// containing directory: apps in a canonical root (`/Applications`,
    /// `/System/Applications`, `~/Applications`) are top-level;
    /// anything one level deeper (like `/Applications/Utilities`)
    /// gets grouped under its enclosing folder's name.
    @MainActor
    private static func scanApplications() -> LaunchpadScan {
        let canonicalRoots: Set<String> = Set(applicationDirectories.map { $0.standardizedFileURL.path })

        var appsByBundleID: [String: AppTile] = [:]
        var topLevelApps: [AppTile] = []
        var groupedBundleIDsByDirectory: [URL: [String]] = [:]
        var groupOrder: [URL] = []

        for discovered in ApplicationBundleScanner.shared.installedApps {
            guard let appTile = makeAppTile(from: discovered.url) else { continue }
            // Self-skip is handled by the scanner / makeAppTile.
            appsByBundleID[appTile.bundleIdentifier] = appTile

            let containing = discovered.containingDirectory?.standardizedFileURL
            if let containing, !canonicalRoots.contains(containing.path) {
                if groupedBundleIDsByDirectory[containing] == nil {
                    groupOrder.append(containing)
                    groupedBundleIDsByDirectory[containing] = []
                }
                groupedBundleIDsByDirectory[containing]?.append(appTile.bundleIdentifier)
            } else {
                topLevelApps.append(appTile)
            }
        }

        let fsGroups: [LaunchpadScan.SeedGroup] = groupOrder.map { url in
            LaunchpadScan.SeedGroup(
                name: FileManager.default.displayName(atPath: url.path),
                bundleIDs: groupedBundleIDsByDirectory[url] ?? []
            )
        }

        return LaunchpadScan(
            appsByBundleID: appsByBundleID,
            topLevelApps: topLevelApps,
            fsGroups: fsGroups
        )
    }

    private static func scanSubfolderApps(in folderURL: URL, seenBundleIDs: inout Set<String>) -> [AppTile] {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var apps: [AppTile] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "app",
                  let app = makeAppTile(from: url),
                  seenBundleIDs.insert(app.bundleIdentifier).inserted else { continue }
            apps.append(app)
        }
        apps.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return apps
    }

    private static func makeAppTile(from url: URL) -> AppTile? {
        guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier,
              !bundleIdentifier.isEmpty,
              bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }
        let displayName = FileManager.default.displayName(atPath: url.path)
        return AppTile(bundleIdentifier: bundleIdentifier, displayName: displayName)
    }

    deinit {
        for source in watchers {
            source.cancel()
        }
    }
}
