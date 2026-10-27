//
//  IconCacheService.swift
//  Docky
//
//  In-memory cache for icons surfaced in tiles. Wraps NSCache so eviction
//  under memory pressure is handled by the OS. `NSWorkspace.icon(forFile:)`
//  itself is fast but SwiftUI re-reads the icon every view update — caching
//  avoids repeated LaunchServices hops and redundant NSImage wrapping.
//

import AppKit
import UniformTypeIdentifiers

final class IconCacheService {
    static let shared = IconCacheService()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    /// Nominal point size stamped onto every icon fetched from LaunchServices.
    /// `NSWorkspace.icon(forFile:)` returns a multi-representation image whose
    /// logical `size` is only 32x32, so `Image(nsImage:).resizable()` rasterizes
    /// at that nominal size and then upscales it into the tile — which is what
    /// made icons look blurry next to the native Dock (the native Dock draws
    /// straight from the 512px representation). Stamping a large nominal size
    /// makes SwiftUI select a high-resolution representation and downsample it
    /// instead. The representations stay lazy, so this does not eagerly allocate
    /// a bitmap per icon.
    ///
    /// 256 is the smallest standard `.icns` representation that still covers the
    /// largest size a tile is ever drawn at (a magnified tile tops out around
    /// ~192px), so every dock surface downsamples rather than upscales. Going
    /// higher (512/1024) would decode a source bitmap 4x larger for no visible
    /// gain in the dock and extra per-frame resampling work during magnification.
    private static let normalizedIconExtent: CGFloat = 256

    /// Covers a folder preview icon at the largest magnified size, about 110 pt.
    private static let flattenedIconExtent: CGFloat = 128

    private init() {}

