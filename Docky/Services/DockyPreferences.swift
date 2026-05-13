//
//  DockyPreferences.swift
//  Docky
//
//  Docky's own user-adjustable settings. Persisted to UserDefaults.
//  Consume via `DockyPreferences.shared`; the class is `@Observable`
//  so SwiftUI views auto-track only the properties they read in body
//  and Combine consumers bridge through `observe(_:)` from
//  `ObservationBridge.swift`.
//

import AppKit
import Foundation
import Observation

enum PinnedTileItemKind: String, Codable, Equatable {
    case app
    case appFolder
    case launchpad
    case widget
    case smartStack
    case spacer
    case divider
}

enum TrailingTileItemKind: String, Codable, Equatable {
    case folder
    case trash
    case widget
    case smartStack
    case spacer
    case divider
}

struct PinnedTileItem: Codable, Equatable, Identifiable {
    let id: String
    let kind: PinnedTileItemKind
    let bundleIdentifier: String?
    let folderDisplayName: String?
    let folderBundleIdentifiers: [String]
    let appFolderDisplayMode: AppFolderTileDisplayMode?
    let folderContentViewMode: FolderTileContentViewMode?
    let widgetKind: WidgetKind?
    let widgetOwnerBundleIdentifier: String?
    let widgetSpan: TileSpan?
    let hiddenWidgetOwnerBundleIdentifiers: [String]

    nonisolated static func app(bundleIdentifier: String) -> Self {
        Self(
            id: "app:\(bundleIdentifier)",
            kind: .app,
            bundleIdentifier: bundleIdentifier,
            folderDisplayName: nil,
            folderBundleIdentifiers: [],
            appFolderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func appFolder(
        id: String = "custom:\(UUID().uuidString)",
        displayName: String = "Folder",
        bundleIdentifiers: [String],
        displayMode: AppFolderTileDisplayMode = .grid,
        contentViewMode: FolderTileContentViewMode = .grid
    ) -> Self {
        Self(
            id: id,
            kind: .appFolder,
            bundleIdentifier: nil,
            folderDisplayName: displayName,
            folderBundleIdentifiers: bundleIdentifiers,
            appFolderDisplayMode: displayMode,
            folderContentViewMode: contentViewMode,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func widget(kind: WidgetKind, ownerBundleIdentifier: String, span: TileSpan = .three) -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .widget,
            bundleIdentifier: nil,
            folderDisplayName: nil,
            folderBundleIdentifiers: [],
            appFolderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: kind,
            widgetOwnerBundleIdentifier: ownerBundleIdentifier,
            widgetSpan: span,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func launchpad(id: String = "custom:\(UUID().uuidString)") -> Self {
        Self(
            id: id,
            kind: .launchpad,
            bundleIdentifier: nil,
            folderDisplayName: nil,
            folderBundleIdentifiers: [],
            appFolderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func smartStack(
        hiddenWidgetOwnerBundleIdentifiers: [String] = WidgetCatalog.defaultHiddenSmartStackOwnerBundleIdentifiers
    ) -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .smartStack,
            bundleIdentifier: nil,
            folderDisplayName: nil,
            folderBundleIdentifiers: [],
            appFolderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: hiddenWidgetOwnerBundleIdentifiers
        )
    }

    nonisolated static func spacer() -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .spacer,
            bundleIdentifier: nil,
            folderDisplayName: nil,
            folderBundleIdentifiers: [],
            appFolderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func divider() -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .divider,
            bundleIdentifier: nil,
            folderDisplayName: nil,
            folderBundleIdentifiers: [],
            appFolderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }
}

struct TrailingTileItem: Codable, Equatable, Identifiable {
    let id: String
    let kind: TrailingTileItemKind
    let sourceTileID: String?
    let folderURL: URL?
    let folderDisplayName: String?
    let folderDisplayMode: FolderTileDisplayMode?
    let folderContentViewMode: FolderTileContentViewMode?
    let folderSortMode: FolderTileSortMode?
    let widgetKind: WidgetKind?
    let widgetOwnerBundleIdentifier: String?
    let widgetSpan: TileSpan?
    let hiddenWidgetOwnerBundleIdentifiers: [String]

    var effectiveFolderDisplayMode: FolderTileDisplayMode {
        folderDisplayMode ?? .contents
    }

    var effectiveFolderContentViewMode: FolderTileContentViewMode {
        folderContentViewMode ?? .grid
    }

    var effectiveFolderSortMode: FolderTileSortMode {
        folderSortMode ?? .dateAdded
    }

    nonisolated init(
        id: String,
        kind: TrailingTileItemKind,
        sourceTileID: String? = nil,
        folderURL: URL? = nil,
        folderDisplayName: String? = nil,
        folderDisplayMode: FolderTileDisplayMode? = nil,
        folderContentViewMode: FolderTileContentViewMode? = nil,
        folderSortMode: FolderTileSortMode? = nil,
        widgetKind: WidgetKind? = nil,
        widgetOwnerBundleIdentifier: String? = nil,
        widgetSpan: TileSpan? = nil,
        hiddenWidgetOwnerBundleIdentifiers: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.sourceTileID = sourceTileID
        self.folderURL = folderURL
        self.folderDisplayName = folderDisplayName
        self.folderDisplayMode = folderDisplayMode
        self.folderContentViewMode = folderContentViewMode
        self.folderSortMode = folderSortMode
        self.widgetKind = widgetKind
        self.widgetOwnerBundleIdentifier = widgetOwnerBundleIdentifier
        self.widgetSpan = widgetSpan
        self.hiddenWidgetOwnerBundleIdentifiers = hiddenWidgetOwnerBundleIdentifiers
    }

    nonisolated static func folder(
        sourceTileID: String,
        displayMode: FolderTileDisplayMode = .contents,
        contentViewMode: FolderTileContentViewMode = .grid,
        sortMode: FolderTileSortMode = .dateAdded
    ) -> Self {
        Self(
            id: "folder:\(sourceTileID)",
            kind: .folder,
            sourceTileID: sourceTileID,
            folderURL: nil,
            folderDisplayName: nil,
            folderDisplayMode: displayMode,
            folderContentViewMode: contentViewMode,
            folderSortMode: sortMode,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func folder(
        id: String = "custom-folder:\(UUID().uuidString)",
        url: URL,
        displayName: String,
        displayMode: FolderTileDisplayMode = .contents,
        contentViewMode: FolderTileContentViewMode = .grid,
        sortMode: FolderTileSortMode = .dateAdded
    ) -> Self {
        Self(
            id: id,
            kind: .folder,
            sourceTileID: nil,
            folderURL: url,
            folderDisplayName: displayName,
            folderDisplayMode: displayMode,
            folderContentViewMode: contentViewMode,
            folderSortMode: sortMode,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func trash() -> Self {
        Self(
            id: "trash",
            kind: .trash,
            sourceTileID: nil,
            folderURL: nil,
            folderDisplayName: nil,
            folderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func widget(kind: WidgetKind, ownerBundleIdentifier: String, span: TileSpan = .three) -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .widget,
            sourceTileID: nil,
            folderURL: nil,
            folderDisplayName: nil,
            folderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: kind,
            widgetOwnerBundleIdentifier: ownerBundleIdentifier,
            widgetSpan: span,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func smartStack(
        hiddenWidgetOwnerBundleIdentifiers: [String] = WidgetCatalog.defaultHiddenSmartStackOwnerBundleIdentifiers
    ) -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .smartStack,
            sourceTileID: nil,
            folderURL: nil,
            folderDisplayName: nil,
            folderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: hiddenWidgetOwnerBundleIdentifiers
        )
    }

    nonisolated static func spacer() -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .spacer,
            sourceTileID: nil,
            folderURL: nil,
            folderDisplayName: nil,
            folderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func divider() -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .divider,
            sourceTileID: nil,
            folderURL: nil,
            folderDisplayName: nil,
            folderDisplayMode: nil,
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }
}

enum DockWindowPosition: String, CaseIterable, Identifiable {
    case system
    case left
    case right
    case bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .left: String(localized: "Left")
        case .right: String(localized: "Right")
        case .bottom: String(localized: "Bottom")
        }
    }

    func resolved(systemOrientation: DockSettingsService.Orientation) -> ResolvedDockWindowPosition {
        switch self {
        case .system:
            switch systemOrientation {
            case .bottom: .bottom
            case .left: .left
            case .right: .right
            }
        case .left:
            .left
        case .right:
            .right
        case .bottom:
            .bottom
        }
    }
}

enum DockWindowDisplayTarget: String, CaseIterable, Identifiable {
    case primaryDisplay
    case displayContainingPointer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primaryDisplay: String(localized: "Primary Display")
        case .displayContainingPointer: String(localized: "Display With Pointer")
        }
    }
}

enum DockWindowSpaceBehavior: String, CaseIterable, Identifiable {
    case activeSpace
    case allSpaces

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activeSpace: String(localized: "Active Space")
        case .allSpaces: String(localized: "All Spaces")
        }
    }

    func collectionBehavior(includesFullScreenAuxiliary: Bool) -> NSWindow.CollectionBehavior {
        switch self {
        case .activeSpace:
            return NSWindow.CollectionBehavior(arrayLiteral: .moveToActiveSpace, .stationary, .ignoresCycle)
        case .allSpaces:
            var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            if includesFullScreenAuxiliary {
                behavior.insert(.fullScreenAuxiliary)
            }
            return behavior
        }
    }
}

enum DockOverflowBehavior: String, CaseIterable, Identifiable {
    case rescale
    case scroll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rescale: String(localized: "Rescale")
        case .scroll: String(localized: "Scroll")
        }
    }
}

enum DockWindowAxisSizing: String, CaseIterable, Identifiable {
    case fitContent
    case fullAxis

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fitContent: String(localized: "Fit Content")
        case .fullAxis: String(localized: "Full Axis")
        }
    }
}

enum DockBackgroundImageMode: String, CaseIterable, Identifiable {
    case fill
    case sprite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: String(localized: "Fill")
        case .sprite: String(localized: "Sprite")
        }
    }
}

enum MaximizedWindowBehavior: String, CaseIterable, Identifiable {
    case ignore
    case hideDocky
    case resizeWindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ignore: String(localized: "Ignore")
        case .hideDocky: String(localized: "Hide Docky")
        case .resizeWindow: String(localized: "Resize Windows")
        }
    }

    var detail: String {
        switch self {
        case .ignore: String(localized: "Maximized windows render under Docky.")
        case .hideDocky: String(localized: "Slide Docky off-screen while a maximized window is on its display, with edge-dwell to reveal.")
        case .resizeWindow: String(localized: "When an app maximizes, shrink its window to leave room for Docky. Requires Accessibility permission and may not work for every app.")
        }
    }
}

enum DockClipShape: String, CaseIterable, Identifiable {
    case rounded
    case circle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: String(localized: "Rounded")
        case .circle: String(localized: "Circle")
        }
    }

    func resolvedCornerRadius(base: CGFloat, maximum: CGFloat) -> CGFloat {
        switch self {
        case .rounded:
            min(base, maximum)
        case .circle:
            maximum
        }
    }
}

enum ResolvedDockWindowPosition {
    case top
    case left
    case right
    case bottom

    var isVertical: Bool {
        switch self {
        case .left, .right:
            true
        case .top, .bottom:
            false
        }
    }
}

/// Behavior when an app tile is clicked while that app is already frontmost
/// with at least one visible (non-minimized) window. Default `.none` keeps the
/// click as a no-op so existing users don't change behavior on upgrade.
enum AppTileFrontmostClickBehavior: String, CaseIterable, Identifiable {
    case none
    case hide
    case cycleWindows
    case minimizeAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "Do Nothing")
        case .hide: String(localized: "Hide App")
        case .cycleWindows: String(localized: "Cycle Windows")
        case .minimizeAll: String(localized: "Minimize All Windows")
        }
    }

    var requiresPro: Bool {
        switch self {
        case .none, .hide: false
        case .cycleWindows, .minimizeAll: true
        }
    }
}

enum DockTileIndicatorShape: String, CaseIterable, Identifiable {
    case none
    case dot
    case pill
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .dot: String(localized: "Dot")
        case .pill: String(localized: "Pill")
        case .image: String(localized: "Custom Image")
        }
    }
}

struct AppIconOverride: Codable, Equatable, Identifiable {
    let bundleIdentifier: String
    let iconPath: String
    /// Optional inset, expressed as a fraction of the smaller cell
    /// dimension, applied around the override icon at render time. Lets
    /// users compensate for custom icons that lack the transparent
    /// padding system icons usually have. Missing in older serialized
    /// data, hence Optional.
    let paddingFraction: CGFloat?

    init(bundleIdentifier: String, iconPath: String, paddingFraction: CGFloat? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.iconPath = iconPath
        self.paddingFraction = paddingFraction
    }

    var id: String { bundleIdentifier }

    var effectiveIconURL: URL? {
        guard !iconPath.isEmpty, FileManager.default.fileExists(atPath: iconPath) else {
            return nil
        }

        return URL(fileURLWithPath: iconPath)
    }
}

enum TrashIconState: String, Codable, CaseIterable, Identifiable {
    case empty
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .empty: String(localized: "Empty")
        case .full: String(localized: "Full")
        }
    }

    var systemImageName: String {
        switch self {
        case .empty: "NSTrashEmpty"
        case .full: "NSTrashFull"
        }
    }
}

struct TrashIconOverride: Codable, Equatable, Identifiable {
    let state: TrashIconState
    let iconPath: String
    /// See `AppIconOverride.paddingFraction`.
    let paddingFraction: CGFloat?

