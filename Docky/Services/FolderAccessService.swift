//
//  FolderAccessService.swift
//  Docky
//
//  Reads folder contents for preview tiles. Relies on the .userFolders
//  permission granted via Full Disk Access. Silent no-op when access isn't
//  granted.
//

import Combine
import Dispatch
import Foundation

enum FolderContentsSnapshot: Equatable {
    case loaded([URL])
    case unreadable
}

final class FolderAccessService: ObservableObject {
    static let shared = FolderAccessService()

    @Published private(set) var changeToken: UInt64 = 0

    private let staleAfter: TimeInterval = 15
    private var contentsCache: [URL: (date: Date, items: [URL])] = [:]
    private var watchersByURL: [URL: FolderWatcher] = [:]
    private var sortCache: [FolderSortCacheKey: (date: Date, items: [URL])] = [:]
    private let maxSortCacheEntries = 32
    private var sortEntries: [URL: (date: Date, entry: FolderSortEntry)] = [:]
    /// Bumped whenever cached state is invalidated, so a background read
    /// that started before the invalidation is not stored as fresh.
    private var invalidationCount: UInt64 = 0
    private var folderReads: [URL: (invalidationCount: UInt64, task: Task<[FolderSortEntry]?, Never>)] = [:]
    private var refreshingSortKeys: Set<FolderSortCacheKey> = []

    private init() {}

    deinit {
        for watcher in watchersByURL.values {
            watcher.source.cancel()
        }
    }

    /// All visible contents of the folder, newest-modified first.
    /// Cached briefly to avoid hitting the filesystem on every view update.
    func contents(of folderURL: URL) -> [URL] {
        if case .loaded(let items) = snapshot(of: folderURL) {
            return items
        }
        return []
    }

    func snapshot(of folderURL: URL) -> FolderContentsSnapshot {
        cachedSnapshot(of: folderURL)
    }

    /// Same result as `snapshot(of:)`, but a stale or missing cache entry is
    /// re-read off the main thread. Use from views that refresh in a task.
    func refreshedSnapshot(of folderURL: URL) async -> FolderContentsSnapshot {
        let normalizedFolderURL = folderURL.standardizedFileURL
        if let items = freshContents(of: normalizedFolderURL) {
            return .loaded(items)
        }

        let startedAt = invalidationCount
        let read: Task<[FolderSortEntry]?, Never>
        if let inFlight = folderReads[normalizedFolderURL], inFlight.invalidationCount == startedAt {
            read = inFlight.task
        } else {
            read = Task.detached(priority: .userInitiated) {
                Self.readEntries(ofFolder: normalizedFolderURL)
            }
            folderReads[normalizedFolderURL] = (startedAt, read)
        }

        let entries = await read.value
        if folderReads[normalizedFolderURL]?.task == read {
            folderReads.removeValue(forKey: normalizedFolderURL)
        }
        guard let entries else {
            return .unreadable
        }

        // The folder changed while it was being read: hand the result back
        // but leave the cache empty so the next read starts over.
        guard invalidationCount == startedAt else {
            return .loaded(entries.map(\.url))
        }
        return .loaded(store(entries, forFolder: normalizedFolderURL))
    }

    func sortedContents(of folderURL: URL, sortMode: FolderTileSortMode) -> [URL] {
        sortedItems(in: contents(of: folderURL), sortMode: sortMode)
    }

    /// Async counterpart of `sortedContents(of:sortMode:)` that keeps the
    /// folder read off the main thread.
    func refreshedSortedContents(of folderURL: URL, sortMode: FolderTileSortMode) async -> [URL] {
        sortedItems(in: await refreshedSnapshot(of: folderURL), sortMode: sortMode)
    }

    /// Memoized for `staleAfter` seconds, same window as the contents cache.
    /// Views read the sorted list several times per update (layout math plus
    /// the grid itself), and every uncached sort re-reads resource values
    /// from disk for each item.
    func sortedItems(in items: [URL], sortMode: FolderTileSortMode) -> [URL] {
        let key = FolderSortCacheKey(items: items, sortMode: sortMode)
        let now = Date()
        let cached = sortCache[key]
        if let cached, now.timeIntervalSince(cached.date) < staleAfter {
            return cached.items
        }

        // Prefer the metadata captured while the folder was read. URLs drop
        // their prefetched resource values when the run loop turns, so
        // building entries here would go back to disk for every item.
        if let captured = capturedEntries(for: items, at: now) {
            let sorted = sortedURLs(from: captured.entries, sortMode: sortMode)
            // Dated by the metadata, not the sort, so captured values never
            // outlive `staleAfter`.
            storeSort(sorted, date: captured.date, for: key)
            return sorted
        }

        // The memoized order expired and so did the metadata. Keep showing
        // the current order and re-read the metadata off the main thread;
        // `changeToken` announces the new order if it differs.
        if let cached {
            refreshSortInBackground(for: key)
            return cached.items
        }

        let sorted = sortedURLs(from: items.map { FolderSortEntry(url: $0) }, sortMode: sortMode)
        storeSort(sorted, date: now, for: key)
        return sorted
    }

