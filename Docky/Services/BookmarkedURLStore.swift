//
//  BookmarkedURLStore.swift
//  Docky
//
//  Persists security-scoped bookmarks for user-selected URLs
//  (folder tiles, trash, pinned apps that need read access for
//  thumbnails). Stored in `UserDefaults` under
//  `docky.bookmark.<scope>`. Resolution is on-demand because
//  bookmarks expire / break when the target moves or the user
//  revokes access.
//
//  Usage pattern:
//
//      // After NSOpenPanel returns a URL the user picked:
//      try BookmarkedURLStore.shared.store(url: pickedURL,
//                                          for: .folderTile(id: tileID))
//
//      // Later, anywhere that needs access:
//      try BookmarkedURLStore.shared.withResolvedURL(for: .folderTile(id: tileID)) { url in
//          // Inside the closure we have security-scoped access.
//          let contents = try FileManager.default.contentsOfDirectory(at: url, ...)
//      }
//
//  The withResolved closure pairs `startAccessingSecurityScopedResource`
//  + `stopAccessingSecurityScopedResource` so callers can't forget
//  the second call (the #1 cause of bookmark exhaustion in
//  sandboxed apps).
//

import Foundation

enum BookmarkScope: Hashable {
    /// Bookmark keyed by a folder's filesystem path. Used by
    /// `FolderAccessService` so that any FolderTile or popover
    /// reading that path can share the same bookmark.
    case folderPath(_ path: String)
    case trash

    fileprivate var storageKey: String {
        switch self {
        case .folderPath(let path):
            // Path may contain characters that are awkward in a
            // UserDefaults key but UserDefaults itself is fine with
            // arbitrary strings, no escaping needed.
            return "docky.bookmark.folder.\(path)"
        case .trash:
            return "docky.bookmark.trash"
        }
    }
}

enum BookmarkError: Error {
    case noBookmark
    case staleBookmark
    case accessDenied
}

@MainActor
final class BookmarkedURLStore {
    static let shared = BookmarkedURLStore()

    private let defaults = UserDefaults.standard
    private init() {}

    /// Stores a security-scoped bookmark for the given URL. Replaces
    /// any existing bookmark for the same scope.
    func store(url: URL, for scope: BookmarkScope) throws {
        // `withSecurityScope` is the option that survives across
        // launches inside an `app-scope` bookmark entitlement. Apps
        // without that entitlement get a one-shot bookmark that
        // dies at relaunch, which is fine for the Dev ID build.
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: scope.storageKey)
    }

    func hasBookmark(for scope: BookmarkScope) -> Bool {
        defaults.data(forKey: scope.storageKey) != nil
    }

    func clear(_ scope: BookmarkScope) {
        defaults.removeObject(forKey: scope.storageKey)
    }

    /// Resolves the bookmark, calls `startAccessingSecurityScopedResource`,
    /// invokes `body` with the URL, then guarantees the matching stop.
    /// If the bookmark is stale, re-stores it (Apple's recommended
    /// recovery) and continues with the resolved URL.
    @discardableResult
    func withResolvedURL<T>(
        for scope: BookmarkScope,
        body: (URL) throws -> T
    ) throws -> T {
        guard let data = defaults.data(forKey: scope.storageKey) else {
            throw BookmarkError.noBookmark
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            // Re-create the bookmark so the next resolve doesn't
            // pay the staleness cost. Best-effort: a failure here
            // just means we'll re-bookmark on the next call.
            try? store(url: url, for: scope)
        }

        guard url.startAccessingSecurityScopedResource() else {
            throw BookmarkError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body(url)
    }
}
