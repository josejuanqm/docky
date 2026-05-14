//
//  ThemeManager.swift
//  Docky
//
//  Owns installed `.dockytheme` bundles and the active selection.
//  Themes are installed bundles on disk under Application Support;
//  the user activates one at a time (WordPress-style install/activate
//  — installed themes persist regardless of which is active so the
//  user can cycle through them).
//
//  Activation never writes appearance values into `DockyPreferences`.
//  Instead, the manager exposes `activeManifest` / `activeBundleURL`
//  and the `effective<X>` accessors in `DockyPreferences` fall through
//  to those values when the user hasn't set an explicit override.
//  That keeps "try a theme, revert, restore my customizations" trivial
//  — your overrides are never overwritten.
//
//  Install location:
//
//      ~/Library/Application Support/Docky/Themes/<theme-id>/
//          theme.json
//          assets/...
//
//  Importing a `.dockytheme` zip (UI flow) belongs to a later commit.
//  For now installed themes are picked up by scanning the directory —
//  drop an unzipped bundle in there to test.
//

import Foundation
import Observation
import ZIPFoundation

@MainActor
@Observable final class ThemeManager {
    static let shared = ThemeManager()

    /// All themes currently installed under the themes directory,
    /// keyed by manifest `id`. Re-scanned on demand via
    /// `refreshInstalled()`; not a live filesystem watcher.
    private(set) var installedThemes: [String: InstalledTheme] = [:]

    /// Identifier of the active theme, or `nil` when no theme is
    /// applied. Persisted to UserDefaults so activation survives
    /// relaunch.
    private(set) var activeThemeID: String?

    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default

    private enum Keys {
        static let activeThemeID = "docky.activeThemeID"
    }

    private init() {
        self.defaults = .standard
        self.activeThemeID = defaults.string(forKey: Keys.activeThemeID)
        ensureThemesDirectoryExists()
        refreshInstalled()
    }