    /// Fetches an icon from LaunchServices and normalizes its nominal size so
    /// downstream `resizable()` rendering downsamples a high-resolution
    /// representation rather than upscaling the default 32pt one. See
    /// `normalizedIconExtent`.
    private static func workspaceIcon(forFile path: String) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: normalizedIconExtent, height: normalizedIconExtent)
        return image
    }

    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        let key = "bundle:\(bundleIdentifier)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = loadIcon(forBundleIdentifier: bundleIdentifier)
        cache.setObject(image, forKey: key)
        return image
    }

    /// With the dark icon style on macOS 26, folder previews sometimes drew
    /// the light variant of the LaunchServices icon while magnification
    /// resized them. A bitmap has only one variant, so it can not flip.
    func flattenedIcon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        let key = "flat:\(bundleIdentifier)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let source = icon(forBundleIdentifier: bundleIdentifier)
        var proposedRect = NSRect(x: 0, y: 0, width: Self.flattenedIconExtent, height: Self.flattenedIconExtent)
        guard let cgImage = source.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return source
        }
        let image = NSImage(cgImage: cgImage, size: proposedRect.size)
        cache.setObject(image, forKey: key)
        return image
    }

    /// For views outside the dock tiles: the override when one is set,
    /// otherwise the LaunchServices icon. Uses the padding the user set for
    /// the override in App Icons, matching the dock tile. Without one, adds
    /// the margin of a macOS app icon (100 px of 1024) so an edge-to-edge
    /// override sits at the same size as the system icons around it.
    func displayedIcon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        let preferences = DockyPreferences.shared
        guard let url = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: bundleIdentifier),
              let override = image(forImageFileURL: url) else {
            return icon(forBundleIdentifier: bundleIdentifier)
        }
        let userPadding = preferences.appIconOverridePadding(forBundleIdentifier: bundleIdentifier)
        let paddingFraction = userPadding > 0 ? userPadding : 100 / 1024
        let key = "displayed:\(url.path):\(paddingFraction)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let extent = Self.normalizedIconExtent
        let inset = extent * paddingFraction
        let image = NSImage(size: NSSize(width: extent, height: extent), flipped: false) { rect in
            override.draw(in: rect.insetBy(dx: inset, dy: inset))
            return true
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Synchronously returns the cached icon if present, without
    /// triggering a LaunchServices fetch. Use this to render hot
    /// icons inline and fall back to `loadIconAsync(forBundleIdentifier:)`
    /// for cold entries so the main thread never blocks on disk I/O.
    func cachedIcon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        let key = "bundle:\(bundleIdentifier)" as NSString
        return cache.object(forKey: key)
    }

    /// Loads the icon on a background priority and stores the result
    /// in the cache. NSWorkspace.icon is thread-safe and NSCache is
    /// thread-safe, so the load can run anywhere.
    func loadIconAsync(forBundleIdentifier bundleIdentifier: String) async -> NSImage {
        let key = "bundle:\(bundleIdentifier)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        return await Task.detached(priority: .userInitiated) { [cache] in
            let image: NSImage
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                image = Self.workspaceIcon(forFile: url.path)
            } else {
                image = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
            }
            cache.setObject(image, forKey: key)
            return image
        }.value
    }

    func icon(forFileURL url: URL) -> NSImage {
        let key = "path:\(url.path)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = Self.workspaceIcon(forFile: url.path)
        cache.setObject(image, forKey: key)
        return image
    }

    func preloadIcon(forBundleIdentifier bundleIdentifier: String, fileURL: URL) {
        let key = "bundle:\(bundleIdentifier)" as NSString
        cache.setObject(Self.workspaceIcon(forFile: fileURL.path), forKey: key)
    }

    func previewIcon(forFileURL url: URL) -> NSImage {
        if isImageFileURL(url), let image = image(forImageFileURL: url) {
            return image
        }

        return icon(forFileURL: url)
    }

    func image(forImageFileURL url: URL) -> NSImage? {
        let key = "image:\(url.path)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Thumbnail extent in pixels for the folder popover grid, whose tiles
    /// are 112pt (224px on Retina).
    static let gridThumbnailPixelExtent = 256

    /// Thumbnail extent in pixels for dock tile previews and the fan. A
    /// magnified tile tops out around ~192pt, which is 384px on Retina, so
    /// 512 keeps those surfaces downsampling rather than upscaling.
    static let tileThumbnailPixelExtent = 512

    /// Synchronously returns the cached preview thumbnail if present, without
    /// touching the disk. Pair with `loadPreviewThumbnailAsync(forFileURL:maxPixelSize:)`.
    func cachedPreviewThumbnail(forFileURL url: URL, maxPixelSize: Int) -> NSImage? {
        cache.object(forKey: Self.previewThumbnailKey(for: url, maxPixelSize: maxPixelSize))
    }

    /// Decodes a downsampled thumbnail for image files off the main thread
    /// and stores it in the cache. Returns nil when the file is not an image
    /// or cannot be decoded, so callers keep showing the file icon.
    /// `image(forImageFileURL:)` keeps the full-size bitmap, which is decoded
    /// on first draw, so a grid of photos would block the main thread.
    func loadPreviewThumbnailAsync(forFileURL url: URL, maxPixelSize: Int) async -> NSImage? {
        let key = Self.previewThumbnailKey(for: url, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key) { return cached }
        return await Task.detached(priority: .userInitiated) { [cache] in
            guard Self.isImageFile(url),
                  let image = Self.previewThumbnail(forImageFileURL: url, maxPixelSize: maxPixelSize) else {
                return nil as NSImage?
            }
            cache.setObject(image, forKey: key)
            return image
        }.value
    }

    /// Warms the thumbnail cache in the background so a surface that is
    /// about to show these files (e.g. the fan opening from a folder tile)
    /// can render them on its first frame.
    func preloadPreviewThumbnails(forFileURLs urls: [URL], maxPixelSize: Int) {
        let uncached = urls.filter { cachedPreviewThumbnail(forFileURL: $0, maxPixelSize: maxPixelSize) == nil }
        guard !uncached.isEmpty else { return }
        Task.detached(priority: .utility) { [cache] in
            for url in uncached {
                guard Self.isImageFile(url),
                      let image = Self.previewThumbnail(forImageFileURL: url, maxPixelSize: maxPixelSize) else {
                    continue
                }
                cache.setObject(image, forKey: Self.previewThumbnailKey(for: url, maxPixelSize: maxPixelSize))
            }
        }
    }

    nonisolated private static func previewThumbnailKey(for url: URL, maxPixelSize: Int) -> NSString {
        "thumbnail:\(maxPixelSize):\(url.path)" as NSString
    }

    nonisolated private static func previewThumbnail(forImageFileURL url: URL, maxPixelSize: Int) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        if let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }

        // Formats ImageIO cannot thumbnail (e.g. vector images) still load
        // through NSImage, just not on the main thread.
        return NSImage(contentsOf: url)
    }

    func invalidate() {
        cache.removeAllObjects()
    }

    private func loadIcon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return Self.workspaceIcon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
    }

    private func isImageFileURL(_ url: URL) -> Bool {
        Self.isImageFile(url)
    }

    nonisolated private static func isImageFile(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        guard values?.isDirectory != true else {
            return false
        }

        if let contentType = values?.contentType {
            return contentType.conforms(to: .image)
        }

        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }
}