    private func capturedEntries(for items: [URL], at now: Date) -> (date: Date, entries: [FolderSortEntry])? {
        var oldest = now
        var entries: [FolderSortEntry] = []
        entries.reserveCapacity(items.count)
        for url in items {
            guard let captured = sortEntries[url],
                  now.timeIntervalSince(captured.date) < staleAfter else {
                return nil
            }
            oldest = min(oldest, captured.date)
            entries.append(captured.entry)
        }
        return (oldest, entries)
    }

    private func storeSort(_ sorted: [URL], date: Date, for key: FolderSortCacheKey) {
        if sortCache[key] == nil, sortCache.count >= maxSortCacheEntries {
            sortCache.removeAll()
        }
        sortCache[key] = (date, sorted)
    }

    private func refreshSortInBackground(for key: FolderSortCacheKey) {
        guard !refreshingSortKeys.contains(key) else {
            return
        }

        refreshingSortKeys.insert(key)
        let startedAt = invalidationCount
        let items = key.items
        Task {
            let entries = await Task.detached(priority: .userInitiated) {
                items.map { FolderSortEntry(url: $0, discardingCachedValues: true) }
            }.value

            refreshingSortKeys.remove(key)
            guard invalidationCount == startedAt else {
                return
            }

            let now = Date()
            for entry in entries where sortEntries[entry.url] != nil {
                sortEntries[entry.url] = (now, entry)
            }
            let sorted = sortedURLs(from: entries, sortMode: key.sortMode)
            let orderChanged = sortCache[key]?.items != sorted
            storeSort(sorted, date: now, for: key)
            if orderChanged {
                changeToken &+= 1
            }
        }
    }

    private func sortedURLs(from entries: [FolderSortEntry], sortMode: FolderTileSortMode) -> [URL] {
        entries.sorted { lhs, rhs in
            switch sortMode {
            case .name:
                let comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                if lhs.modificationDate != rhs.modificationDate {
                    return lhs.modificationDate > rhs.modificationDate
                }
            case .dateModified:
                if lhs.modificationDate != rhs.modificationDate {
                    return lhs.modificationDate > rhs.modificationDate
                }
                let comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            case .dateCreated:
                if lhs.creationDate != rhs.creationDate {
                    return lhs.creationDate > rhs.creationDate
                }
                let comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            case .dateAdded:
                if lhs.addedDate != rhs.addedDate {
                    return lhs.addedDate > rhs.addedDate
                }
                let comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            case .kind:
                let kindComparison = lhs.kind.localizedStandardCompare(rhs.kind)
                if kindComparison != .orderedSame {
                    return kindComparison == .orderedAscending
                }
                let nameComparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
            case .size:
                if lhs.size != rhs.size {
                    return lhs.size > rhs.size
                }
                let comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            }

            return lhs.url.path < rhs.url.path
        }
        .map(\.url)
    }

    func sortedItems(in snapshot: FolderContentsSnapshot, sortMode: FolderTileSortMode) -> [URL] {
        guard case .loaded(let items) = snapshot else {
            return []
        }

        return sortedItems(in: items, sortMode: sortMode)
    }

    /// Up to `limit` URLs from the folder, newest-modified first.
    func recentContents(of folderURL: URL, sortMode: FolderTileSortMode, limit: Int = 3) -> [URL] {
        Array(sortedContents(of: folderURL, sortMode: sortMode).prefix(limit))
    }

    func beginWatching(_ folderURL: URL, ownerID: String) {
        let normalizedFolderURL = folderURL.standardizedFileURL
        if var watcher = watchersByURL[normalizedFolderURL] {
            watcher.ownerIDs.insert(ownerID)
            watchersByURL[normalizedFolderURL] = watcher
            return
        }

        let descriptor = open(normalizedFolderURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend, .link, .revoke],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            self?.handleWatcherEvent(for: normalizedFolderURL)
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }

