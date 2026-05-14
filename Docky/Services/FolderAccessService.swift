//
//  FolderAccessService.swift
//  Docky
//
//  Reads folder contents for preview tiles. Relies on the .userFolders
//  permission granted via Full Disk Access. Silent no-op when access isn't
//  granted.
//

import AppKit
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

    func sortedContents(of folderURL: URL, sortMode: FolderTileSortMode) -> [URL] {
        sortedItems(in: contents(of: folderURL), sortMode: sortMode)
    }

    func sortedItems(in items: [URL], sortMode: FolderTileSortMode) -> [URL] {
        let entries = items.map(FolderSortEntry.init)

        return entries.sorted { lhs, rhs in
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

        if let cached = contentsCache[normalizedFolderURL],
           Date().timeIntervalSince(cached.date) < staleAfter {
            return .loaded(cached.items)
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

        // Try the bookmark-resolved path first. In the sandboxed
        // (MAS) build this is the only path that works for any folder
        // outside our container; in the Dev ID build it succeeds the
        // first time the user added a folder and falls through to the
        // direct read on subsequent launches if the bookmark was
        // never persisted.
        let scope = BookmarkScope.folderPath(normalizedFolderURL.path)
        if BookmarkedURLStore.shared.hasBookmark(for: scope) {
            do {
                return try BookmarkedURLStore.shared.withResolvedURL(for: scope) { resolved in
                    let loaded = try FileManager.default.contentsOfDirectory(
                        at: resolved,
                        includingPropertiesForKeys: keys,
                        options: [.skipsHiddenFiles]
                    ).sorted(by: { Self.modDate($0) > Self.modDate($1) })
                    contentsCache[normalizedFolderURL] = (Date(), loaded)
                    return .loaded(loaded)
                }
            } catch {
                // Bookmark is broken or revoked. Fall through to
                // direct read which may still work in the Dev ID
                // build; sandboxed callers see `.unreadable` and the
                // tile shows a "needs access" affordance.
            }
        }

        guard FileManager.default.isReadableFile(atPath: normalizedFolderURL.path) else {
            return .unreadable
        }

        guard let loaded = try? FileManager.default.contentsOfDirectory(
            at: normalizedFolderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ).sorted(by: { Self.modDate($0) > Self.modDate($1) }) else {
            return .unreadable
        }

        contentsCache[normalizedFolderURL] = (Date(), loaded)
        return .loaded(loaded)
    }

    func invalidateCache() {
        contentsCache.removeAll()
    }

    /// Open an NSOpenPanel pre-selected to `folderURL` and, if the
    /// user confirms, persist a security-scoped bookmark under
    /// `.folderPath(path:)`. Returns `true` when a new bookmark was
    /// stored so callers can refresh their UI.
    ///
    /// Used by the folder popover's "needs access" affordance in the
    /// MAS build: the original tile URL points to something outside
    /// the sandbox container, and the only way to read it is for the
    /// user to re-confirm the same path through an Open panel.
    @MainActor
    @discardableResult
    func requestAccess(to folderURL: URL) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderURL
        panel.prompt = String(localized: "Grant Access")
        panel.message = String(
            localized: "Docky needs your permission to read this folder."
        )

        guard panel.runModal() == .OK, let picked = panel.url else {
            return false
        }

        let scope = BookmarkScope.folderPath(folderURL.standardizedFileURL.path)
        do {
            try BookmarkedURLStore.shared.store(url: picked, for: scope)
            invalidateCache(for: folderURL)
            changeToken &+= 1
            return true
        } catch {
            return false
        }
    }

    private func invalidateCache(for folderURL: URL) {
        contentsCache.removeValue(forKey: folderURL.standardizedFileURL)
    }

    private func handleWatcherEvent(for folderURL: URL) {
        invalidateCache(for: folderURL)
        changeToken &+= 1
    }

    private static func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

private struct FolderWatcher {
    var ownerIDs: Set<String>
    let source: DispatchSourceFileSystemObject
}

private struct FolderSortEntry {
    let url: URL
    let displayName: String
    let modificationDate: Date
    let creationDate: Date
    let addedDate: Date
    let kind: String
    let size: Int
    let isDirectory: Bool

    nonisolated init(url: URL) {
        let values = try? url.resourceValues(forKeys: [
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
