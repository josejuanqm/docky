//
//  Theme.swift
//  Docky
//
//  Codable representation of a `.dockytheme` bundle's `theme.json`
//  manifest. Every appearance field is optional so that partial
//  themes overlay cleanly: a field that is `nil` falls through to
//  the user's own preference (or the app default), per the layered
//  read path in `DockyPreferences`.
//
//  Image fields are *relative* paths into the bundle's `assets/`
//  directory. Absolute resolution happens at read time against
//  `ThemeManager.activeBundleURL` so a theme stays portable when
//  copied between machines.
//
//  Optional bundle-root files (not referenced by the manifest):
//    - `cover_image.png` (or `.jpg`/`.jpeg`): displayed by the Themes
//      settings pane as a rich preview. Convention over manifest
//      configuration — drop a file in with that name and it's picked
//      up automatically by `InstalledTheme.coverImageURL`.
//
//  Optional files inside `assets/` (also convention-only):
//    - `<bundle-id>.png` (or `.jpg`/`.jpeg`): per-app icon override.
//      When the theme is active, `effectiveAppIconOverrideURL` on
//      `DockyPreferences` falls back to this asset for any app whose
//      bundle identifier matches the filename — so a file named
//      `com.apple.Safari.png` automatically replaces Safari's icon
//      while the theme is in use.
//

import Foundation

/// Top-level manifest stored at `<bundle>/theme.json`.
struct ThemeManifest: Codable, Equatable {
    /// Bumped when the manifest format changes in a non-additive way.
    /// New optional fields don't require a bump — readers ignore
    /// unknown keys via `Codable`'s default behavior.
    let schemaVersion: Int

    /// Reverse-DNS id, doubles as the on-disk install folder name.
    /// Validated to match `[A-Za-z0-9._-]+` on import.
    let id: String

    let name: String
    let author: String?
    let version: String?
    let description: String?

    let appearance: ThemeAppearance
}

struct ThemeAppearance: Codable, Equatable {
    var disablesGlassLook: Bool?
    var tile: ThemeTile?
    var window: ThemeWindow?
    var indicators: ThemeIndicators?
}

struct ThemeTile: Codable, Equatable {
    /// Raw value of `DockClipShape` (e.g. "rounded", "circle").
    var clipShape: String?
    var verticalPadding: CGFloat?
    var spacing: CGFloat?
}

struct ThemeWindow: Codable, Equatable {
    /// Raw value of `DockClipShape`.
    var clipShape: String?
    var cornerRadius: CGFloat?
    /// Path relative to `<bundle>/`.
    var backgroundImage: String?
    /// Raw value of `DockBackgroundImageMode` ("fill" or "sprite").
    var backgroundImageMode: String?
    var tintColor: ThemeColor?
    var tintOpacity: CGFloat?
}

struct ThemeIndicators: Codable, Equatable {
    /// Raw value of `DockTileIndicatorShape`.
    var shape: String?
    /// Path relative to `<bundle>/`.
    var image: String?
    var color: ThemeColor?
    var offset: CGFloat?
    var scale: CGFloat?
    var divider: ThemeDivider?
}

struct ThemeDivider: Codable, Equatable {
    /// Path relative to `<bundle>/`.
    var left: String?
    /// Path relative to `<bundle>/`.
    var right: String?
    /// Path relative to `<bundle>/`. Center divider, used when an
    /// asymmetric left/right pair isn't supplied.
    var center: String?
    var mirrorLeftOnRight: Bool?
    var paddingFraction: CGFloat?
    var offset: CGFloat?
    var imageScale: CGFloat?
}

struct ThemeColor: Codable, Equatable {
    let r: Double
    let g: Double
    let b: Double

    var dockColor: DockColor {
        DockColor(red: r, green: g, blue: b)
    }
}
