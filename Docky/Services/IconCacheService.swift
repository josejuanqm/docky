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