    init(state: TrashIconState, iconPath: String, paddingFraction: CGFloat? = nil) {
        self.state = state
        self.iconPath = iconPath
        self.paddingFraction = paddingFraction
    }

    var id: String { state.rawValue }

    var effectiveIconURL: URL? {
        guard !iconPath.isEmpty, FileManager.default.fileExists(atPath: iconPath) else {
            return nil
        }

        return URL(fileURLWithPath: iconPath)
    }
}

struct FolderIconOverride: Codable, Equatable, Identifiable {
    let folderPath: String
    let iconPath: String
    /// See `AppIconOverride.paddingFraction`.
    let paddingFraction: CGFloat?

    init(folderPath: String, iconPath: String, paddingFraction: CGFloat? = nil) {
        self.folderPath = folderPath
        self.iconPath = iconPath
        self.paddingFraction = paddingFraction
    }

    var id: String { folderPath }

    var effectiveIconURL: URL? {
        guard !iconPath.isEmpty, FileManager.default.fileExists(atPath: iconPath) else {
            return nil
        }

        return URL(fileURLWithPath: iconPath)
    }
}

struct DockColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(nsColor: NSColor) {
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else {
            return nil
        }

        self.init(
            red: Double(rgbColor.redComponent),
            green: Double(rgbColor.greenComponent),
            blue: Double(rgbColor.blueComponent)
        )
    }

    var nsColor: NSColor {
        NSColor(deviceRed: red, green: green, blue: blue, alpha: 1)
    }
}

enum FolderTileDisplayMode: String, CaseIterable, Codable, Identifiable {
    case folder
    case contents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .folder: String(localized: "Folder")
        case .contents: String(localized: "Contents")
        }
    }
}

enum AppFolderTileDisplayMode: String, CaseIterable, Codable, Identifiable {
    case grid
    case stack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: String(localized: "Grid")
        case .stack: String(localized: "Stack")
        }
    }
}

enum FolderTileContentViewMode: String, CaseIterable, Codable, Identifiable {
    case grid
    case list
    case inline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: String(localized: "Grid")
        case .list: String(localized: "List")
        case .inline: String(localized: "Inline")
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? Self.grid.rawValue

        switch rawValue {
        case Self.list.rawValue:
            self = .list
        case Self.inline.rawValue:
            self = .inline
        case Self.grid.rawValue, "fan":
            self = .grid
        default:
            self = .grid
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum FolderTileSortMode: String, CaseIterable, Codable, Identifiable {
    case name
    case dateModified
    case dateCreated
    case dateAdded
    case kind
    case size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .dateModified: String(localized: "Date Modified")
        case .dateCreated: String(localized: "Date Created")
        case .dateAdded: String(localized: "Date Added")
        case .kind: String(localized: "Kind")
        case .size: String(localized: "Size")
        }
    }
}

enum WindowSwitcherPreviewMode: String, CaseIterable, Codable, Identifiable {
    case inPlace
    case instantFocus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inPlace: String(localized: "In Place")
        case .instantFocus: String(localized: "Instant Focus")
        }
    }

    var summary: String {
        switch self {
        case .inPlace:
            String(localized: "Hold on one selection to preview that window behind the switcher without changing focus until you release the shortcut.")
        case .instantFocus:
            String(localized: "Focus each selected window immediately while keeping the original cycling order frozen until you release the shortcut.")
        }
    }
}

enum WindowSwitcherLayout: String, CaseIterable, Codable, Identifiable {
    case auto
    case thumbnails
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .thumbnails: String(localized: "Thumbnails")
        case .list: String(localized: "List")
        }
    }

    var summary: String {
        switch self {
        case .auto:
            String(localized: "Use thumbnails when screen recording permission is granted; fall back to a compact list when previews aren't available.")
        case .thumbnails:
            String(localized: "Always show window thumbnails. Requires screen recording permission to render preview images.")
        case .list:
            String(localized: "Always show a compact vertical list with app icons and window titles. No screen recording required.")
        }
    }

    /// Resolves `.auto` based on whether thumbnail capture is currently
    /// possible. Always returns either `.thumbnails` or `.list`.
    func resolved(canCaptureThumbnails: Bool) -> WindowSwitcherLayout {
        switch self {
        case .auto: canCaptureThumbnails ? .thumbnails : .list
        case .thumbnails, .list: self
        }
    }
}

@Observable final class DockyPreferences {
    static let shared = DockyPreferences()

    /// Set of `Keys.*` strings the user has explicitly customized. Each
    /// appearance setter inserts its key; setters that clear a value
    /// (e.g. setting `windowTintColor` back to `nil`) remove it.
    ///
    /// This is the predicate the theme override layer uses: when a key
    /// is *not* in this set, `effective<X>` reads fall through to the
    /// active theme's manifest, then the built-in default. When the
    /// key *is* in this set, the user's explicit value wins.
    ///
    /// Persisted to `UserDefaults` so override status survives relaunch.
    /// Populated on first launch via the migration in `init` (any key
    /// already present in `UserDefaults` at upgrade time is treated as
    /// user-overridden — better to over-respect existing customizations
    /// than to let a theme silently replace them).
    var userOverriddenAppearanceKeys: Set<String> = []

    /// All preference keys that participate in the theme override
    /// layer (i.e. the appearance subset). Used by `init` migration
    /// and by `clearAllAppearanceOverrides()`.
    static let appearanceKeys: Set<String> = [
        Keys.disablesGlassLook,
        Keys.tileVerticalPadding,
        Keys.tileSpacing,
        Keys.tileClipShape,
        Keys.windowCornerRadius,
        Keys.windowClipShape,
        Keys.windowTintColor,
        Keys.windowTintOpacity,
        Keys.windowBackgroundImagePath,
        Keys.windowBackgroundImageMode,
        Keys.activeIndicatorShape,
        Keys.activeIndicatorImagePath,
        Keys.activeIndicatorColor,
        Keys.activeIndicatorOffset,
        Keys.activeIndicatorScale,
        Keys.dividerImagePath,
        Keys.leftDividerImagePath,
        Keys.rightDividerImagePath,
        Keys.mirrorsLeftDividerOnRight,
        Keys.dividerPaddingFraction,
        Keys.dividerImageScale,
        Keys.dividerOffset,
    ]

    /// Whether the user has an explicit override for this preference
    /// key. Used by Settings UI to show an "override / theme value"
    /// affordance, and by `effective<X>` accessors to decide which
    /// value to return.
    func isAppearanceOverridden(_ key: String) -> Bool {
        userOverriddenAppearanceKeys.contains(key)
    }

    /// Marks an appearance key as user-overridden. Idempotent.
    /// Called from every appearance setter alongside the persist write.
    fileprivate func markAppearanceOverride(_ key: String) {
        guard !userOverriddenAppearanceKeys.contains(key) else { return }
        userOverriddenAppearanceKeys.insert(key)
        persistUserOverriddenAppearanceKeys()
    }

    /// Clears the override flag for a single appearance key. The
    /// stored value is left untouched — `effective<X>` simply starts
    /// preferring the theme value (or built-in default). Used by the
    /// Settings UI "revert to theme" affordance.
    func clearAppearanceOverride(_ key: String) {
        guard userOverriddenAppearanceKeys.contains(key) else { return }
        userOverriddenAppearanceKeys.remove(key)
        persistUserOverriddenAppearanceKeys()
    }

    /// Clears every appearance override. Used by the "use theme as-is"
    /// flow and by `resetAppearanceToDefaults()`.
    func clearAllAppearanceOverrides() {
        guard !userOverriddenAppearanceKeys.isEmpty else { return }
        userOverriddenAppearanceKeys.removeAll()
        persistUserOverriddenAppearanceKeys()
    }

    private func persistUserOverriddenAppearanceKeys() {
        defaults.set(
            Array(userOverriddenAppearanceKeys),
            forKey: Keys.userOverriddenAppearanceKeys
        )
    }

    /// Padding applied inside each dock tile above and below the icon content.
    /// Total window height becomes `iconHeight + tileVerticalPadding * 2`.
    var tileVerticalPadding: CGFloat {
        didSet {
            guard tileVerticalPadding != oldValue else { return }
            defaults.set(Double(tileVerticalPadding), forKey: Keys.tileVerticalPadding)
            markAppearanceOverride(Keys.tileVerticalPadding)
        }
    }

    /// Spacing applied between adjacent dock tiles.
    var tileSpacing: CGFloat {
        didSet {
            guard tileSpacing != oldValue else { return }
            defaults.set(Double(tileSpacing), forKey: Keys.tileSpacing)
            markAppearanceOverride(Keys.tileSpacing)
        }
    }

    /// Clip shape applied to Docky-rendered tile chrome.
    var tileClipShape: DockClipShape {
        didSet {
            guard tileClipShape != oldValue else { return }
            defaults.set(tileClipShape.rawValue, forKey: Keys.tileClipShape)
            markAppearanceOverride(Keys.tileClipShape)
        }
    }

    /// Corner radius applied to the main dock window.
    var windowCornerRadius: CGFloat {
        didSet {
            guard windowCornerRadius != oldValue else { return }
            defaults.set(Double(windowCornerRadius), forKey: Keys.windowCornerRadius)
            markAppearanceOverride(Keys.windowCornerRadius)
        }
    }

    /// Clip shape applied to the main dock chrome.
    var windowClipShape: DockClipShape {
        didSet {
            guard windowClipShape != oldValue else { return }
            defaults.set(windowClipShape.rawValue, forKey: Keys.windowClipShape)
            markAppearanceOverride(Keys.windowClipShape)
        }
    }

    /// Optional tint override for the main dock window. `nil` follows the system material tint.
    var windowTintColor: DockColor? {
        didSet {
            guard windowTintColor != oldValue else { return }
            persistWindowTintColor(windowTintColor)
            if windowTintColor == nil {
                clearAppearanceOverride(Keys.windowTintColor)
            } else {
                markAppearanceOverride(Keys.windowTintColor)
            }
        }
    }

    /// Opacity applied to the main dock window tint.
    var windowTintOpacity: CGFloat {
        didSet {
            guard windowTintOpacity != oldValue else { return }
            defaults.set(Double(windowTintOpacity), forKey: Keys.windowTintOpacity)
            markAppearanceOverride(Keys.windowTintOpacity)
        }
    }

    /// Whether the main dock window should suppress its gradient border chrome.
    var disablesGlassLook: Bool {
        didSet {
            guard disablesGlassLook != oldValue else { return }
            defaults.set(disablesGlassLook, forKey: Keys.disablesGlassLook)
            markAppearanceOverride(Keys.disablesGlassLook)
        }
    }

    /// Optional image path used as the main dock window background.
    var windowBackgroundImagePath: String? {
        didSet {
            guard windowBackgroundImagePath != oldValue else { return }

            if let windowBackgroundImagePath, !windowBackgroundImagePath.isEmpty {
                defaults.set(windowBackgroundImagePath, forKey: Keys.windowBackgroundImagePath)
                markAppearanceOverride(Keys.windowBackgroundImagePath)
            } else {
                defaults.removeObject(forKey: Keys.windowBackgroundImagePath)
                clearAppearanceOverride(Keys.windowBackgroundImagePath)
            }
        }
    }

    /// How the background image is rendered inside the chrome. `fill` scales
    /// to cover the chrome while `sprite` clips the leading/trailing thirds
    /// and stretches the middle along the dock's axis.
    var windowBackgroundImageMode: DockBackgroundImageMode {
        didSet {
            guard windowBackgroundImageMode != oldValue else { return }
            defaults.set(windowBackgroundImageMode.rawValue, forKey: Keys.windowBackgroundImageMode)
            markAppearanceOverride(Keys.windowBackgroundImageMode)
        }
    }

    /// Edge Docky anchors itself to. `system` mirrors the macOS Dock.
    var windowPosition: DockWindowPosition {
        didSet {
            guard windowPosition != oldValue else { return }
            defaults.set(windowPosition.rawValue, forKey: Keys.windowPosition)
            syncSystemDockPositionIfNeeded()
        }
    }

    /// Which display owns Docky's single main window.
    var windowDisplayTarget: DockWindowDisplayTarget {
        didSet {
            guard windowDisplayTarget != oldValue else { return }
            defaults.set(windowDisplayTarget.rawValue, forKey: Keys.windowDisplayTarget)
        }
    }

    /// Whether Docky's windows stay in the active Space or join all Spaces.
    var windowSpaceBehavior: DockWindowSpaceBehavior {
        didSet {
            guard windowSpaceBehavior != oldValue else { return }
            defaults.set(windowSpaceBehavior.rawValue, forKey: Keys.windowSpaceBehavior)
        }
    }

    /// Whether Docky's main window should slide off-screen until revealed.
    var autohidesWindow: Bool {
        didSet {
            guard autohidesWindow != oldValue else { return }
            defaults.set(autohidesWindow, forKey: Keys.autohidesWindow)
        }
    }

    /// Whether Docky should register itself to launch when the user logs in.
    var opensAtLogin: Bool {
        didSet {
            guard opensAtLogin != oldValue else { return }
            defaults.set(opensAtLogin, forKey: Keys.opensAtLogin)

            guard !isSyncingOpenAtLoginPreference else {
                return
            }

            guard LaunchAtLoginService.shared.setEnabled(opensAtLogin) else {
                syncOpenAtLoginPreferenceFromSystem()
                return
            }
        }
    }

