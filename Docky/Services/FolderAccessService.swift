//
//  FolderAccessService.swift
//  Docky
//
//  Reads folder contents for preview tiles. Relies on the .userFolders
//  permission granted via Full Disk Access. Silent no-op when access isn't
//  granted.
//

import Foundation

enum FolderContentsSnapshot: Equatable {
    case loaded([URL])
    case unreadable
}

final class FolderAccessService {
    static let shared = FolderAccessService()

    private let staleAfter: TimeInterval = 15
    private var contentsCache: [URL: (date: Date, items: [URL])] = [:]

    private init() {}

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
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

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

    private func cachedSnapshot(of folderURL: URL) -> FolderContentsSnapshot {
        if let cached = contentsCache[folderURL],
           Date().timeIntervalSince(cached.date) < staleAfter {
            return .loaded(cached.items)
        }

        guard FileManager.default.isReadableFile(atPath: folderURL.path) else {
            return .unreadable
        }

        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let loaded = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ).sorted(by: { Self.modDate($0) > Self.modDate($1) }) else {
            return .unreadable
        }

        contentsCache[folderURL] = (Date(), loaded)
        return .loaded(loaded)
    }

    func invalidateCache() {
        contentsCache.removeAll()
    }

    private static func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

private struct FolderSortEntry {
    let url: URL
    let displayName: String
    let modificationDate: Date
    let isDirectory: Bool

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [.localizedNameKey, .contentModificationDateKey, .isDirectoryKey])
        self.url = url
        self.displayName = values?.localizedName ?? url.lastPathComponent
        self.modificationDate = values?.contentModificationDate ?? .distantPast
        self.isDirectory = values?.isDirectory == true
    }
}