        watchersByURL[normalizedFolderURL] = FolderWatcher(
            ownerIDs: [ownerID],
            source: source
        )
        source.resume()
    }

    func endWatching(_ folderURL: URL, ownerID: String) {
        let normalizedFolderURL = folderURL.standardizedFileURL
        guard var watcher = watchersByURL[normalizedFolderURL] else {
            return
        }

        watcher.ownerIDs.remove(ownerID)
        guard watcher.ownerIDs.isEmpty else {
            watchersByURL[normalizedFolderURL] = watcher
            return
        }

        watchersByURL.removeValue(forKey: normalizedFolderURL)
        watcher.source.cancel()
    }

    private func cachedSnapshot(of folderURL: URL) -> FolderContentsSnapshot {
        let normalizedFolderURL = folderURL.standardizedFileURL

        if let items = freshContents(of: normalizedFolderURL) {
            return .loaded(items)
        }

        guard let entries = Self.readEntries(ofFolder: normalizedFolderURL) else {
            return .unreadable
        }
        return .loaded(store(entries, forFolder: normalizedFolderURL))
    }

    private func freshContents(of normalizedFolderURL: URL) -> [URL]? {
        guard let cached = contentsCache[normalizedFolderURL],
              Date().timeIntervalSince(cached.date) < staleAfter else {
            return nil
        }
        return cached.items
    }

    /// Lists the folder newest-modified first along with each item's sort
    /// metadata. Returns nil when the folder cannot be read.
    nonisolated private static func readEntries(ofFolder normalizedFolderURL: URL) -> [FolderSortEntry]? {
        guard FileManager.default.isReadableFile(atPath: normalizedFolderURL.path) else {
            return nil
        }

        let keys: [URLResourceKey] = [
            .addedToDirectoryDateKey,
            .contentModificationDateKey,
            .creationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .localizedNameKey,
            .localizedTypeDescriptionKey,
            .totalFileAllocatedSizeKey
        ]
        guard let listed = try? FileManager.default.contentsOfDirectory(
            at: normalizedFolderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        // The listing prefetched `keys`, so capturing the sort metadata now
        // costs no extra disk access.
        return listed
            .map { FolderSortEntry(url: $0) }
            .sorted(by: { $0.modificationDate > $1.modificationDate })
    }

    private func store(_ entries: [FolderSortEntry], forFolder normalizedFolderURL: URL) -> [URL] {
        let now = Date()
        removeSortEntries(forContentsOf: normalizedFolderURL)
        for entry in entries {
            sortEntries[entry.url] = (now, entry)
        }
        let loaded = entries.map(\.url)
        contentsCache[normalizedFolderURL] = (now, loaded)
        return loaded
    }

    func invalidateCache() {
        invalidationCount &+= 1
        contentsCache.removeAll()
        sortCache.removeAll()
        sortEntries.removeAll()
    }

    private func invalidateCache(for folderURL: URL) {
        invalidationCount &+= 1
        removeSortEntries(forContentsOf: folderURL.standardizedFileURL)
        contentsCache.removeValue(forKey: folderURL.standardizedFileURL)
        sortCache.removeAll()
    }

    private func removeSortEntries(forContentsOf normalizedFolderURL: URL) {
        guard let cached = contentsCache[normalizedFolderURL] else {
            return
        }

        for url in cached.items {
            sortEntries.removeValue(forKey: url)
        }
    }

    private func handleWatcherEvent(for folderURL: URL) {
        invalidateCache(for: folderURL)
        changeToken &+= 1
    }
}

private struct FolderWatcher {
    var ownerIDs: Set<String>
    let source: DispatchSourceFileSystemObject
}

private struct FolderSortCacheKey: Hashable {
    let items: [URL]
    let sortMode: FolderTileSortMode
}

nonisolated private struct FolderSortEntry: Sendable {
    let url: URL
    let displayName: String
    let modificationDate: Date
    let creationDate: Date
    let addedDate: Date
    let kind: String
    let size: Int
    let isDirectory: Bool

    /// `discardingCachedValues` forces a read from disk. URLs only drop
    /// their cached resource values when a run loop turns, which never
    /// happens for values read on a background thread.
    init(url: URL, discardingCachedValues: Bool = false) {
        var source = url
        if discardingCachedValues {
            source.removeAllCachedResourceValues()
        }
        let values = try? source.resourceValues(forKeys: [
            .addedToDirectoryDateKey,
            .contentModificationDateKey,
            .creationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .localizedNameKey,
            .localizedTypeDescriptionKey,
            .totalFileAllocatedSizeKey
        ])
        self.url = url
        self.displayName = values?.localizedName ?? url.lastPathComponent
        self.modificationDate = values?.contentModificationDate ?? .distantPast
        self.creationDate = values?.creationDate ?? .distantPast
        self.addedDate = values?.addedToDirectoryDate ?? .distantPast
        self.kind = values?.localizedTypeDescription ?? ""
        self.size = values?.fileSize ?? values?.totalFileAllocatedSize ?? 0
        self.isDirectory = values?.isDirectory == true
    }
}