    /// Delay before Docky hides its own window after interaction ends.
    var autohideWindowDelay: TimeInterval {
        didSet {
            let clampedValue = max(0, autohideWindowDelay)
            guard clampedValue != oldValue else {
                if autohideWindowDelay != clampedValue {
                    autohideWindowDelay = clampedValue
                }
                return
            }

            if autohideWindowDelay != clampedValue {
                autohideWindowDelay = clampedValue
                return
            }

            defaults.set(clampedValue, forKey: Keys.autohideWindowDelay)
        }
    }

    /// How Docky reacts to a maximized (visibleFrame-sized, non-fullscreen)
    /// window on its target screen.
    var maximizedWindowBehavior: MaximizedWindowBehavior {
        didSet {
            guard maximizedWindowBehavior != oldValue else { return }
            defaults.set(maximizedWindowBehavior.rawValue, forKey: Keys.maximizedWindowBehavior)
        }
    }

    /// Dwell time the pointer must spend at the screen edge before Docky
    /// reveals while a fullscreen app is on the target screen. Mirrors the
    /// macOS Dock's intent-gating behavior in fullscreen.
    var fullscreenRevealDelay: TimeInterval {
        didSet {
            let clampedValue = max(0, fullscreenRevealDelay)
            guard clampedValue != oldValue else {
                if fullscreenRevealDelay != clampedValue {
                    fullscreenRevealDelay = clampedValue
                }
                return
            }

            if fullscreenRevealDelay != clampedValue {
                fullscreenRevealDelay = clampedValue
                return
            }

            defaults.set(clampedValue, forKey: Keys.fullscreenRevealDelay)
        }
    }

    /// Hover dwell before the per-tile window preview slides up. Same
    /// clamp pattern as the other delay prefs so the slider can never go
    /// negative.
    var windowPreviewHoverDelay: TimeInterval {
        didSet {
            let clampedValue = max(0, windowPreviewHoverDelay)
            guard clampedValue != oldValue else {
                if windowPreviewHoverDelay != clampedValue {
                    windowPreviewHoverDelay = clampedValue
                }
                return
            }

            if windowPreviewHoverDelay != clampedValue {
                windowPreviewHoverDelay = clampedValue
                return
            }

            defaults.set(clampedValue, forKey: Keys.windowPreviewHoverDelay)
        }
    }

    /// Layout for the per-tile hover window preview. Independent from the
    /// global switcher's layout so users can prefer thumbnails in one and
    /// list in the other.
    var windowPreviewLayout: WindowSwitcherLayout {
        didSet {
            guard windowPreviewLayout != oldValue else { return }
            defaults.set(windowPreviewLayout.rawValue, forKey: Keys.windowPreviewLayout)
        }
    }

    /// Whether Docky should hide the macOS system Dock while running.
    /// Turning this on snapshots the user's current Dock preferences and
    /// overwrites autohide/bounce behavior; turning it off restores the
    /// snapshot. The snapshot is also restored when Docky quits.
    var hidesSystemDock: Bool {
        didSet {
            guard hidesSystemDock != oldValue else { return }
            defaults.set(hidesSystemDock, forKey: Keys.hidesSystemDock)
            applySystemDockVisibilityPreference()
        }
    }

    /// How Docky handles overflow when tiles exceed the screen on the dock axis.
    var overflowBehavior: DockOverflowBehavior {
        didSet {
            guard overflowBehavior != oldValue else { return }
            defaults.set(overflowBehavior.rawValue, forKey: Keys.overflowBehavior)
        }
    }

    /// Whether Docky's window hugs its content or stretches across the full dock axis.
    var windowAxisSizing: DockWindowAxisSizing {
        didSet {
            guard windowAxisSizing != oldValue else { return }
            defaults.set(windowAxisSizing.rawValue, forKey: Keys.windowAxisSizing)
        }
    }

    /// Whether hovering an expandable widget tile presents the expanded preview window.
    var enablesWidgetHoverPreview: Bool {
        didSet {
            guard enablesWidgetHoverPreview != oldValue else { return }
            defaults.set(enablesWidgetHoverPreview, forKey: Keys.enablesWidgetHoverPreview)
        }
    }

    /// Tile spans for which the expanded hover preview is allowed to appear.
    var widgetHoverPreviewSpans: Set<TileSpan> {
        didSet {
            guard widgetHoverPreviewSpans != oldValue else { return }
            defaults.set(widgetHoverPreviewSpans.map(\.rawValue), forKey: Keys.widgetHoverPreviewSpans)
        }
    }

    /// How long the cursor must rest on a widget before its expanded preview appears. Zero = immediate.
    var widgetHoverPreviewDelay: TimeInterval {
        didSet {
            let clampedValue = max(0, widgetHoverPreviewDelay)
            guard clampedValue != oldValue else {
                if widgetHoverPreviewDelay != clampedValue {
                    widgetHoverPreviewDelay = clampedValue
                }
                return
            }

            if widgetHoverPreviewDelay != clampedValue {
                widgetHoverPreviewDelay = clampedValue
                return
            }

            defaults.set(clampedValue, forKey: Keys.widgetHoverPreviewDelay)
        }
    }

    /// Whether Docky shows the divider between pinned apps and unpinned running apps.
    var showsActivePinnedSeparator: Bool {
        didSet {
            guard showsActivePinnedSeparator != oldValue else { return }
            defaults.set(showsActivePinnedSeparator, forKey: Keys.showsActivePinnedSeparator)
        }
    }

    /// Whether Docky surfaces unpinned running apps. Disable to use Docky as a static shelf alongside the system Dock.
    var showsRunningApps: Bool {
        didSet {
            guard showsRunningApps != oldValue else { return }
            defaults.set(showsRunningApps, forKey: Keys.showsRunningApps)
        }
    }

    /// Behavior when clicking an app tile whose app is already frontmost with at least one
    /// visible window. `.none` is the default; `.cycleWindows` and `.minimizeAll` are pro-only.
    var appTileFrontmostClickBehavior: AppTileFrontmostClickBehavior {
        didSet {
            guard appTileFrontmostClickBehavior != oldValue else { return }
            defaults.set(appTileFrontmostClickBehavior.rawValue, forKey: Keys.appTileFrontmostClickBehavior)
        }
    }

    /// Whether Docky surfaces minimized window tiles in the trailing section.
    var showsMinimizedWindows: Bool {
        didSet {
            guard showsMinimizedWindows != oldValue else { return }
            defaults.set(showsMinimizedWindows, forKey: Keys.showsMinimizedWindows)
        }
    }

    /// When true, Docky hides while a fullscreen app is on its target
    /// screen and reveals on edge dwell (gated by `fullscreenRevealDelay`).
    /// Default true — matches the system Dock and what existed before this
    /// preference was added. Turning it off keeps Docky pinned over
    /// fullscreen apps.
    var hidesDuringFullscreen: Bool {
        didSet {
            guard hidesDuringFullscreen != oldValue else { return }
            defaults.set(hidesDuringFullscreen, forKey: Keys.hidesDuringFullscreen)
        }
    }

    /// Shelve mode: hides Finder and Trash tiles so the dock reads as a
    /// pure shelf of pinned apps + widgets. Independent of recent-app
    /// suppression (`hidesRecentApps`).
    var enablesShelveMode: Bool {
        didSet {
            guard enablesShelveMode != oldValue else { return }
            defaults.set(enablesShelveMode, forKey: Keys.enablesShelveMode)
        }
    }

    /// When true, recent / unpinned running apps are hidden from the dock.
    /// Equivalent to `showsRunningApps == false`; either being set hides
    /// them, so the user can disable recents from the dedicated toggle
    /// without flipping the broader "Show Running Apps" preference.
    var hidesRecentApps: Bool {
        didSet {
            guard hidesRecentApps != oldValue else { return }
            defaults.set(hidesRecentApps, forKey: Keys.hidesRecentApps)
        }
    }

    /// Shape used for the active app indicator.
    var activeIndicatorShape: DockTileIndicatorShape {
        didSet {
            guard activeIndicatorShape != oldValue else { return }
            defaults.set(activeIndicatorShape.rawValue, forKey: Keys.activeIndicatorShape)
            markAppearanceOverride(Keys.activeIndicatorShape)
        }
    }

    /// Optional image path used for the custom active app indicator.
    var activeIndicatorImagePath: String? {
        didSet {
            guard activeIndicatorImagePath != oldValue else { return }

            if let activeIndicatorImagePath, !activeIndicatorImagePath.isEmpty {
                defaults.set(activeIndicatorImagePath, forKey: Keys.activeIndicatorImagePath)
                markAppearanceOverride(Keys.activeIndicatorImagePath)
            } else {
                defaults.removeObject(forKey: Keys.activeIndicatorImagePath)
                clearAppearanceOverride(Keys.activeIndicatorImagePath)
            }
        }
    }

    /// Optional color override used for dot and pill active app indicators.
    var activeIndicatorColor: DockColor? {
        didSet {
            guard activeIndicatorColor != oldValue else { return }
            persistActiveIndicatorColor(activeIndicatorColor)
            if activeIndicatorColor == nil {
                clearAppearanceOverride(Keys.activeIndicatorColor)
            } else {
                markAppearanceOverride(Keys.activeIndicatorColor)
            }
        }
    }

    /// Optional image path used as the default divider image (applies to all dividers).
    var dividerImagePath: String? {
        didSet {
            guard dividerImagePath != oldValue else { return }

            if let dividerImagePath, !dividerImagePath.isEmpty {
                defaults.set(dividerImagePath, forKey: Keys.dividerImagePath)
                markAppearanceOverride(Keys.dividerImagePath)
            } else {
                defaults.removeObject(forKey: Keys.dividerImagePath)
                clearAppearanceOverride(Keys.dividerImagePath)
            }
        }
    }

    /// Optional image path that overrides the global divider image for the leading section divider.
    var leftDividerImagePath: String? {
        didSet {
            guard leftDividerImagePath != oldValue else { return }

            if let leftDividerImagePath, !leftDividerImagePath.isEmpty {
                defaults.set(leftDividerImagePath, forKey: Keys.leftDividerImagePath)
                markAppearanceOverride(Keys.leftDividerImagePath)
            } else {
                defaults.removeObject(forKey: Keys.leftDividerImagePath)
                clearAppearanceOverride(Keys.leftDividerImagePath)
            }
        }
    }

    /// Optional image path that overrides the global divider image for the trailing section divider.
    var rightDividerImagePath: String? {
        didSet {
            guard rightDividerImagePath != oldValue else { return }

            if let rightDividerImagePath, !rightDividerImagePath.isEmpty {
                defaults.set(rightDividerImagePath, forKey: Keys.rightDividerImagePath)
                markAppearanceOverride(Keys.rightDividerImagePath)
            } else {
                defaults.removeObject(forKey: Keys.rightDividerImagePath)
                clearAppearanceOverride(Keys.rightDividerImagePath)
            }
        }
    }

    /// When true, the trailing divider mirrors the leading divider's image instead of using its own override.
    var mirrorsLeftDividerOnRight: Bool {
        didSet {
            guard mirrorsLeftDividerOnRight != oldValue else { return }
            defaults.set(mirrorsLeftDividerOnRight, forKey: Keys.mirrorsLeftDividerOnRight)
            markAppearanceOverride(Keys.mirrorsLeftDividerOnRight)
        }
    }

    /// Extra inward offset applied to the active app indicator, in points.
    /// Positive values pull the indicator further from the screen edge.
    var activeIndicatorOffset: CGFloat {
        didSet {
            guard activeIndicatorOffset != oldValue else { return }
            defaults.set(activeIndicatorOffset, forKey: Keys.activeIndicatorOffset)
            markAppearanceOverride(Keys.activeIndicatorOffset)
        }
    }

    /// Scale multiplier applied to the active app indicator's rendered size.
    var activeIndicatorScale: CGFloat {
        didSet {
            guard activeIndicatorScale != oldValue else { return }
            defaults.set(activeIndicatorScale, forKey: Keys.activeIndicatorScale)
            markAppearanceOverride(Keys.activeIndicatorScale)
        }
    }

    /// Fraction of the tile size used to inset the divider along its short axis.
    /// 0 produces an edge-to-edge divider; 0.25 matches the legacy default.
    var dividerPaddingFraction: CGFloat {
        didSet {
            guard dividerPaddingFraction != oldValue else { return }
            defaults.set(dividerPaddingFraction, forKey: Keys.dividerPaddingFraction)
            markAppearanceOverride(Keys.dividerPaddingFraction)
        }
    }

    /// Scale multiplier applied to custom divider images.
    var dividerImageScale: CGFloat {
        didSet {
            guard dividerImageScale != oldValue else { return }
            defaults.set(dividerImageScale, forKey: Keys.dividerImageScale)
            markAppearanceOverride(Keys.dividerImageScale)
        }
    }

    /// Offset applied to dividers along the dock's main axis, in points.
    /// Positive shifts toward the dock's trailing direction.
    var dividerOffset: CGFloat {
        didSet {
            guard dividerOffset != oldValue else { return }
            defaults.set(dividerOffset, forKey: Keys.dividerOffset)
            markAppearanceOverride(Keys.dividerOffset)
        }
    }

    /// Optional per-app icon overrides used by app tiles.
    var appIconOverrides: [AppIconOverride] {
        didSet {
            guard appIconOverrides != oldValue else { return }
            persistAppIconOverrides(appIconOverrides)
        }
    }

    /// Optional icon overrides for the Trash tile, keyed by empty/full state.
    var trashIconOverrides: [TrashIconOverride] {
        didSet {
            guard trashIconOverrides != oldValue else { return }
            persistTrashIconOverrides(trashIconOverrides)
        }
    }

