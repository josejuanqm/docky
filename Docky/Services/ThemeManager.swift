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

    /// Re-scans the themes directory and rebuilds `installedThemes`.
    /// Cheap enough to call on launch and after user-initiated
    /// install/uninstall actions.
    func refreshInstalled() {
        installedThemes = Self.scanInstalledThemes(at: themesDirectoryURL, decoder: decoder)

        // If the active id no longer maps to an installed theme,
        // forget it so reads fall back to user/default values.
        if let id = activeThemeID, installedThemes[id] == nil {
            clearActive()
        }
    }

    /// Removes an installed theme. If it is the active theme, the
    /// active selection is cleared first so reads don't briefly point
    /// at a missing bundle.
    func deleteTheme(id: String) throws {
        guard let installed = installedThemes[id] else { return }
        if activeThemeID == id {
            clearActive()
        }
        try fileManager.removeItem(at: installed.bundleURL)
        installedThemes.removeValue(forKey: id)
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, destination.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw ThemeImportError.extractionFailed(status: process.terminationStatus, stderr: stderr)
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
        decoder: JSONDecoder
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
            result[manifest.id] = InstalledTheme(manifest: manifest, bundleURL: entry)
        }
        return result
    }
}

/// One installed theme on disk: parsed manifest plus the bundle
/// directory that asset paths resolve against.
struct InstalledTheme: Equatable {
    let manifest: ThemeManifest
    let bundleURL: URL
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
