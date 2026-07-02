//
//  PhotoFrameService.swift
//  Docky
//
//  Backing store for the Photo Frame widget. Owns the user's chosen
//  photos as an ordered list of file bookmarks (persisted globally in
//  DockyPreferences), resolves them to URLs, decodes them lazily, and
//  publishes the frame the widget should currently show. When more than
//  one photo is configured it drives a slideshow that cross-fades
//  between frames on a timer.
//
//  Docky is not sandboxed (ENABLE_APP_SANDBOX = NO), so plain file
//  bookmarks resolve across launches with full read access — no
//  security-scoped start/stop dance is required. Photos are referenced
//  in place rather than copied, so moving or deleting a source file
//  removes it from the slideshow on the next resolve.
//

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PhotoFrameService: ObservableObject {
    static let shared = PhotoFrameService()

    /// The frame currently shown in the widget. `nil` while no photos are
    /// configured (widget shows its empty-state CTA) or before the first
    /// image finishes decoding.
    @Published private(set) var currentImage: NSImage?

    /// Number of photos in the slideshow. The widget branches on this to
    /// choose between the CTA (0) and the photo view (>0); the context
    /// menu uses it to decide whether "Clear Photos" is offered.
    @Published private(set) var photoCount: Int = 0

    /// How long each photo stays on screen before the slideshow advances.
    private let slideshowInterval: TimeInterval = 8

    /// Upper bound on decoded frames kept in memory. Slideshows are
    /// usually a handful of photos; the cap keeps a pathological
    /// hundreds-of-photos selection from pinning every decode in memory.
    private let maxCachedImages = 16

    private let preferences = DockyPreferences.shared
    private var urls: [URL] = []
    private var imageCache: [Int: NSImage] = [:]
    private var currentIndex = 0
    private var slideshowTask: Task<Void, Never>?

    var hasPhotos: Bool { photoCount > 0 }

    init() {
        reload()
    }

    // MARK: - Configuration

    /// Prompts the user to pick one or more image files and makes them the
    /// slideshow. Replaces the existing selection so "Choose Photos…"
    /// reads as "these are my photos now".
    func choosePhotos() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Photos")
        panel.prompt = String(localized: "Choose")
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]

        // Docky runs as an accessory app; bring it forward so the panel
        // opens in front and can take key focus.
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK else { return }

        let bookmarks = panel.urls.compactMap { url in
            try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        guard !bookmarks.isEmpty else { return }

        preferences.photoFrameBookmarks = bookmarks
        reload()
    }

    /// Empties the slideshow, returning the widget to its CTA state.
    func clearPhotos() {
        guard !preferences.photoFrameBookmarks.isEmpty else { return }
        preferences.photoFrameBookmarks = []
        reload()
    }

    // MARK: - Slideshow

    /// Advances to the next photo immediately (also invoked by the timer).
    func advance() {
        guard urls.count > 1 else { return }
        let next = (currentIndex + 1) % urls.count
        showImage(at: next)
        preload(at: (next + 1) % urls.count)
    }

    /// Rebuilds the URL list from persisted bookmarks and restarts the
    /// slideshow. Safe to call repeatedly; the widget triggers it on
    /// appear so a fresh launch resolves bookmarks lazily.
    func reload() {
        let (resolvedURLs, refreshedBookmarks) = resolveBookmarks()

        // Persist back if any bookmark went stale or a dead reference was
        // dropped, so we don't re-resolve the same broken data next time.
        if refreshedBookmarks != preferences.photoFrameBookmarks {
            preferences.photoFrameBookmarks = refreshedBookmarks
        }

        urls = resolvedURLs
        imageCache.removeAll()
        currentIndex = 0
        photoCount = urls.count

        if urls.isEmpty {
            currentImage = nil
            stopTimer()
        } else {
            showImage(at: 0)
            if urls.count > 1 {
                preload(at: 1)
            }
            startTimerIfNeeded()
        }
    }

    // MARK: - Bookmark resolution

    private func resolveBookmarks() -> (urls: [URL], bookmarks: [Data]) {
        var urls: [URL] = []
        var bookmarks: [Data] = []

        for data in preferences.photoFrameBookmarks {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), FileManager.default.fileExists(atPath: url.path) else {
                // Unresolvable or missing file: drop it from the set.
                continue
            }

            if isStale, let fresh = try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                bookmarks.append(fresh)
            } else {
                bookmarks.append(data)
            }
            urls.append(url)
        }

        return (urls, bookmarks)
    }

    // MARK: - Image loading

    private func showImage(at index: Int) {
        guard urls.indices.contains(index) else { return }
        currentIndex = index

        if let cached = imageCache[index] {
            currentImage = cached
            return
        }

        let url = urls[index]
        Task { [weak self] in
            let data = await Self.readData(at: url)
            guard let self, self.currentIndex == index else { return }
            let image = data.flatMap(NSImage.init(data:))
            if let image { self.store(image, at: index) }
            self.currentImage = image
        }
    }

    private func preload(at index: Int) {
        guard urls.indices.contains(index), imageCache[index] == nil else { return }
        let url = urls[index]
        Task { [weak self] in
            let data = await Self.readData(at: url)
            guard let self, let image = data.flatMap(NSImage.init(data:)) else { return }
            self.store(image, at: index)
        }
    }

    private func store(_ image: NSImage, at index: Int) {
        if imageCache.count >= maxCachedImages {
            // Keep only the frame on screen; a slideshow revisits the
            // dropped frames and re-decodes them when it comes back around.
            imageCache = imageCache.filter { $0.key == currentIndex }
        }
        imageCache[index] = image
    }

    private static func readData(at url: URL) async -> Data? {
        await Task.detached(priority: .utility) {
            try? Data(contentsOf: url)
        }.value
    }

    // MARK: - Timer

    private func startTimerIfNeeded() {
        stopTimer()
        guard urls.count > 1 else { return }
        let interval = slideshowInterval
        // The class is @MainActor, so this Task inherits main-actor
        // isolation and `advance()` runs on the main thread without a hop.
        slideshowTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                self.advance()
            }
        }
    }

    private func stopTimer() {
        slideshowTask?.cancel()
        slideshowTask = nil
    }
}