    /// Optional per-folder icon overrides used by folder tiles, keyed by path.
    var folderIconOverrides: [FolderIconOverride] {
        didSet {
            guard folderIconOverrides != oldValue else { return }
            persistFolderIconOverrides(folderIconOverrides)
        }
    }

    /// Optional image path used to replace the Launchpad tile's icon.
    var launchpadIconPath: String? {
        didSet {
            guard launchpadIconPath != oldValue else { return }

            if let launchpadIconPath, !launchpadIconPath.isEmpty {
                defaults.set(launchpadIconPath, forKey: Keys.launchpadIconPath)
            } else {
                defaults.removeObject(forKey: Keys.launchpadIconPath)
            }
        }
    }

    /// Optional padding fraction applied around the Launchpad override icon.
    /// Persists as a Double under `launchpadIconPaddingFraction`.
    var launchpadIconPaddingFraction: CGFloat? {
        didSet {
            guard launchpadIconPaddingFraction != oldValue else { return }

            if let launchpadIconPaddingFraction {
                defaults.set(Double(launchpadIconPaddingFraction), forKey: Keys.launchpadIconPaddingFraction)
            } else {
                defaults.removeObject(forKey: Keys.launchpadIconPaddingFraction)
            }
        }
    }

    /// Bundle identifiers hidden from Docky's app tile surfaces.
    var hiddenAppBundleIdentifiers: [String] {
        didSet {
            let normalizedIdentifiers = Self.normalizedBundleIdentifiers(hiddenAppBundleIdentifiers)
            guard normalizedIdentifiers != oldValue else {
                if hiddenAppBundleIdentifiers != normalizedIdentifiers {
                    hiddenAppBundleIdentifiers = normalizedIdentifiers
                }
                return
            }

            if hiddenAppBundleIdentifiers != normalizedIdentifiers {
                hiddenAppBundleIdentifiers = normalizedIdentifiers
                return
            }

            defaults.set(normalizedIdentifiers, forKey: Keys.hiddenAppBundleIdentifiers)
        }
    }

    /// Whether opened apps from an app folder should appear grouped beside that folder.
    var showsGroupedOpenedAppsInDock: Bool {
        didSet {
            guard showsGroupedOpenedAppsInDock != oldValue else { return }
            defaults.set(showsGroupedOpenedAppsInDock, forKey: Keys.showsGroupedOpenedAppsInDock)
        }
    }

    /// Whether the rounded backdrop should be drawn around the folder tile and
    /// its grouped opened apps. Independent of `showsGroupedOpenedAppsInDock`
    /// so users can keep the grouping without the visual halo.
    var showsGroupedOpenedAppsBackdrop: Bool {
        didSet {
            guard showsGroupedOpenedAppsBackdrop != oldValue else { return }
            defaults.set(showsGroupedOpenedAppsBackdrop, forKey: Keys.showsGroupedOpenedAppsBackdrop)
        }
    }

    /// Whether Docky's Launchpad overlay is enabled.
    var enablesLaunchpadOverlay: Bool {
        didSet {
            guard enablesLaunchpadOverlay != oldValue else { return }
            defaults.set(enablesLaunchpadOverlay, forKey: Keys.enablesLaunchpadOverlay)
        }
    }

    /// How transparent the Launchpad overlay's background tint is. `0` is
    /// fully opaque (heavy tint over the SkyLight blur); `1` is fully clear
    /// (only the live blur remains, no tint on top).
    var launchpadOverlayTransparency: CGFloat {
        didSet {
            let clampedValue = min(max(launchpadOverlayTransparency, 0), 1)
            guard clampedValue != oldValue else {
                if launchpadOverlayTransparency != clampedValue {
                    launchpadOverlayTransparency = clampedValue
                }
                return
            }

            if launchpadOverlayTransparency != clampedValue {
                launchpadOverlayTransparency = clampedValue
                return
            }

            defaults.set(Double(clampedValue), forKey: Keys.launchpadOverlayTransparency)
        }
    }

    /// Preferred column count for the Launchpad overlay grid.
    var launchpadGridColumnCount: Int {
        didSet {
            let clampedValue = max(1, launchpadGridColumnCount)
            guard clampedValue != oldValue else {
                if launchpadGridColumnCount != clampedValue {
                    launchpadGridColumnCount = clampedValue
                }
                return
            }

            if launchpadGridColumnCount != clampedValue {
                launchpadGridColumnCount = clampedValue
                return
            }

            defaults.set(clampedValue, forKey: Keys.launchpadGridColumnCount)
        }
    }

    /// Preferred row count for the Launchpad overlay grid.
    var launchpadGridRowCount: Int {
        didSet {
            let clampedValue = max(1, launchpadGridRowCount)
            guard clampedValue != oldValue else {
                if launchpadGridRowCount != clampedValue {
                    launchpadGridRowCount = clampedValue
                }
                return
            }

            if launchpadGridRowCount != clampedValue {
                launchpadGridRowCount = clampedValue
                return
            }

            defaults.set(clampedValue, forKey: Keys.launchpadGridRowCount)
        }
    }

    /// Global shortcut that toggles Docky's Launchpad overlay.
    var launchpadShortcut: KeyboardShortcut {
        didSet {
            guard launchpadShortcut != oldValue else { return }
            persistLaunchpadShortcut(launchpadShortcut)
        }
    }

    /// Whether Docky's window switcher is enabled.
    var enablesWindowSwitcher: Bool {
        didSet {
            guard enablesWindowSwitcher != oldValue else { return }
            defaults.set(enablesWindowSwitcher, forKey: Keys.enablesWindowSwitcher)
        }
    }

    /// Global shortcut that opens Docky's window switcher.
    var windowSwitcherShortcut: KeyboardShortcut {
        didSet {
            guard windowSwitcherShortcut != oldValue else { return }
            persistWindowSwitcherShortcut(windowSwitcherShortcut)
        }
    }

    /// Whether the window switcher should preview the selected window in place after a short hold.
    var showsWindowSwitcherFocusPreview: Bool {
        didSet {
            guard showsWindowSwitcherFocusPreview != oldValue else { return }
            defaults.set(showsWindowSwitcherFocusPreview, forKey: Keys.showsWindowSwitcherFocusPreview)
        }
    }

    /// Which behavior Docky's window switcher should use when previewing the selected window.
    var windowSwitcherPreviewMode: WindowSwitcherPreviewMode {
        didSet {
            guard windowSwitcherPreviewMode != oldValue else { return }
            defaults.set(windowSwitcherPreviewMode.rawValue, forKey: Keys.windowSwitcherPreviewMode)
        }
    }

    /// Layout for the window switcher overlay. `.auto` resolves to `.list` when
    /// screen-recording permission is missing (so users without thumbnails get a
    /// usable switcher) and `.thumbnails` otherwise.
    var windowSwitcherLayout: WindowSwitcherLayout {
        didSet {
            guard windowSwitcherLayout != oldValue else { return }
            defaults.set(windowSwitcherLayout.rawValue, forKey: Keys.windowSwitcherLayout)
        }
    }

    /// Docky-owned ordered pinned app bundle identifiers.
    var pinnedAppBundleIdentifiers: [String] {
        didSet {
            guard pinnedAppBundleIdentifiers != oldValue else { return }
            defaults.set(pinnedAppBundleIdentifiers, forKey: Keys.pinnedAppBundleIdentifiers)
        }
    }

    /// Docky-owned ordered pinned section items.
    var pinnedItems: [PinnedTileItem] {
        didSet {
            guard pinnedItems != oldValue else { return }
            persistPinnedItems(pinnedItems)

            let appBundleIdentifiers = pinnedItems.compactMap { item in
                item.kind == .app ? item.bundleIdentifier : nil
            }
            if pinnedAppBundleIdentifiers != appBundleIdentifiers {
                pinnedAppBundleIdentifiers = appBundleIdentifiers
            }
        }
    }

    /// Enabled widgets grouped by the app tile they extend.
    var widgetPlacements: [WidgetPlacement] {
        didSet {
            guard widgetPlacements != oldValue else { return }
            persistWidgetPlacements(widgetPlacements)
        }
    }

    /// Optional widget substitutions for app tiles.
    var appWidgetDisplays: [AppWidgetDisplay] {
        didSet {
            guard appWidgetDisplays != oldValue else { return }
            persistAppWidgetDisplays(appWidgetDisplays)
        }
    }

    /// Docky-owned ordered folder/trash section items.
    var trailingItems: [TrailingTileItem] {
        didSet {
            guard trailingItems != oldValue else { return }
            persistTrailingItems(trailingItems)
        }
    }