    /// Read-only directory inside the app bundle holding themes
    /// shipped with Docky. Populated by the "Copy Bundled Themes"
    /// build phase from `BundledThemes/` at the repo root. Returns
    /// `nil` when the directory doesn't exist (e.g. running from a
    /// debug build without bundled themes staged).
    private static var bundledThemesDirectoryURL: URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL.appending(path: "Themes", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: - Public surface

    /// On-disk location where installed theme bundles live.
    /// Created lazily; safe to expose to UI / shell.
    var themesDirectoryURL: URL {
        Self.themesDirectoryURL
    }

    /// Manifest of the active theme, if any. Resolved from the
    /// installed-themes cache; returns `nil` when the active id is
    /// stale or no theme is active.
    var activeManifest: ThemeManifest? {
        guard let activeThemeID else { return nil }
        return installedThemes[activeThemeID]?.manifest
    }

    /// Bundle directory of the active theme, used to resolve
    /// asset-relative paths in the manifest.
    var activeBundleURL: URL? {
        guard let activeThemeID else { return nil }
        return installedThemes[activeThemeID]?.bundleURL
    }

    /// Resolves a manifest-relative asset path (e.g. `assets/x.png`)
    /// against the active bundle. Returns `nil` if no theme is active
    /// or the file doesn't exist on disk.
    func activeAssetURL(_ relativePath: String?) -> URL? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        guard let activeBundleURL else { return nil }
        let url = activeBundleURL.appending(path: relativePath, directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Looks for a theme-supplied app icon at
    /// `<activeBundleURL>/assets/<bundleIdentifier>.<png|jpg|jpeg>`.
    /// Convention-based — no manifest declaration needed; drop a file
    /// named for the app's bundle id and it's picked up when the theme
    /// is active. Returns `nil` when no theme is active or no matching
    /// asset exists.
    func activeAppIconURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        guard !bundleIdentifier.isEmpty, let activeBundleURL else { return nil }
        let assetsDir = activeBundleURL.appending(path: "assets", directoryHint: .isDirectory)
        for ext in ["png", "jpg", "jpeg"] {
            let url = assetsDir.appending(
                path: "\(bundleIdentifier).\(ext)",
                directoryHint: .notDirectory
            )
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Bundle identifiers of every per-app icon the active theme
    /// ships in its `assets/` directory. Filenames whose stems
    /// contain a dot (the macOS reverse-DNS pattern) are treated as
    /// bundle ids; anything else is treated as a regular manifest
    /// asset and skipped here. Used by the export flow to decide
    /// which per-app icons to bundle into the new theme.
    func activeAppIconBundleIDs() -> [String] {
        guard let activeBundleURL else { return [] }
        let assetsDir = activeBundleURL.appending(path: "assets", directoryHint: .isDirectory)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: assetsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.compactMap { url in
            let ext = url.pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { return nil }
            let stem = url.deletingPathExtension().lastPathComponent
            guard stem.contains(".") else { return nil }
            return stem
        }
    }

    // MARK: - Mutation

    /// Activate an installed theme by id. No-op (logs) when the id
    /// isn't installed. Does not modify the user's preference values.
    func setActive(_ id: String) {
        guard installedThemes[id] != nil else { return }
        guard activeThemeID != id else { return }
        activeThemeID = id
        defaults.set(id, forKey: Keys.activeThemeID)
    }

    /// Clear the active theme. Appearance reads fall through to user
    /// overrides / built-in defaults.
    func clearActive() {
        guard activeThemeID != nil else { return }
        activeThemeID = nil
        defaults.removeObject(forKey: Keys.activeThemeID)
    }

    /// Re-scans the bundled + user themes directories and rebuilds
    /// `installedThemes`. Bundled themes load first so a user-supplied
    /// theme with the same id transparently overrides the built-in
    /// (last write wins in the merge step).
    func refreshInstalled() {
        var merged: [String: InstalledTheme] = [:]

        if let bundledURL = Self.bundledThemesDirectoryURL {
            for (id, theme) in Self.scanInstalledThemes(at: bundledURL, decoder: decoder, isBundled: true) {
                merged[id] = theme
            }
        }

        for (id, theme) in Self.scanInstalledThemes(at: themesDirectoryURL, decoder: decoder, isBundled: false) {
            merged[id] = theme
        }

        installedThemes = merged

        // If the active id no longer maps to an installed theme,
        // forget it so reads fall back to user/default values.
        if let id = activeThemeID, installedThemes[id] == nil {
            clearActive()
        }
    }

    /// Removes the user-installed copy of a theme. Built-in (bundled)
    /// themes are read-only and silently rejected — the caller's UI
    /// should never offer deletion for `isBundled` entries.
    ///
    /// If a bundled theme with the same id exists, deleting the user
    /// copy lets activation fall through to the built-in (the post-
    /// delete `refreshInstalled` re-merges and `activeThemeID` is
    /// preserved). When no bundled fallback exists, `refreshInstalled`
    /// clears the active selection itself.
    func deleteTheme(id: String) throws {
        guard let installed = installedThemes[id], !installed.isBundled else { return }
        try fileManager.removeItem(at: installed.bundleURL)
        refreshInstalled()
    }

    /// Imports a `.dockytheme` (zip) bundle from disk. The zip is
    /// extracted to a temp directory via `/usr/bin/ditto -xk`, the
    /// manifest is parsed and validated, then the bundle is moved
    /// atomically into `Themes/<manifest.id>/`.
    ///
    /// An existing install with the same id is replaced (the new
    /// content wins). The active theme is cleared before replacement
    /// so observers don't briefly read from the swapped-out directory,
    /// then restored if it pointed at the same id.
    ///
    /// Returns the parsed manifest on success.
    @discardableResult
    func importTheme(from zipURL: URL) throws -> ThemeManifest {
        let tempRoot = fileManager.temporaryDirectory
            .appending(path: "docky-theme-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        try Self.extractZip(at: zipURL, into: tempRoot)

        // Locate the bundle root. Two valid layouts:
        //  (a) zip extracted directly to manifest+assets at tempRoot
        //  (b) zip extracted to a single subfolder containing them
        let bundleRoot = try Self.locateBundleRoot(in: tempRoot)

        let manifestURL = bundleRoot.appending(path: "theme.json", directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw ThemeImportError.missingManifest
        }
        let manifest: ThemeManifest
        do {
            manifest = try decoder.decode(ThemeManifest.self, from: data)
        } catch {
            throw ThemeImportError.invalidManifest(error)
        }

        guard Self.isValidThemeID(manifest.id) else {
            throw ThemeImportError.invalidID(manifest.id)
        }

        let destination = themesDirectoryURL
            .appending(path: manifest.id, directoryHint: .isDirectory)

        let wasActive = activeThemeID == manifest.id
        if wasActive {
            // Clear during the swap so any reactive consumer doesn't
            // briefly resolve assets against a half-moved directory.
            clearActive()
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: bundleRoot, to: destination)

        refreshInstalled()

        if wasActive {
            setActive(manifest.id)
        }

        return manifest
    }

    private static func extractZip(at zipURL: URL, into destination: URL) throws {
        // ZIPFoundation handles macOS-flavored zips (including the
        // sequestered resource forks that `ditto` produces). Works
        // in the sandbox.
        do {
            try FileManager.default.unzipItem(at: zipURL, to: destination)
        } catch {
            throw ThemeImportError.extractionFailed(status: -1, stderr: error.localizedDescription)
        }
    }

    private static func locateBundleRoot(in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        let manifestAtRoot = directory.appending(path: "theme.json", directoryHint: .notDirectory)
        if fileManager.fileExists(atPath: manifestAtRoot.path) {
            return directory
        }

        let entries = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        // Some zip tools (and macOS Finder's "Compress") wrap content
        // in a single top-level folder. Walk into it transparently.
        let directories = entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        if directories.count == 1 {
            let nested = directories[0].appending(path: "theme.json", directoryHint: .notDirectory)
            if fileManager.fileExists(atPath: nested.path) {
                return directories[0]
            }
        }

        throw ThemeImportError.missingManifest
    }

    /// Validates that a manifest id is safe to use as a folder name.
    /// Reverse-DNS and lower-case-with-dashes are both accepted.
    static func isValidThemeID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 128 else { return false }
        guard !id.hasPrefix(".") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Lowercases the input, replaces whitespace with dashes, and
    /// strips characters that wouldn't pass `isValidThemeID`. Returns
    /// `nil` when no valid characters remain.
    static func slugify(_ raw: String) -> String? {
        let lowered = raw.lowercased()
        var result = ""
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                result.append(Character(scalar))
                lastWasDash = false
            } else if scalar == "_" || scalar == "." || scalar == "-" {
                result.append(Character(scalar))
                lastWasDash = scalar == "-"
            } else if scalar == " " || scalar == "\t" {
                if !lastWasDash {
                    result.append("-")
                    lastWasDash = true
                }
            }
            // Any other character is dropped.
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Export

    /// Exports the user's current effective appearance to a
    /// `.dockytheme` zip at `destinationURL`. The on-disk archive
    /// contains a `theme.json` manifest plus every referenced image
    /// asset, with manifest paths rewritten to relative `assets/...`
    /// references so the bundle is portable.
    ///
    /// `name` is shown in the Themes pane and used to derive the
    /// manifest id (slugified). Asset files are deduplicated by
    /// source URL so a divider image that resolves to the same file
    /// for left/right/center is copied only once.
    @discardableResult
    func exportCurrentAppearance(name: String, to destinationURL: URL) throws -> URL {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw ThemeExportError.invalidName(name) }
        guard let id = Self.slugify(trimmedName), Self.isValidThemeID(id) else {
            throw ThemeExportError.invalidName(name)
        }

        let staging = fileManager.temporaryDirectory
            .appending(path: "docky-theme-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let bundleDir = staging.appending(path: id, directoryHint: .isDirectory)
        let assetsDir = bundleDir.appending(path: "assets", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let copier = AssetCopier(assetsDir: assetsDir)
        let manifest = Self.buildExportManifest(id: id, name: trimmedName, copier: copier)
        Self.copyPerAppIcons(into: copier)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(
            to: bundleDir.appending(path: "theme.json", directoryHint: .notDirectory),
            options: .atomic
        )

        let stagedZip = staging.appending(path: "\(id).dockytheme", directoryHint: .notDirectory)
        try Self.createZip(of: bundleDir, at: stagedZip)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: stagedZip, to: destinationURL)
        return destinationURL
    }

    private static func buildExportManifest(
        id: String,
        name: String,
        copier: AssetCopier
    ) -> ThemeManifest {
        let prefs = DockyPreferences.shared

        let backgroundAsset = copier.copyIfPresent(prefs.effectiveWindowBackgroundImageURL)
        let indicatorAsset = copier.copyIfPresent(prefs.effectiveActiveIndicatorImageURL)
        let centerDividerAsset = copier.copyIfPresent(prefs.effectiveDividerImageURL)
        let leftDividerAsset = copier.copyIfPresent(prefs.effectiveLeftDividerImageURL)
        let rightDividerAsset = copier.copyIfPresent(prefs.effectiveRightDividerImageURL)

        let borderColor = prefs.explicitWindowBorderColor
        let window = ThemeWindow(
            clipShape: prefs.effectiveWindowClipShape.rawValue,
            cornerRadius: prefs.effectiveWindowCornerRadius,
            backgroundImage: backgroundAsset,
            backgroundImageMode: prefs.effectiveWindowBackgroundImageMode.rawValue,
            tintColor: prefs.explicitWindowTintColor,
            tintOpacity: prefs.effectiveWindowTintOpacity,
            borderColor: borderColor,
            // Only ship the width when a color is set — otherwise the
            // recipient would see "no border" + a stale width, which
            // serializes noise without affecting render.
            borderWidth: borderColor == nil ? nil : prefs.effectiveWindowBorderWidth
        )

        let divider = ThemeDivider(
            left: leftDividerAsset,
            right: rightDividerAsset,
            center: centerDividerAsset,
            mirrorLeftOnRight: prefs.effectiveMirrorsLeftDividerOnRight,
            paddingFraction: prefs.effectiveDividerPaddingFraction,
            offset: prefs.effectiveDividerOffset,
            imageScale: prefs.effectiveDividerImageScale,
            opacity: prefs.effectiveDividerOpacity,
            color: prefs.explicitDividerColor
        )

        let indicators = ThemeIndicators(
            shape: prefs.effectiveActiveIndicatorShape.rawValue,
            image: indicatorAsset,
            color: prefs.explicitActiveIndicatorColor,
            offset: prefs.effectiveActiveIndicatorOffset,
            scale: prefs.effectiveActiveIndicatorScale,
            divider: divider
        )

        let shadowColor = prefs.explicitIconShadowColor
        let iconShadow: ThemeShadow? = shadowColor.map { color in
            ThemeShadow(
                color: color,
                radius: prefs.effectiveIconShadowRadius,
                opacity: prefs.effectiveIconShadowOpacity
            )
        }

        let appearance = ThemeAppearance(
            disablesGlassLook: prefs.effectiveDisablesGlassLook,
            tile: ThemeTile(
                clipShape: prefs.effectiveTileClipShape.rawValue,
                verticalPadding: prefs.effectiveTileVerticalPadding,
                spacing: prefs.effectiveTileSpacing
            ),
            window: window,
            indicators: indicators,
            iconShadow: iconShadow
        )

        return ThemeManifest(
            schemaVersion: 1,
            id: id,
            name: name,
            author: NSFullUserName(),
            version: "1.0.0",
            description: nil,
            appearance: appearance
        )
    }

    /// Bundles every per-app icon — user-set overrides ∪ icons the
    /// active theme ships — into the export's `assets/` directory as
    /// `<bundle-id>.<ext>`. Convention-named, so the recipient picks
    /// them up automatically when the exported theme is activated.
    private static func copyPerAppIcons(into copier: AssetCopier) {
        let prefs = DockyPreferences.shared
        var bundleIdentifiers = Set<String>()
        bundleIdentifiers.formUnion(prefs.appIconOverrides.map(\.bundleIdentifier))
        bundleIdentifiers.formUnion(ThemeManager.shared.activeAppIconBundleIDs())

        for bundleIdentifier in bundleIdentifiers {
            guard let sourceURL = prefs.effectiveAppIconOverrideURL(
                forBundleIdentifier: bundleIdentifier
            ) else { continue }

            let sourceExt = sourceURL.pathExtension.lowercased()
            let preservedExt = ["png", "jpg", "jpeg"].contains(sourceExt) ? sourceExt : "png"
            copier.copyAt(sourceURL, named: "\(bundleIdentifier).\(preservedExt)")
        }
    }

    private static func createZip(of sourceDirectory: URL, at destination: URL) throws {
        do {
            try FileManager.default.zipItem(
                at: sourceDirectory,
                to: destination,
                shouldKeepParent: true,
                compressionMethod: .deflate
            )
        } catch {
            throw ThemeExportError.archiveFailed(status: -1, stderr: error.localizedDescription)
        }
    }

    // MARK: - Internals

    private func ensureThemesDirectoryExists() {
        let url = themesDirectoryURL
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static var themesDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return base
            .appending(path: "Docky", directoryHint: .isDirectory)
            .appending(path: "Themes", directoryHint: .isDirectory)
    }

    private static func scanInstalledThemes(
        at directory: URL,
        decoder: JSONDecoder,
        isBundled: Bool
    ) -> [String: InstalledTheme] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var result: [String: InstalledTheme] = [:]
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            let manifestURL = entry.appending(path: "theme.json", directoryHint: .notDirectory)
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(ThemeManifest.self, from: data) else {
                continue
            }

            // Trust the manifest id over the folder name so a renamed
            // folder still resolves consistently. Collisions: last one
            // wins; harmless because the user can rename and re-scan.
            result[manifest.id] = InstalledTheme(
                manifest: manifest,
                bundleURL: entry,
                isBundled: isBundled
            )
        }
        return result
    }
}

/// One installed theme on disk: parsed manifest plus the bundle
/// directory that asset paths resolve against. `isBundled == true`
/// for themes shipped inside the app bundle (read-only); the UI
/// hides destructive actions for those entries.
struct InstalledTheme: Equatable {
    let manifest: ThemeManifest
    let bundleURL: URL
    let isBundled: Bool

    /// Optional `cover_image.png` (or `.jpg`/`.jpeg`) at the bundle
    /// root. Used by the Themes settings pane as a rich preview.
    /// Re-checked at access time so authors iterating on the file
    /// don't need to relaunch or refresh.
    var coverImageURL: URL? {
        let fileManager = FileManager.default
        for name in ["cover_image.png", "cover_image.jpg", "cover_image.jpeg"] {
            let url = bundleURL.appending(path: name, directoryHint: .notDirectory)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

/// Stages copies of referenced image assets into an export bundle's
/// `assets/` directory, deduping by source URL so an image referenced
/// from multiple appearance slots (e.g. a divider shared by left and
/// right) is copied only once. Returns the path relative to the
/// bundle root (`"assets/<name>"`) for use in the exported manifest.
private final class AssetCopier {
    private let assetsDir: URL
    private let fileManager = FileManager.default
    private var copiedRelativePaths: [URL: String] = [:]
    private var usedNames: Set<String> = []

    init(assetsDir: URL) {
        self.assetsDir = assetsDir
    }

    func copyIfPresent(_ sourceURL: URL?) -> String? {
        guard let sourceURL else { return nil }
        if let existing = copiedRelativePaths[sourceURL] { return existing }

        let destination = uniqueDestination(for: sourceURL)
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } catch {
            return nil
        }
        let relative = "assets/\(destination.lastPathComponent)"
        copiedRelativePaths[sourceURL] = relative
        usedNames.insert(destination.lastPathComponent)
        return relative
    }

    /// Copies an asset to a fixed destination filename (used for
    /// convention-named files like `<bundle-id>.<ext>` where the
    /// recipient discovers the file by name rather than via the
    /// manifest). No-op if the destination already exists.
    func copyAt(_ sourceURL: URL, named fixedName: String) {
        guard !usedNames.contains(fixedName) else { return }
        let destination = assetsDir.appending(path: fixedName, directoryHint: .notDirectory)
        guard !fileManager.fileExists(atPath: destination.path) else {
            usedNames.insert(fixedName)
            return
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } catch {
            return
        }
        usedNames.insert(fixedName)
        copiedRelativePaths[sourceURL] = "assets/\(fixedName)"
    }

    private func uniqueDestination(for sourceURL: URL) -> URL {
        let originalName = sourceURL.lastPathComponent
        if !usedNames.contains(originalName) {
            return assetsDir.appending(path: originalName, directoryHint: .notDirectory)
        }
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var counter = 1
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            if !usedNames.contains(candidate) {
                return assetsDir.appending(path: candidate, directoryHint: .notDirectory)
            }
            counter += 1
        }
    }
}

enum ThemeExportError: LocalizedError {
    case invalidName(String)
    case archiveFailed(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return "The name \"\(name)\" can't be used as a theme identifier."
        case .archiveFailed(let status, let stderr):
            let detail = stderr.isEmpty ? "" : " (\(stderr.trimmingCharacters(in: .whitespacesAndNewlines)))"
            return "Failed to write theme archive (exit \(status))\(detail)."
        }
    }
}

enum ThemeImportError: LocalizedError {
    case extractionFailed(status: Int32, stderr: String)
    case missingManifest
    case invalidManifest(Error)
    case invalidID(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let status, let stderr):
            let detail = stderr.isEmpty ? "" : " (\(stderr.trimmingCharacters(in: .whitespacesAndNewlines)))"
            return "Failed to extract theme archive (exit \(status))\(detail)."
        case .missingManifest:
            return "The theme archive does not contain a theme.json manifest."
        case .invalidManifest(let underlying):
            return "The theme manifest is invalid: \(underlying.localizedDescription)"
        case .invalidID(let id):
            return "The theme manifest id \"\(id)\" is not a valid identifier."
        }
    }
}