    /// Whether Docky has already shown the divider edit hint chip.
    var hasSeenDockEditorHint: Bool {
        didSet {
            guard hasSeenDockEditorHint != oldValue else { return }
            defaults.set(hasSeenDockEditorHint, forKey: Keys.hasSeenDockEditorHint)
        }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isSyncingOpenAtLoginPreference = false

    // MARK: - Effective appearance values (theme override layer)
    //
    // Each `effective<X>` accessor returns `userValue` when
    // `isAppearanceOverridden(Keys.X)` is true, otherwise falls
    // through to the active theme's manifest value (if any), then
    // finally to the raw stored value (which is initialized to the
    // built-in default when the key isn't in UserDefaults).
    //
    // Consumers in `Views/` should read `effective<X>` rather than
    // the raw stored property. Settings UI is the exception — its
    // sliders/pickers bind to the raw stored property so the user
    // sees and edits their own value, not the theme's.

    /// Returns `raw` when the user has overridden this key, otherwise
    /// the supplied theme value (when present), otherwise `raw` again
    /// (which equals the built-in default when no override exists).
    private func appearanceOverride<T>(_ key: String, raw: T, themed: T?) -> T {
        if isAppearanceOverridden(key) { return raw }
        return themed ?? raw
    }

    var effectiveTileVerticalPadding: CGFloat {
        appearanceOverride(
            Keys.tileVerticalPadding,
            raw: tileVerticalPadding,
            themed: ThemeManager.shared.activeManifest?.appearance.tile?.verticalPadding
        )
    }

    var effectiveTileSpacing: CGFloat {
        appearanceOverride(
            Keys.tileSpacing,
            raw: tileSpacing,
            themed: ThemeManager.shared.activeManifest?.appearance.tile?.spacing
        )
    }

    var effectiveTileClipShape: DockClipShape {
        let themed = ThemeManager.shared.activeManifest?.appearance.tile?.clipShape
            .flatMap(DockClipShape.init(rawValue:))
        return appearanceOverride(Keys.tileClipShape, raw: tileClipShape, themed: themed)
    }

    var effectiveWindowCornerRadius: CGFloat {
        appearanceOverride(
            Keys.windowCornerRadius,
            raw: windowCornerRadius,
            themed: ThemeManager.shared.activeManifest?.appearance.window?.cornerRadius
        )
    }

    var effectiveWindowClipShape: DockClipShape {
        let themed = ThemeManager.shared.activeManifest?.appearance.window?.clipShape
            .flatMap(DockClipShape.init(rawValue:))
        return appearanceOverride(Keys.windowClipShape, raw: windowClipShape, themed: themed)
    }

    var effectiveWindowTintColor: NSColor {
        if isAppearanceOverridden(Keys.windowTintColor), let user = windowTintColor {
            return user.nsColor
        }
        if let themed = ThemeManager.shared.activeManifest?.appearance.window?.tintColor {
            return themed.dockColor.nsColor
        }
        return Self.defaultWindowTintColor
    }

    var effectiveWindowTintOpacity: CGFloat {
        let raw = appearanceOverride(
            Keys.windowTintOpacity,
            raw: windowTintOpacity,
            themed: ThemeManager.shared.activeManifest?.appearance.window?.tintOpacity
        )
        return min(max(raw, 0), 1)
    }

    var effectiveDisablesGlassLook: Bool {
        appearanceOverride(
            Keys.disablesGlassLook,
            raw: disablesGlassLook,
            themed: ThemeManager.shared.activeManifest?.appearance.disablesGlassLook
        )
    }

    var effectiveWindowBackgroundImageURL: URL? {
        if isAppearanceOverridden(Keys.windowBackgroundImagePath),
           let path = windowBackgroundImagePath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        if let assetPath = ThemeManager.shared.activeManifest?.appearance.window?.backgroundImage,
           let url = ThemeManager.shared.activeAssetURL(assetPath) {
            return url
        }

        return nil
    }

    var effectiveWindowBackgroundImageMode: DockBackgroundImageMode {
        let themed = ThemeManager.shared.activeManifest?.appearance.window?.backgroundImageMode
            .flatMap(DockBackgroundImageMode.init(rawValue:))
        return appearanceOverride(Keys.windowBackgroundImageMode, raw: windowBackgroundImageMode, themed: themed)
    }

    var effectiveActiveIndicatorShape: DockTileIndicatorShape {
        let themed = ThemeManager.shared.activeManifest?.appearance.indicators?.shape
            .flatMap(DockTileIndicatorShape.init(rawValue:))
        return appearanceOverride(Keys.activeIndicatorShape, raw: activeIndicatorShape, themed: themed)
    }

    var effectiveActiveIndicatorColor: NSColor {
        if isAppearanceOverridden(Keys.activeIndicatorColor), let user = activeIndicatorColor {
            return user.nsColor
        }
        if let themed = ThemeManager.shared.activeManifest?.appearance.indicators?.color {
            return themed.dockColor.nsColor
        }
        return .labelColor
    }

    var effectiveActiveIndicatorImageURL: URL? {
        if isAppearanceOverridden(Keys.activeIndicatorImagePath),
           let path = activeIndicatorImagePath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        if let assetPath = ThemeManager.shared.activeManifest?.appearance.indicators?.image,
           let url = ThemeManager.shared.activeAssetURL(assetPath) {
            return url
        }

        return nil
    }

    var effectiveActiveIndicatorOffset: CGFloat {
        appearanceOverride(
            Keys.activeIndicatorOffset,
            raw: activeIndicatorOffset,
            themed: ThemeManager.shared.activeManifest?.appearance.indicators?.offset
        )
    }

    var effectiveActiveIndicatorScale: CGFloat {
        appearanceOverride(
            Keys.activeIndicatorScale,
            raw: activeIndicatorScale,
            themed: ThemeManager.shared.activeManifest?.appearance.indicators?.scale
        )
    }

    var effectiveMirrorsLeftDividerOnRight: Bool {
        appearanceOverride(
            Keys.mirrorsLeftDividerOnRight,
            raw: mirrorsLeftDividerOnRight,
            themed: ThemeManager.shared.activeManifest?.appearance.indicators?.divider?.mirrorLeftOnRight
        )
    }

    var effectiveDividerPaddingFraction: CGFloat {
        appearanceOverride(
            Keys.dividerPaddingFraction,
            raw: dividerPaddingFraction,
            themed: ThemeManager.shared.activeManifest?.appearance.indicators?.divider?.paddingFraction
        )
    }

    var effectiveDividerImageScale: CGFloat {
        appearanceOverride(
            Keys.dividerImageScale,
            raw: dividerImageScale,
            themed: ThemeManager.shared.activeManifest?.appearance.indicators?.divider?.imageScale
        )
    }

    var effectiveDividerOffset: CGFloat {
        appearanceOverride(
            Keys.dividerOffset,
            raw: dividerOffset,
            themed: ThemeManager.shared.activeManifest?.appearance.indicators?.divider?.offset
        )
    }

    var effectiveDividerImageURL: URL? {
        if isAppearanceOverridden(Keys.dividerImagePath),
           let url = Self.existingFileURL(at: dividerImagePath) {
            return url
        }
        if let assetPath = ThemeManager.shared.activeManifest?.appearance.indicators?.divider?.center,
           let url = ThemeManager.shared.activeAssetURL(assetPath) {
            return url
        }
        return nil
    }

    var effectiveLeftDividerImageURL: URL? {
        if isAppearanceOverridden(Keys.leftDividerImagePath),
           let url = Self.existingFileURL(at: leftDividerImagePath) {
            return url
        }
        if let assetPath = ThemeManager.shared.activeManifest?.appearance.indicators?.divider?.left,
           let url = ThemeManager.shared.activeAssetURL(assetPath) {
            return url
        }
        return effectiveDividerImageURL
    }

    var effectiveRightDividerImageURL: URL? {
        if effectiveMirrorsLeftDividerOnRight {
            return effectiveLeftDividerImageURL
        }
        if isAppearanceOverridden(Keys.rightDividerImagePath),
           let url = Self.existingFileURL(at: rightDividerImagePath) {
            return url
        }
        if let assetPath = ThemeManager.shared.activeManifest?.appearance.indicators?.divider?.right,
           let url = ThemeManager.shared.activeAssetURL(assetPath) {
            return url
        }
        return effectiveDividerImageURL
    }

    // MARK: - Explicit appearance values (for theme export)
    //
    // Returns the color when it comes from a deliberate source —
    // either a user override on this preference or the active theme's
    // manifest. Returns `nil` when the only value would be the
    // built-in system fallback, because that isn't meaningfully
    // portable to another machine.

    var explicitWindowTintColor: ThemeColor? {
        if isAppearanceOverridden(Keys.windowTintColor), let user = windowTintColor {
            return ThemeColor(r: user.red, g: user.green, b: user.blue)
        }
        if let themed = ThemeManager.shared.activeManifest?.appearance.window?.tintColor {
            return themed
        }
        return nil
    }

    var explicitActiveIndicatorColor: ThemeColor? {
        if isAppearanceOverridden(Keys.activeIndicatorColor), let user = activeIndicatorColor {
            return ThemeColor(r: user.red, g: user.green, b: user.blue)
        }
        if let themed = ThemeManager.shared.activeManifest?.appearance.indicators?.color {
            return themed
        }
        return nil
    }

    /// Resolves the divider image and mirroring flag for a given divider position class.
    /// Returns `nil` when no custom image applies.
    func resolvedDividerImage(forPositionClass positionClass: DockDividerPositionClass) -> (url: URL, mirrored: Bool)? {
        switch positionClass {
        case .left:
            guard let url = effectiveLeftDividerImageURL else { return nil }
            return (url, false)
        case .right:
            if effectiveMirrorsLeftDividerOnRight, let url = effectiveLeftDividerImageURL {
                return (url, true)
            }

            guard let url = effectiveRightDividerImageURL else { return nil }
            return (url, false)
        case .center:
            guard let url = effectiveDividerImageURL else { return nil }
            return (url, false)
        }
    }

    private static func existingFileURL(at path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    func appIconOverride(forBundleIdentifier bundleIdentifier: String) -> AppIconOverride? {
        guard ProductService.shared.isUnlocked(.customAppIcons) else {
            return nil
        }

        return appIconOverrides.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func effectiveAppIconOverrideURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        if let userURL = appIconOverride(forBundleIdentifier: bundleIdentifier)?.effectiveIconURL {
            return userURL
        }
        // Theme-supplied icons are convention-based: `assets/<bundle-id>.png`
        // inside the active theme bundle. Not gated by the Pro
        // `customAppIcons` flag — consistent with how other
        // theme-supplied appearance values flow through unconditionally.
        return ThemeManager.shared.activeAppIconURL(forBundleIdentifier: bundleIdentifier)
    }

    func setAppIconOverride(bundleIdentifier: String, iconPath: String, paddingFraction: CGFloat? = nil) {
        guard ProductService.shared.isUnlocked(.customAppIcons) else {
            return
        }

        guard !bundleIdentifier.isEmpty, !iconPath.isEmpty else {
            return
        }

        var overridesByBundleIdentifier = Dictionary(uniqueKeysWithValues: appIconOverrides.map {
            ($0.bundleIdentifier, $0)
        })
        overridesByBundleIdentifier[bundleIdentifier] = AppIconOverride(
            bundleIdentifier: bundleIdentifier,
            iconPath: iconPath,
            paddingFraction: paddingFraction
        )
        appIconOverrides = overridesByBundleIdentifier.values.sorted {
            $0.bundleIdentifier.localizedCaseInsensitiveCompare($1.bundleIdentifier) == .orderedAscending
        }
    }

    /// Updates only the padding for an existing override. No-op when the
    /// app has no override yet — callers should set an icon first.
    func setAppIconPaddingFraction(bundleIdentifier: String, paddingFraction: CGFloat?) {
        guard let existing = appIconOverrides.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return
        }
        setAppIconOverride(
            bundleIdentifier: bundleIdentifier,
            iconPath: existing.iconPath,
            paddingFraction: paddingFraction
        )
    }

    func removeAppIconOverride(bundleIdentifier: String) {
        appIconOverrides.removeAll { $0.bundleIdentifier == bundleIdentifier }
    }

    /// Padding fraction (0...0.5) applied around an app's override icon.
    /// Returns 0 when no override or no padding has been configured.
    func appIconOverridePadding(forBundleIdentifier bundleIdentifier: String) -> CGFloat {
        appIconOverride(forBundleIdentifier: bundleIdentifier)?.paddingFraction ?? 0
    }

    func trashIconOverride(forState state: TrashIconState) -> TrashIconOverride? {
        guard ProductService.shared.isUnlocked(.customAppIcons) else {
            return nil
        }

        return trashIconOverrides.first { $0.state == state }
    }

    func effectiveTrashIconOverrideURL(forState state: TrashIconState) -> URL? {
        trashIconOverride(forState: state)?.effectiveIconURL
    }

    func setTrashIconOverride(state: TrashIconState, iconPath: String, paddingFraction: CGFloat? = nil) {
        guard ProductService.shared.isUnlocked(.customAppIcons) else {
            return
        }

        guard !iconPath.isEmpty else {
            return
        }

        var overridesByState = Dictionary(uniqueKeysWithValues: trashIconOverrides.map {
            ($0.state, $0)
        })
        overridesByState[state] = TrashIconOverride(
            state: state,
            iconPath: iconPath,
            paddingFraction: paddingFraction
        )
        trashIconOverrides = TrashIconState.allCases.compactMap { overridesByState[$0] }
    }

    func setTrashIconPaddingFraction(state: TrashIconState, paddingFraction: CGFloat?) {
        guard let existing = trashIconOverrides.first(where: { $0.state == state }) else {
            return
        }
        setTrashIconOverride(
            state: state,
            iconPath: existing.iconPath,
            paddingFraction: paddingFraction
        )
    }

    func removeTrashIconOverride(state: TrashIconState) {
        trashIconOverrides.removeAll { $0.state == state }
    }

    func trashIconOverridePadding(forState state: TrashIconState) -> CGFloat {
        trashIconOverride(forState: state)?.paddingFraction ?? 0
    }

    func folderIconOverride(forPath path: String) -> FolderIconOverride? {
        guard ProductService.shared.isUnlocked(.customAppIcons) else {
            return nil
        }

        return folderIconOverrides.first { $0.folderPath == path }
    }

    func effectiveFolderIconOverrideURL(forPath path: String) -> URL? {
        folderIconOverride(forPath: path)?.effectiveIconURL
    }

    func setFolderIconOverride(folderPath: String, iconPath: String, paddingFraction: CGFloat? = nil) {
        guard ProductService.shared.isUnlocked(.customAppIcons) else {
            return
        }

        guard !folderPath.isEmpty, !iconPath.isEmpty else {
            return
        }

        var overridesByPath = DataIntegrityReporter.makeDictionary(
            folderIconOverrides.map { ($0.folderPath, $0) },
            site: "DockyPreferences.folderIconOverrides"
        )
        overridesByPath[folderPath] = FolderIconOverride(
            folderPath: folderPath,
            iconPath: iconPath,
            paddingFraction: paddingFraction
        )
        folderIconOverrides = overridesByPath.values.sorted {
            $0.folderPath.localizedCaseInsensitiveCompare($1.folderPath) == .orderedAscending
        }
    }

    func setFolderIconPaddingFraction(folderPath: String, paddingFraction: CGFloat?) {
        guard let existing = folderIconOverrides.first(where: { $0.folderPath == folderPath }) else {
            return
        }
        setFolderIconOverride(
            folderPath: folderPath,
            iconPath: existing.iconPath,
            paddingFraction: paddingFraction
        )
    }

    func folderIconOverridePadding(forPath path: String) -> CGFloat {
        folderIconOverride(forPath: path)?.paddingFraction ?? 0
    }

    func removeFolderIconOverride(folderPath: String) {
        folderIconOverrides.removeAll { $0.folderPath == folderPath }
    }

    var effectiveLaunchpadIconOverrideURL: URL? {
        guard ProductService.shared.isUnlocked(.customAppIcons) else {
            return nil
        }
        guard let path = launchpadIconPath, !path.isEmpty else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// Padding fraction (0...0.5) for the Launchpad override icon. Returns
    /// 0 when no override or no padding is configured.
    var effectiveLaunchpadIconOverridePadding: CGFloat {
        guard effectiveLaunchpadIconOverrideURL != nil else { return 0 }
        return launchpadIconPaddingFraction ?? 0
    }

    func isAppHiddenInDocky(bundleIdentifier: String) -> Bool {
        // Docky reports itself as effectively hidden so any surface that
        // gates on this returns the right answer even though Docky never
        // actually shows up in the explicit hidden list.
        if bundleIdentifier == Bundle.main.bundleIdentifier { return true }
        return hiddenAppBundleIdentifiers.contains(bundleIdentifier)
    }

    func setAppHiddenInDocky(bundleIdentifier: String, isHidden: Bool) {
        guard !bundleIdentifier.isEmpty else {
            return
        }
        // Docky never shows itself anywhere, so adding it to the
        // hidden-apps list would be a confusing no-op — refuse it.
        if bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }

        var bundleIdentifiers = Set(hiddenAppBundleIdentifiers)
        if isHidden {
            bundleIdentifiers.insert(bundleIdentifier)
        } else {
            bundleIdentifiers.remove(bundleIdentifier)
        }

        hiddenAppBundleIdentifiers = bundleIdentifiers.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    static var defaultWindowTintColor: NSColor {
        NSColor.windowBackgroundColor.blended(withFraction: 0.18, of: .black) ?? .windowBackgroundColor
    }

    private enum Keys {
        static let tileVerticalPadding = "docky.tileVerticalPadding"
        static let tileSpacing = "docky.tileSpacing"
        static let tileClipShape = "docky.tileClipShape"
        static let windowCornerRadius = "docky.windowCornerRadius"
        static let windowClipShape = "docky.windowClipShape"
        static let windowTintColor = "docky.windowTintColor"
        static let windowTintOpacity = "docky.windowTintOpacity"
        static let disablesGlassLook = "docky.disablesGlassLook"
        static let windowBackgroundImagePath = "docky.windowBackgroundImagePath"
        static let windowBackgroundImageMode = "docky.windowBackgroundImageMode"
        static let windowPosition = "docky.windowPosition"
        static let windowDisplayTarget = "docky.windowDisplayTarget"
        static let windowSpaceBehavior = "docky.windowSpaceBehavior"
        static let autohidesWindow = "docky.autohidesWindow"
        static let opensAtLogin = "docky.opensAtLogin"
        static let autohideWindowDelay = "docky.autohideWindowDelay"
        static let fullscreenRevealDelay = "docky.fullscreenRevealDelay"
        static let windowPreviewHoverDelay = "docky.windowPreviewHoverDelay"
        static let windowPreviewLayout = "docky.windowPreviewLayout"
        static let maximizedWindowBehavior = "docky.maximizedWindowBehavior"
        static let hidesSystemDock = "docky.hidesSystemDock"
        static let overflowBehavior = "docky.overflowBehavior"
        static let windowAxisSizing = "docky.windowAxisSizing"
        static let enablesWidgetHoverPreview = "docky.enablesWidgetHoverPreview"
        static let widgetHoverPreviewSpans = "docky.widgetHoverPreviewSpans"
        static let widgetHoverPreviewDelay = "docky.widgetHoverGrowDelay"
        static let showsActivePinnedSeparator = "docky.showsActivePinnedSeparator"
        static let showsRunningApps = "docky.showsRunningApps"
        static let showsMinimizedWindows = "docky.showsMinimizedWindows"
        static let hidesDuringFullscreen = "docky.hidesDuringFullscreen"
        static let enablesShelveMode = "docky.enablesShelveMode"
        static let hidesRecentApps = "docky.hidesRecentApps"
        static let appTileFrontmostClickBehavior = "docky.appTileFrontmostClickBehavior"
        static let activeIndicatorShape = "docky.activeIndicatorShape"
        static let activeIndicatorImagePath = "docky.activeIndicatorImagePath"
        static let activeIndicatorColor = "docky.activeIndicatorColor"
        static let dividerImagePath = "docky.dividerImagePath"
        static let leftDividerImagePath = "docky.leftDividerImagePath"
        static let rightDividerImagePath = "docky.rightDividerImagePath"
        static let mirrorsLeftDividerOnRight = "docky.mirrorsLeftDividerOnRight"
        static let activeIndicatorOffset = "docky.activeIndicatorOffset"
        static let activeIndicatorScale = "docky.activeIndicatorScale"
        static let dividerPaddingFraction = "docky.dividerPaddingFraction"
        static let dividerImageScale = "docky.dividerImageScale"
        static let dividerOffset = "docky.dividerOffset"
        static let appIconOverrides = "docky.appIconOverrides"
        static let trashIconOverrides = "docky.trashIconOverrides"
        static let folderIconOverrides = "docky.folderIconOverrides"
        static let launchpadIconPath = "docky.launchpadIconPath"
        static let launchpadIconPaddingFraction = "docky.launchpadIconPaddingFraction"
        static let hiddenAppBundleIdentifiers = "docky.hiddenAppBundleIdentifiers"
        static let showsGroupedOpenedAppsInDock = "docky.showsGroupedOpenedAppsInDock"
        static let showsGroupedOpenedAppsBackdrop = "docky.showsGroupedOpenedAppsBackdrop"
        static let enablesLaunchpadOverlay = "docky.enablesLaunchpadOverlay"
        static let launchpadOverlayTransparency = "docky.launchpadOverlayTransparency"
        static let launchpadGridColumnCount = "docky.launchpadGridColumnCount"
        static let launchpadGridRowCount = "docky.launchpadGridRowCount"
        static let launchpadShortcut = "docky.launchpadShortcut"
        static let enablesWindowSwitcher = "docky.enablesWindowSwitcher"
        static let windowSwitcherShortcut = "docky.windowSwitcherShortcut"
        static let showsWindowSwitcherFocusPreview = "docky.showsWindowSwitcherFocusPreview"
        static let windowSwitcherPreviewMode = "docky.windowSwitcherPreviewMode"
        static let windowSwitcherLayout = "docky.windowSwitcherLayout"
        static let pinnedAppBundleIdentifiers = "docky.pinnedAppBundleIdentifiers"
        static let pinnedItems = "docky.pinnedItems"
        static let widgetPlacements = "docky.widgetPlacements"
        static let appWidgetDisplays = "docky.appWidgetDisplays"
        static let trailingItems = "docky.trailingItems"
        static let hasSeenDockEditorHint = "docky.hasSeenDockEditorHint"
        static let userOverriddenAppearanceKeys = "docky.userOverriddenAppearanceKeys"
        static let appearanceOverrideMigrationVersion = "docky.appearanceOverrideMigrationVersion"
    }

    private enum DefaultValues {
        static let tileVerticalPadding: CGFloat = 8
        static let tileSpacing: CGFloat = 0
        static let tileClipShape: DockClipShape = .rounded
        static let windowCornerRadius: CGFloat = 24
        static let windowClipShape: DockClipShape = .rounded
        static let windowTintColor: DockColor? = nil
        static let windowTintOpacity: CGFloat = 0.22
        static let disablesGlassLook = false
        static let windowBackgroundImagePath: String? = nil
        static let windowBackgroundImageMode: DockBackgroundImageMode = .fill
        static let windowPosition: DockWindowPosition = .system
        static let windowDisplayTarget: DockWindowDisplayTarget = .primaryDisplay
        static let windowSpaceBehavior: DockWindowSpaceBehavior = .allSpaces
        static let autohidesWindow = false
        static let opensAtLogin = true
        static let autohideWindowDelay: TimeInterval = 0.5
        static let fullscreenRevealDelay: TimeInterval = 0.5
        static let windowPreviewHoverDelay: TimeInterval = 1.0
        static let windowPreviewLayout: WindowSwitcherLayout = .auto
        static let maximizedWindowBehavior: MaximizedWindowBehavior = .ignore
        static let hidesSystemDock = true
        static let overflowBehavior: DockOverflowBehavior = .rescale
        static let windowAxisSizing: DockWindowAxisSizing = .fitContent
        static let enablesWidgetHoverPreview = true
        static let widgetHoverPreviewSpans: Set<TileSpan> = Set(TileSpan.allCases)
        static let widgetHoverPreviewDelay: TimeInterval = 1
        static let showsActivePinnedSeparator = true
        static let showsRunningApps = true
        static let showsMinimizedWindows = true
        static let hidesDuringFullscreen = true
        static let enablesShelveMode = false
        static let hidesRecentApps = false
        static let appTileFrontmostClickBehavior: AppTileFrontmostClickBehavior = .none
        static let activeIndicatorShape: DockTileIndicatorShape = .dot
        static let activeIndicatorImagePath: String? = nil
        static let activeIndicatorColor: DockColor? = nil
        static let dividerImagePath: String? = nil
        static let leftDividerImagePath: String? = nil
        static let rightDividerImagePath: String? = nil
        static let mirrorsLeftDividerOnRight = false
        static let activeIndicatorOffset: CGFloat = 0
        static let activeIndicatorScale: CGFloat = 1
        static let dividerPaddingFraction: CGFloat = 0.25
        static let dividerImageScale: CGFloat = 1
        static let dividerOffset: CGFloat = 0
        static let appIconOverrides: [AppIconOverride] = []
        static let trashIconOverrides: [TrashIconOverride] = []
        static let folderIconOverrides: [FolderIconOverride] = []
        static let launchpadIconPath: String? = nil
        static let launchpadIconPaddingFraction: CGFloat? = nil
        static let hiddenAppBundleIdentifiers: [String] = []
        static let showsGroupedOpenedAppsInDock = true
        static let showsGroupedOpenedAppsBackdrop = true
        static let enablesLaunchpadOverlay = true
        static let launchpadOverlayTransparency: CGFloat = 0.4
        static let launchpadGridColumnCount = 7
        static let launchpadGridRowCount = 5
        static let launchpadShortcut = KeyboardShortcut.empty
        static let enablesWindowSwitcher = true
        static let windowSwitcherShortcut = KeyboardShortcut(keyCode: 48, modifierFlags: [.option])
        static let showsWindowSwitcherFocusPreview = true
        static let windowSwitcherPreviewMode: WindowSwitcherPreviewMode = .inPlace
        static let windowSwitcherLayout: WindowSwitcherLayout = .auto
        static let pinnedAppBundleIdentifiers: [String] = []
        static let pinnedItems: [PinnedTileItem] = []
        static let widgetPlacements: [WidgetPlacement] = []
        static let appWidgetDisplays: [AppWidgetDisplay] = []
        static let trailingItems: [TrailingTileItem] = []
        static let hasSeenDockEditorHint = false
    }

    private init() {
        self.defaults = .standard
        let storedVerticalPadding = defaults.object(forKey: Keys.tileVerticalPadding) as? Double
        let storedTileSpacing = defaults.object(forKey: Keys.tileSpacing) as? Double
        let storedTileClipShape = defaults.string(forKey: Keys.tileClipShape)
        let storedWindowCornerRadius = defaults.object(forKey: Keys.windowCornerRadius) as? Double
        let storedWindowClipShape = defaults.string(forKey: Keys.windowClipShape)
        let storedWindowTintColor = defaults.data(forKey: Keys.windowTintColor)
        let storedWindowTintOpacity = defaults.object(forKey: Keys.windowTintOpacity) as? Double
        let storedDisablesGlassLook = defaults.object(forKey: Keys.disablesGlassLook) as? Bool
        let storedWindowBackgroundImagePath = defaults.string(forKey: Keys.windowBackgroundImagePath)
        let storedWindowBackgroundImageMode = defaults.string(forKey: Keys.windowBackgroundImageMode)
        let storedWindowPosition = defaults.string(forKey: Keys.windowPosition)
        let storedWindowDisplayTarget = defaults.string(forKey: Keys.windowDisplayTarget)
        let storedWindowSpaceBehavior = defaults.string(forKey: Keys.windowSpaceBehavior)
        let storedAutohidesWindow = defaults.object(forKey: Keys.autohidesWindow) as? Bool
        let storedOpensAtLogin = defaults.object(forKey: Keys.opensAtLogin) as? Bool
        let storedAutohideWindowDelay = defaults.object(forKey: Keys.autohideWindowDelay) as? Double
        let storedFullscreenRevealDelay = defaults.object(forKey: Keys.fullscreenRevealDelay) as? Double
        let storedWindowPreviewHoverDelay = defaults.object(forKey: Keys.windowPreviewHoverDelay) as? Double
        let storedWindowPreviewLayout = defaults.string(forKey: Keys.windowPreviewLayout)
        let storedMaximizedWindowBehavior = defaults.string(forKey: Keys.maximizedWindowBehavior)
        let storedHidesSystemDock = defaults.object(forKey: Keys.hidesSystemDock) as? Bool
        let storedOverflowBehavior = defaults.string(forKey: Keys.overflowBehavior)
        let storedWindowAxisSizing = defaults.string(forKey: Keys.windowAxisSizing)
        let storedEnablesWidgetHoverPreview = defaults.object(forKey: Keys.enablesWidgetHoverPreview) as? Bool
        let storedWidgetHoverPreviewSpans = defaults.array(forKey: Keys.widgetHoverPreviewSpans) as? [Int]
        let storedWidgetHoverPreviewDelay = defaults.object(forKey: Keys.widgetHoverPreviewDelay) as? Double
        let storedShowsActivePinnedSeparator = defaults.object(forKey: Keys.showsActivePinnedSeparator) as? Bool
        let storedShowsRunningApps = defaults.object(forKey: Keys.showsRunningApps) as? Bool
        let storedShowsMinimizedWindows = defaults.object(forKey: Keys.showsMinimizedWindows) as? Bool
        let storedEnablesShelveMode = defaults.object(forKey: Keys.enablesShelveMode) as? Bool
        let storedHidesRecentApps = defaults.object(forKey: Keys.hidesRecentApps) as? Bool
        let storedAppTileFrontmostClickBehavior = defaults.string(forKey: Keys.appTileFrontmostClickBehavior)
        let storedActiveIndicatorShape = defaults.string(forKey: Keys.activeIndicatorShape)
        let storedActiveIndicatorImagePath = defaults.string(forKey: Keys.activeIndicatorImagePath)
        let storedActiveIndicatorColor = defaults.data(forKey: Keys.activeIndicatorColor)
        let storedDividerImagePath = defaults.string(forKey: Keys.dividerImagePath)
        let storedLeftDividerImagePath = defaults.string(forKey: Keys.leftDividerImagePath)
        let storedRightDividerImagePath = defaults.string(forKey: Keys.rightDividerImagePath)
        let storedMirrorsLeftDividerOnRight = defaults.object(forKey: Keys.mirrorsLeftDividerOnRight) as? Bool
        let storedActiveIndicatorOffset = defaults.object(forKey: Keys.activeIndicatorOffset) as? Double
        let storedActiveIndicatorScale = defaults.object(forKey: Keys.activeIndicatorScale) as? Double
        let storedDividerPaddingFraction = defaults.object(forKey: Keys.dividerPaddingFraction) as? Double
        let storedDividerImageScale = defaults.object(forKey: Keys.dividerImageScale) as? Double
        let storedDividerOffset = defaults.object(forKey: Keys.dividerOffset) as? Double
        let storedAppIconOverrides = defaults.data(forKey: Keys.appIconOverrides)
        let storedTrashIconOverrides = defaults.data(forKey: Keys.trashIconOverrides)
        let storedFolderIconOverrides = defaults.data(forKey: Keys.folderIconOverrides)
        let storedLaunchpadIconPath = defaults.string(forKey: Keys.launchpadIconPath)
        let storedLaunchpadIconPaddingFraction = defaults.object(forKey: Keys.launchpadIconPaddingFraction) as? Double
        let storedHiddenAppBundleIdentifiers = defaults.stringArray(forKey: Keys.hiddenAppBundleIdentifiers)
        let storedShowsGroupedOpenedAppsInDock = defaults.object(forKey: Keys.showsGroupedOpenedAppsInDock) as? Bool
        let storedShowsGroupedOpenedAppsBackdrop = defaults.object(forKey: Keys.showsGroupedOpenedAppsBackdrop) as? Bool
        let storedEnablesLaunchpadOverlay = defaults.object(forKey: Keys.enablesLaunchpadOverlay) as? Bool
        let storedLaunchpadOverlayTransparency = defaults.object(forKey: Keys.launchpadOverlayTransparency) as? Double
        let storedLaunchpadGridColumnCount = defaults.object(forKey: Keys.launchpadGridColumnCount) as? Int
        let storedLaunchpadGridRowCount = defaults.object(forKey: Keys.launchpadGridRowCount) as? Int
        let storedLaunchpadShortcut = defaults.data(forKey: Keys.launchpadShortcut)
        let storedEnablesWindowSwitcher = defaults.object(forKey: Keys.enablesWindowSwitcher) as? Bool
        let storedWindowSwitcherShortcut = defaults.data(forKey: Keys.windowSwitcherShortcut)
        let storedShowsWindowSwitcherFocusPreview = defaults.object(forKey: Keys.showsWindowSwitcherFocusPreview) as? Bool
        let storedWindowSwitcherPreviewMode = defaults.string(forKey: Keys.windowSwitcherPreviewMode)
        let storedWindowSwitcherLayout = defaults.string(forKey: Keys.windowSwitcherLayout)
        let storedPinnedAppBundleIdentifiers = defaults.stringArray(forKey: Keys.pinnedAppBundleIdentifiers)
        let storedPinnedItems = defaults.data(forKey: Keys.pinnedItems)
        let storedWidgetPlacements = defaults.data(forKey: Keys.widgetPlacements)
        let storedAppWidgetDisplays = defaults.data(forKey: Keys.appWidgetDisplays)
        let storedTrailingItems = defaults.data(forKey: Keys.trailingItems)
        let storedHasSeenDockEditorHint = defaults.object(forKey: Keys.hasSeenDockEditorHint) as? Bool
        let initialPinnedAppBundleIdentifiers = storedPinnedAppBundleIdentifiers ?? DefaultValues.pinnedAppBundleIdentifiers
        let initialPinnedItems = Self.decodePinnedItems(from: storedPinnedItems)
            ?? initialPinnedAppBundleIdentifiers.map(PinnedTileItem.app(bundleIdentifier:))
        self.tileVerticalPadding = storedVerticalPadding.map { CGFloat($0) } ?? DefaultValues.tileVerticalPadding
        self.tileSpacing = storedTileSpacing.map { CGFloat($0) } ?? DefaultValues.tileSpacing
        self.tileClipShape = (storedTileClipShape.flatMap(DockClipShape.init(rawValue:)) ?? DefaultValues.tileClipShape)
        self.windowCornerRadius = storedWindowCornerRadius.map { CGFloat($0) } ?? DefaultValues.windowCornerRadius
        self.windowClipShape = (storedWindowClipShape.flatMap(DockClipShape.init(rawValue:)) ?? DefaultValues.windowClipShape)
        self.windowTintColor = Self.decodeColor(from: storedWindowTintColor) ?? DefaultValues.windowTintColor
        self.windowTintOpacity = storedWindowTintOpacity.map { CGFloat($0) } ?? DefaultValues.windowTintOpacity
        self.disablesGlassLook = storedDisablesGlassLook ?? DefaultValues.disablesGlassLook
        self.windowBackgroundImagePath = storedWindowBackgroundImagePath ?? DefaultValues.windowBackgroundImagePath
        self.windowBackgroundImageMode = storedWindowBackgroundImageMode.flatMap(DockBackgroundImageMode.init(rawValue:)) ?? DefaultValues.windowBackgroundImageMode
        self.windowPosition = (storedWindowPosition.flatMap(DockWindowPosition.init(rawValue:)) ?? DefaultValues.windowPosition)
        self.windowDisplayTarget = (storedWindowDisplayTarget.flatMap(DockWindowDisplayTarget.init(rawValue:)) ?? DefaultValues.windowDisplayTarget)
        self.windowSpaceBehavior = (storedWindowSpaceBehavior.flatMap(DockWindowSpaceBehavior.init(rawValue:)) ?? DefaultValues.windowSpaceBehavior)
        self.autohidesWindow = storedAutohidesWindow ?? DefaultValues.autohidesWindow
        self.opensAtLogin = storedOpensAtLogin ?? LaunchAtLoginService.shared.isEnabled
        self.autohideWindowDelay = max(storedAutohideWindowDelay ?? DefaultValues.autohideWindowDelay, 0)
        self.fullscreenRevealDelay = max(storedFullscreenRevealDelay ?? DefaultValues.fullscreenRevealDelay, 0)
        self.windowPreviewHoverDelay = max(storedWindowPreviewHoverDelay ?? DefaultValues.windowPreviewHoverDelay, 0)
        self.windowPreviewLayout = storedWindowPreviewLayout.flatMap(WindowSwitcherLayout.init(rawValue:)) ?? DefaultValues.windowPreviewLayout
        self.maximizedWindowBehavior = (storedMaximizedWindowBehavior.flatMap(MaximizedWindowBehavior.init(rawValue:)) ?? DefaultValues.maximizedWindowBehavior)
        self.hidesSystemDock = storedHidesSystemDock ?? DefaultValues.hidesSystemDock
        self.overflowBehavior = (storedOverflowBehavior.flatMap(DockOverflowBehavior.init(rawValue:)) ?? DefaultValues.overflowBehavior)
        self.windowAxisSizing = (storedWindowAxisSizing.flatMap(DockWindowAxisSizing.init(rawValue:)) ?? DefaultValues.windowAxisSizing)
        self.enablesWidgetHoverPreview = storedEnablesWidgetHoverPreview ?? DefaultValues.enablesWidgetHoverPreview
        self.widgetHoverPreviewSpans = storedWidgetHoverPreviewSpans
            .map { Set($0.compactMap(TileSpan.init(rawValue:))) }
            ?? DefaultValues.widgetHoverPreviewSpans
        self.widgetHoverPreviewDelay = max(storedWidgetHoverPreviewDelay ?? DefaultValues.widgetHoverPreviewDelay, 0)
        self.showsActivePinnedSeparator = storedShowsActivePinnedSeparator ?? DefaultValues.showsActivePinnedSeparator
        self.showsRunningApps = storedShowsRunningApps ?? DefaultValues.showsRunningApps
        self.showsMinimizedWindows = storedShowsMinimizedWindows ?? DefaultValues.showsMinimizedWindows
        self.hidesDuringFullscreen = (defaults.object(forKey: Keys.hidesDuringFullscreen) as? Bool) ?? DefaultValues.hidesDuringFullscreen
        self.enablesShelveMode = storedEnablesShelveMode ?? DefaultValues.enablesShelveMode
        self.hidesRecentApps = storedHidesRecentApps ?? DefaultValues.hidesRecentApps
        self.appTileFrontmostClickBehavior = storedAppTileFrontmostClickBehavior
            .flatMap(AppTileFrontmostClickBehavior.init(rawValue:))
            ?? DefaultValues.appTileFrontmostClickBehavior
        self.activeIndicatorShape = (storedActiveIndicatorShape.flatMap(DockTileIndicatorShape.init(rawValue:)) ?? DefaultValues.activeIndicatorShape)
        self.activeIndicatorImagePath = storedActiveIndicatorImagePath ?? DefaultValues.activeIndicatorImagePath
        self.activeIndicatorColor = Self.decodeColor(from: storedActiveIndicatorColor) ?? DefaultValues.activeIndicatorColor
        self.dividerImagePath = storedDividerImagePath ?? DefaultValues.dividerImagePath
        self.leftDividerImagePath = storedLeftDividerImagePath ?? DefaultValues.leftDividerImagePath
        self.rightDividerImagePath = storedRightDividerImagePath ?? DefaultValues.rightDividerImagePath
        self.mirrorsLeftDividerOnRight = storedMirrorsLeftDividerOnRight ?? DefaultValues.mirrorsLeftDividerOnRight
        self.activeIndicatorOffset = storedActiveIndicatorOffset.map { CGFloat($0) } ?? DefaultValues.activeIndicatorOffset
        self.activeIndicatorScale = max(0.25, storedActiveIndicatorScale.map { CGFloat($0) } ?? DefaultValues.activeIndicatorScale)
        self.dividerPaddingFraction = min(max(storedDividerPaddingFraction.map { CGFloat($0) } ?? DefaultValues.dividerPaddingFraction, 0), 0.5)
        self.dividerImageScale = max(0.25, storedDividerImageScale.map { CGFloat($0) } ?? DefaultValues.dividerImageScale)
        self.dividerOffset = storedDividerOffset.map { CGFloat($0) } ?? DefaultValues.dividerOffset
        self.appIconOverrides = Self.decodeAppIconOverrides(from: storedAppIconOverrides) ?? DefaultValues.appIconOverrides
        self.trashIconOverrides = Self.decodeTrashIconOverrides(from: storedTrashIconOverrides) ?? DefaultValues.trashIconOverrides
        self.folderIconOverrides = Self.decodeFolderIconOverrides(from: storedFolderIconOverrides) ?? DefaultValues.folderIconOverrides
        self.launchpadIconPath = storedLaunchpadIconPath ?? DefaultValues.launchpadIconPath
        self.launchpadIconPaddingFraction = storedLaunchpadIconPaddingFraction.map { CGFloat($0) }
            ?? DefaultValues.launchpadIconPaddingFraction
        self.hiddenAppBundleIdentifiers = Self.normalizedBundleIdentifiers(storedHiddenAppBundleIdentifiers ?? DefaultValues.hiddenAppBundleIdentifiers)
        self.showsGroupedOpenedAppsInDock = storedShowsGroupedOpenedAppsInDock ?? DefaultValues.showsGroupedOpenedAppsInDock
        self.showsGroupedOpenedAppsBackdrop = storedShowsGroupedOpenedAppsBackdrop ?? DefaultValues.showsGroupedOpenedAppsBackdrop
        self.enablesLaunchpadOverlay = storedEnablesLaunchpadOverlay ?? DefaultValues.enablesLaunchpadOverlay
        self.launchpadOverlayTransparency = min(max(
            storedLaunchpadOverlayTransparency.map { CGFloat($0) } ?? DefaultValues.launchpadOverlayTransparency,
            0
        ), 1)
        self.launchpadGridColumnCount = max(storedLaunchpadGridColumnCount ?? DefaultValues.launchpadGridColumnCount, 1)
        self.launchpadGridRowCount = max(storedLaunchpadGridRowCount ?? DefaultValues.launchpadGridRowCount, 1)
        self.launchpadShortcut = Self.decodeKeyboardShortcut(from: storedLaunchpadShortcut) ?? DefaultValues.launchpadShortcut
        self.enablesWindowSwitcher = storedEnablesWindowSwitcher ?? DefaultValues.enablesWindowSwitcher
        self.windowSwitcherShortcut = Self.decodeKeyboardShortcut(from: storedWindowSwitcherShortcut) ?? DefaultValues.windowSwitcherShortcut
        self.showsWindowSwitcherFocusPreview = storedShowsWindowSwitcherFocusPreview ?? DefaultValues.showsWindowSwitcherFocusPreview
        self.windowSwitcherPreviewMode = storedWindowSwitcherPreviewMode.flatMap(WindowSwitcherPreviewMode.init(rawValue:)) ?? DefaultValues.windowSwitcherPreviewMode
        self.windowSwitcherLayout = storedWindowSwitcherLayout.flatMap(WindowSwitcherLayout.init(rawValue:)) ?? DefaultValues.windowSwitcherLayout
        self.pinnedAppBundleIdentifiers = initialPinnedAppBundleIdentifiers
        self.pinnedItems = initialPinnedItems
        self.widgetPlacements = Self.decodeWidgetPlacements(from: storedWidgetPlacements) ?? DefaultValues.widgetPlacements
        self.appWidgetDisplays = Self.decodeAppWidgetDisplays(from: storedAppWidgetDisplays) ?? DefaultValues.appWidgetDisplays
        self.trailingItems = Self.decodeTrailingItems(from: storedTrailingItems) ?? DefaultValues.trailingItems
        self.hasSeenDockEditorHint = storedHasSeenDockEditorHint ?? DefaultValues.hasSeenDockEditorHint

        // Load the user-override set, then run the one-shot migration
        // that infers overrides from existing UserDefaults presence.
        // After this runs once, the set is the authoritative source of
        // truth — appearance setters maintain it from then on.
        if let storedOverrideKeys = defaults.stringArray(forKey: Keys.userOverriddenAppearanceKeys) {
            self.userOverriddenAppearanceKeys = Set(storedOverrideKeys)
                .intersection(Self.appearanceKeys)
        }

        let migrationVersion = defaults.integer(forKey: Keys.appearanceOverrideMigrationVersion)
        if migrationVersion < 1 {
            // First launch with the override layer: treat any
            // appearance key that exists in UserDefaults as a user
            // override. Better to over-respect existing customizations
            // than to let a theme silently replace them.
            var seeded = self.userOverriddenAppearanceKeys
            for key in Self.appearanceKeys {
                if defaults.object(forKey: key) != nil {
                    seeded.insert(key)
                }
            }
            self.userOverriddenAppearanceKeys = seeded
            persistUserOverriddenAppearanceKeys()
            defaults.set(1, forKey: Keys.appearanceOverrideMigrationVersion)
        }
    }

    func applySystemDockVisibilityPreference() {
        if hidesSystemDock {
            SystemDockVisibilityService.shared.hide()
            syncSystemDockPositionIfNeeded()
        } else {
            SystemDockVisibilityService.shared.restore()
        }
    }

    func applyOpenAtLoginPreference() {
        guard !LaunchAtLoginService.shared.setEnabled(opensAtLogin) else {
            return
        }

        syncOpenAtLoginPreferenceFromSystem()
    }

    func enableOpenAtLoginOnFirstLaunchIfNeeded() {
        guard defaults.object(forKey: Keys.opensAtLogin) == nil else {
            return
        }

        opensAtLogin = true
    }

    /// Resets only the preferences exposed in Settings → Appearance
    /// (General, Indicators, Tile Layout, Window Shape, Window
    /// Background). App-icon overrides, behavior, widgets, launchpad,
    /// window-management, and system-dock settings are untouched —
    /// callers that want a full wipe should call `resetToDefaults()`
    /// instead.
    func resetAppearanceToDefaults() {
        // General
        disablesGlassLook = DefaultValues.disablesGlassLook

        // Indicators
        activeIndicatorShape = DefaultValues.activeIndicatorShape
        activeIndicatorImagePath = DefaultValues.activeIndicatorImagePath
        activeIndicatorColor = DefaultValues.activeIndicatorColor
        activeIndicatorOffset = DefaultValues.activeIndicatorOffset
        activeIndicatorScale = DefaultValues.activeIndicatorScale
        dividerImagePath = DefaultValues.dividerImagePath
        leftDividerImagePath = DefaultValues.leftDividerImagePath
        rightDividerImagePath = DefaultValues.rightDividerImagePath
        mirrorsLeftDividerOnRight = DefaultValues.mirrorsLeftDividerOnRight
        dividerPaddingFraction = DefaultValues.dividerPaddingFraction
        dividerOffset = DefaultValues.dividerOffset
        dividerImageScale = DefaultValues.dividerImageScale

        // Tile Layout (system tile size + magnification live on
        // DockSettingsService and aren't reset here)
        tileClipShape = DefaultValues.tileClipShape
        tileVerticalPadding = DefaultValues.tileVerticalPadding
        tileSpacing = DefaultValues.tileSpacing

        // Window Shape
        windowClipShape = DefaultValues.windowClipShape
        windowCornerRadius = DefaultValues.windowCornerRadius

        // Window Background
        windowBackgroundImagePath = DefaultValues.windowBackgroundImagePath
        windowBackgroundImageMode = DefaultValues.windowBackgroundImageMode
        windowTintColor = DefaultValues.windowTintColor
        windowTintOpacity = DefaultValues.windowTintOpacity

        // Clear all override flags so the active theme (if any) takes
        // over for these fields. The setters above re-mark whichever
        // keys ended up with a non-default value, but for non-Optional
        // fields setting back to the exact default doesn't trigger
        // `didSet` (the guard short-circuits), so any pre-existing
        // override flag would survive. Clearing them all here is the
        // simplest way to honor "reset" semantically.
        clearAllAppearanceOverrides()
    }

    func resetToDefaults() {
        tileVerticalPadding = DefaultValues.tileVerticalPadding
        tileSpacing = DefaultValues.tileSpacing
        tileClipShape = DefaultValues.tileClipShape
        windowCornerRadius = DefaultValues.windowCornerRadius
        windowClipShape = DefaultValues.windowClipShape
        windowTintColor = DefaultValues.windowTintColor
        windowTintOpacity = DefaultValues.windowTintOpacity
        disablesGlassLook = DefaultValues.disablesGlassLook
        windowBackgroundImagePath = DefaultValues.windowBackgroundImagePath
        windowBackgroundImageMode = DefaultValues.windowBackgroundImageMode
        windowPosition = DefaultValues.windowPosition
        windowDisplayTarget = DefaultValues.windowDisplayTarget
        windowSpaceBehavior = DefaultValues.windowSpaceBehavior
        autohidesWindow = DefaultValues.autohidesWindow
        opensAtLogin = DefaultValues.opensAtLogin
        autohideWindowDelay = DefaultValues.autohideWindowDelay
        fullscreenRevealDelay = DefaultValues.fullscreenRevealDelay
        windowPreviewHoverDelay = DefaultValues.windowPreviewHoverDelay
        windowPreviewLayout = DefaultValues.windowPreviewLayout
        maximizedWindowBehavior = DefaultValues.maximizedWindowBehavior
        hidesSystemDock = DefaultValues.hidesSystemDock
        overflowBehavior = DefaultValues.overflowBehavior
        windowAxisSizing = DefaultValues.windowAxisSizing
        enablesWidgetHoverPreview = DefaultValues.enablesWidgetHoverPreview
        widgetHoverPreviewSpans = DefaultValues.widgetHoverPreviewSpans
        widgetHoverPreviewDelay = DefaultValues.widgetHoverPreviewDelay
        showsActivePinnedSeparator = DefaultValues.showsActivePinnedSeparator
        showsRunningApps = DefaultValues.showsRunningApps
        showsMinimizedWindows = DefaultValues.showsMinimizedWindows
        hidesDuringFullscreen = DefaultValues.hidesDuringFullscreen
        enablesShelveMode = DefaultValues.enablesShelveMode
        hidesRecentApps = DefaultValues.hidesRecentApps
        appTileFrontmostClickBehavior = DefaultValues.appTileFrontmostClickBehavior
        activeIndicatorShape = DefaultValues.activeIndicatorShape
        activeIndicatorImagePath = DefaultValues.activeIndicatorImagePath
        activeIndicatorColor = DefaultValues.activeIndicatorColor
        dividerImagePath = DefaultValues.dividerImagePath
        leftDividerImagePath = DefaultValues.leftDividerImagePath
        rightDividerImagePath = DefaultValues.rightDividerImagePath
        mirrorsLeftDividerOnRight = DefaultValues.mirrorsLeftDividerOnRight
        activeIndicatorOffset = DefaultValues.activeIndicatorOffset
        activeIndicatorScale = DefaultValues.activeIndicatorScale
        dividerPaddingFraction = DefaultValues.dividerPaddingFraction
        dividerImageScale = DefaultValues.dividerImageScale
        dividerOffset = DefaultValues.dividerOffset
        appIconOverrides = DefaultValues.appIconOverrides
        trashIconOverrides = DefaultValues.trashIconOverrides
        folderIconOverrides = DefaultValues.folderIconOverrides
        launchpadIconPath = DefaultValues.launchpadIconPath
        launchpadIconPaddingFraction = DefaultValues.launchpadIconPaddingFraction
        hiddenAppBundleIdentifiers = DefaultValues.hiddenAppBundleIdentifiers
        showsGroupedOpenedAppsInDock = DefaultValues.showsGroupedOpenedAppsInDock
        showsGroupedOpenedAppsBackdrop = DefaultValues.showsGroupedOpenedAppsBackdrop
        enablesLaunchpadOverlay = DefaultValues.enablesLaunchpadOverlay
        launchpadOverlayTransparency = DefaultValues.launchpadOverlayTransparency
        launchpadGridColumnCount = DefaultValues.launchpadGridColumnCount
        launchpadGridRowCount = DefaultValues.launchpadGridRowCount
        launchpadShortcut = DefaultValues.launchpadShortcut
        enablesWindowSwitcher = DefaultValues.enablesWindowSwitcher
        windowSwitcherShortcut = DefaultValues.windowSwitcherShortcut
        showsWindowSwitcherFocusPreview = DefaultValues.showsWindowSwitcherFocusPreview
        windowSwitcherPreviewMode = DefaultValues.windowSwitcherPreviewMode
        windowSwitcherLayout = DefaultValues.windowSwitcherLayout
        appWidgetDisplays = DefaultValues.appWidgetDisplays
        hasSeenDockEditorHint = DefaultValues.hasSeenDockEditorHint
    }

    private func syncSystemDockPositionIfNeeded() {
        guard hidesSystemDock else { return }

        let orientation: DockSettingsService.Orientation
        switch windowPosition {
        case .system:
            return
        case .left:
            orientation = .left
        case .right:
            orientation = .right
        case .bottom:
            orientation = .bottom
        }

        SystemDockVisibilityService.shared.setOrientation(orientation)
    }

    private func syncOpenAtLoginPreferenceFromSystem() {
        let actualValue = LaunchAtLoginService.shared.isEnabled
        guard opensAtLogin != actualValue else {
            defaults.set(actualValue, forKey: Keys.opensAtLogin)
            return
        }

        isSyncingOpenAtLoginPreference = true
        opensAtLogin = actualValue
        isSyncingOpenAtLoginPreference = false
    }

    private func persistPinnedItems(_ items: [PinnedTileItem]) {
        guard let data = try? encoder.encode(items) else {
            defaults.removeObject(forKey: Keys.pinnedItems)
            return
        }

        defaults.set(data, forKey: Keys.pinnedItems)
    }

    private func persistWidgetPlacements(_ placements: [WidgetPlacement]) {
        guard let data = try? encoder.encode(placements) else {
            defaults.removeObject(forKey: Keys.widgetPlacements)
            return
        }

        defaults.set(data, forKey: Keys.widgetPlacements)
    }

    private func persistAppWidgetDisplays(_ displays: [AppWidgetDisplay]) {
        guard let data = try? encoder.encode(displays) else {
            defaults.removeObject(forKey: Keys.appWidgetDisplays)
            return
        }

        defaults.set(data, forKey: Keys.appWidgetDisplays)
    }

    private func persistTrailingItems(_ items: [TrailingTileItem]) {
        guard let data = try? encoder.encode(items) else {
            defaults.removeObject(forKey: Keys.trailingItems)
            return
        }

        defaults.set(data, forKey: Keys.trailingItems)
    }

    private func persistWindowTintColor(_ color: DockColor?) {
        guard let color else {
            defaults.removeObject(forKey: Keys.windowTintColor)
            return
        }

        guard let data = try? encoder.encode(color) else {
            defaults.removeObject(forKey: Keys.windowTintColor)
            return
        }

        defaults.set(data, forKey: Keys.windowTintColor)
    }

    private func persistActiveIndicatorColor(_ color: DockColor?) {
        guard let color else {
            defaults.removeObject(forKey: Keys.activeIndicatorColor)
            return
        }

        guard let data = try? encoder.encode(color) else {
            defaults.removeObject(forKey: Keys.activeIndicatorColor)
            return
        }

        defaults.set(data, forKey: Keys.activeIndicatorColor)
    }

    private func persistAppIconOverrides(_ overrides: [AppIconOverride]) {
        guard let data = try? encoder.encode(overrides) else {
            defaults.removeObject(forKey: Keys.appIconOverrides)
            return
        }

        defaults.set(data, forKey: Keys.appIconOverrides)
    }

    private func persistTrashIconOverrides(_ overrides: [TrashIconOverride]) {
        guard let data = try? encoder.encode(overrides) else {
            defaults.removeObject(forKey: Keys.trashIconOverrides)
            return
        }

        defaults.set(data, forKey: Keys.trashIconOverrides)
    }

    private func persistFolderIconOverrides(_ overrides: [FolderIconOverride]) {
        guard let data = try? encoder.encode(overrides) else {
            defaults.removeObject(forKey: Keys.folderIconOverrides)
            return
        }

        defaults.set(data, forKey: Keys.folderIconOverrides)
    }

    private func persistWindowSwitcherShortcut(_ shortcut: KeyboardShortcut) {
        guard let data = try? encoder.encode(shortcut) else {
            defaults.removeObject(forKey: Keys.windowSwitcherShortcut)
            return
        }

        defaults.set(data, forKey: Keys.windowSwitcherShortcut)
    }

    private func persistLaunchpadShortcut(_ shortcut: KeyboardShortcut) {
        guard let data = try? encoder.encode(shortcut) else {
            defaults.removeObject(forKey: Keys.launchpadShortcut)
            return
        }

        defaults.set(data, forKey: Keys.launchpadShortcut)
    }

    private static func decodeColor(from data: Data?) -> DockColor? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode(DockColor.self, from: data)
    }

    private static func decodeWidgetPlacements(from data: Data?) -> [WidgetPlacement]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([WidgetPlacement].self, from: data)
    }

    private static func decodeAppWidgetDisplays(from data: Data?) -> [AppWidgetDisplay]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([AppWidgetDisplay].self, from: data)
    }

    private static func decodeAppIconOverrides(from data: Data?) -> [AppIconOverride]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([AppIconOverride].self, from: data)
    }

    private static func decodeTrashIconOverrides(from data: Data?) -> [TrashIconOverride]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([TrashIconOverride].self, from: data)
    }

    private static func decodeFolderIconOverrides(from data: Data?) -> [FolderIconOverride]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([FolderIconOverride].self, from: data)
    }

    private static func decodeKeyboardShortcut(from data: Data?) -> KeyboardShortcut? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
    }

    private static func decodePinnedItems(from data: Data?) -> [PinnedTileItem]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([PinnedTileItem].self, from: data)
    }

    private static func decodeTrailingItems(from data: Data?) -> [TrailingTileItem]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([TrailingTileItem].self, from: data)
    }

    private static func normalizedBundleIdentifiers(_ bundleIdentifiers: [String]) -> [String] {
        Array(Set(bundleIdentifiers.filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
