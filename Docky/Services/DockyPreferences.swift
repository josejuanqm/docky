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
    case startMenu
    case widget
    case smartStack
    case spacer
    case flexibleSpacer
    case divider
}

enum TrailingTileItemKind: String, Codable, Equatable {
    case folder
    case trash
    case widget
    case smartStack
    case spacer
    case flexibleSpacer
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

    nonisolated static func startMenu(id: String = "custom:\(UUID().uuidString)") -> Self {
        Self(
            id: id,
            kind: .startMenu,
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

    nonisolated static func flexibleSpacer() -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .flexibleSpacer,
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

    nonisolated static func flexibleSpacer() -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .flexibleSpacer,
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
    case underline
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .dot: String(localized: "Dot")
        case .pill: String(localized: "Pill")
        case .underline: String(localized: "Underline")
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
    case fan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: String(localized: "Grid")
        case .list: String(localized: "List")
        case .inline: String(localized: "Inline")
        case .fan: String(localized: "Fan")
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
        case Self.fan.rawValue:
            self = .fan
        case Self.grid.rawValue:
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

enum LaunchpadLayoutAxis: String, CaseIterable, Codable, Identifiable {
    /// Apple's classic paged Launchpad: a fixed grid per page, scrolls
    /// horizontally one screenful at a time.
    case horizontal
    /// macOS Tahoe-style "Apps" view: a single continuous vertical
    /// grid that scrolls freely without page boundaries.
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal: String(localized: "Paged")
        case .vertical: String(localized: "Continuous")
        }
    }

    var summary: String {
        switch self {
        case .horizontal:
            String(localized: "Apple's classic Launchpad: pages of icons that swipe horizontally with a page indicator below.")
        case .vertical:
            String(localized: "macOS Tahoe-style Apps view: one tall scrollable grid with no page boundaries. Rows are unused.")
        }
    }

    /// Default for the current OS. macOS 26 (Tahoe) ships a vertical
    /// Apps view in place of paged Launchpad; older systems keep the
    /// paged layout so the upgrade isn't silently disruptive.
    static var defaultForCurrentOS: LaunchpadLayoutAxis {
        if #available(macOS 26.0, *) {
            return .vertical
        }
        return .horizontal
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
    /// user-overridden, better to over-respect existing customizations
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
        Keys.tileIconPadding,
        Keys.tileHoverOpacity,
        Keys.tileHoverScale,
        Keys.tileHoverBackgroundColor,
        Keys.tileHoverBackgroundImagePath,
        Keys.tileHoverBackgroundOpacity,
        Keys.tileHoverBackgroundCornerRadius,
        Keys.tileActiveBackgroundColor,
        Keys.tileActiveBackgroundImagePath,
        Keys.tileActiveBackgroundOpacity,
        Keys.tileActiveBackgroundCornerRadius,
        Keys.widget1xContentPadding,
        Keys.widget1xCornerRadius,
        Keys.widget2xContentPadding,
        Keys.widget2xCornerRadius,
        Keys.widget3xContentPadding,
        Keys.widget3xCornerRadius,
        Keys.widget4xContentPadding,
        Keys.widget4xCornerRadius,
        Keys.windowCornerRadius,
        Keys.windowCornerRadiusTopLeading,
        Keys.windowCornerRadiusTopTrailing,
        Keys.windowCornerRadiusBottomLeading,
        Keys.windowCornerRadiusBottomTrailing,
        Keys.windowContentInsetTop,
        Keys.windowContentInsetLeading,
        Keys.windowContentInsetBottom,
        Keys.windowContentInsetTrailing,
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
        Keys.dividerOpacity,
        Keys.dividerColor,
        Keys.windowBorderColor,
        Keys.windowBorderWidth,
        Keys.iconShadowColor,
        Keys.iconShadowRadius,
        Keys.iconShadowOpacity,
        Keys.showsActivePinnedSeparator,
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
    /// Internal (not fileprivate) so other services that own their own
    /// preference storage (e.g. `DockSettingsService` for tile size /
    /// magnification) can participate in the same override layer when a
    /// theme tries to provide a `behavior.*` value.
    func markAppearanceOverride(_ key: String) {
        guard !userOverriddenAppearanceKeys.contains(key) else { return }
        userOverriddenAppearanceKeys.insert(key)
        persistUserOverriddenAppearanceKeys()
    }

    /// Clears the override flag for a single appearance key. The
    /// stored value is left untouched, `effective<X>` simply starts
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

    /// Extra padding inside each tile around the icon, shrinks the
    /// rendered icon while leaving the tile bounds untouched.
    var tileIconPadding: CGFloat {
        didSet {
            guard tileIconPadding != oldValue else { return }
            defaults.set(Double(tileIconPadding), forKey: Keys.tileIconPadding)
            markAppearanceOverride(Keys.tileIconPadding)
        }
    }

    /// Optional tile-hover effects. Each property is nullable; if the
    /// user clears one (sets it back to its absent state) the override
    /// flag is cleared so the active theme can resume providing the
    /// value.
    var tileHoverOpacity: CGFloat? {
        didSet {
            guard tileHoverOpacity != oldValue else { return }
            persistOptionalDouble(tileHoverOpacity, forKey: Keys.tileHoverOpacity)
            if tileHoverOpacity == nil {
                clearAppearanceOverride(Keys.tileHoverOpacity)
            } else {
                markAppearanceOverride(Keys.tileHoverOpacity)
            }
        }
    }

    var tileHoverScale: CGFloat? {
        didSet {
            guard tileHoverScale != oldValue else { return }
            persistOptionalDouble(tileHoverScale, forKey: Keys.tileHoverScale)
            if tileHoverScale == nil {
                clearAppearanceOverride(Keys.tileHoverScale)
            } else {
                markAppearanceOverride(Keys.tileHoverScale)
            }
        }
    }

    var tileHoverBackgroundColor: DockColor? {
        didSet {
            guard tileHoverBackgroundColor != oldValue else { return }
            persistOptionalColor(tileHoverBackgroundColor, forKey: Keys.tileHoverBackgroundColor)
            if tileHoverBackgroundColor == nil {
                clearAppearanceOverride(Keys.tileHoverBackgroundColor)
            } else {
                markAppearanceOverride(Keys.tileHoverBackgroundColor)
            }
        }
    }

    var tileHoverBackgroundImagePath: String? {
        didSet {
            guard tileHoverBackgroundImagePath != oldValue else { return }
            if let path = tileHoverBackgroundImagePath, !path.isEmpty {
                defaults.set(path, forKey: Keys.tileHoverBackgroundImagePath)
                markAppearanceOverride(Keys.tileHoverBackgroundImagePath)
            } else {
                defaults.removeObject(forKey: Keys.tileHoverBackgroundImagePath)
                clearAppearanceOverride(Keys.tileHoverBackgroundImagePath)
            }
        }
    }

    var tileHoverBackgroundOpacity: CGFloat? {
        didSet {
            guard tileHoverBackgroundOpacity != oldValue else { return }
            persistOptionalDouble(tileHoverBackgroundOpacity, forKey: Keys.tileHoverBackgroundOpacity)
            if tileHoverBackgroundOpacity == nil {
                clearAppearanceOverride(Keys.tileHoverBackgroundOpacity)
            } else {
                markAppearanceOverride(Keys.tileHoverBackgroundOpacity)
            }
        }
    }

    var tileHoverBackgroundCornerRadius: CGFloat? {
        didSet {
            guard tileHoverBackgroundCornerRadius != oldValue else { return }
            persistOptionalDouble(tileHoverBackgroundCornerRadius, forKey: Keys.tileHoverBackgroundCornerRadius)
            if tileHoverBackgroundCornerRadius == nil {
                clearAppearanceOverride(Keys.tileHoverBackgroundCornerRadius)
            } else {
                markAppearanceOverride(Keys.tileHoverBackgroundCornerRadius)
            }
        }
    }

    /// Active-tile background, same surface as the hover background
    /// but painted under every running app tile, regardless of hover.
    /// Used together with the underline / dot / pill indicator for
    /// Windows-style "highlighted active app" looks.
    var tileActiveBackgroundColor: DockColor? {
        didSet {
            guard tileActiveBackgroundColor != oldValue else { return }
            persistOptionalColor(tileActiveBackgroundColor, forKey: Keys.tileActiveBackgroundColor)
            if tileActiveBackgroundColor == nil {
                clearAppearanceOverride(Keys.tileActiveBackgroundColor)
            } else {
                markAppearanceOverride(Keys.tileActiveBackgroundColor)
            }
        }
    }

    var tileActiveBackgroundImagePath: String? {
        didSet {
            guard tileActiveBackgroundImagePath != oldValue else { return }
            if let path = tileActiveBackgroundImagePath, !path.isEmpty {
                defaults.set(path, forKey: Keys.tileActiveBackgroundImagePath)
                markAppearanceOverride(Keys.tileActiveBackgroundImagePath)
            } else {
                defaults.removeObject(forKey: Keys.tileActiveBackgroundImagePath)
                clearAppearanceOverride(Keys.tileActiveBackgroundImagePath)
            }
        }
    }

    var tileActiveBackgroundOpacity: CGFloat? {
        didSet {
            guard tileActiveBackgroundOpacity != oldValue else { return }
            persistOptionalDouble(tileActiveBackgroundOpacity, forKey: Keys.tileActiveBackgroundOpacity)
            if tileActiveBackgroundOpacity == nil {
                clearAppearanceOverride(Keys.tileActiveBackgroundOpacity)
            } else {
                markAppearanceOverride(Keys.tileActiveBackgroundOpacity)
            }
        }
    }

    var tileActiveBackgroundCornerRadius: CGFloat? {
        didSet {
            guard tileActiveBackgroundCornerRadius != oldValue else { return }
            persistOptionalDouble(tileActiveBackgroundCornerRadius, forKey: Keys.tileActiveBackgroundCornerRadius)
            if tileActiveBackgroundCornerRadius == nil {
                clearAppearanceOverride(Keys.tileActiveBackgroundCornerRadius)
            } else {
                markAppearanceOverride(Keys.tileActiveBackgroundCornerRadius)
            }
        }
    }

    /// Per-span widget chrome overrides. Each property is `nil` by
    /// default; widgets at that span fall through to
    /// `nonAppContentPadding` / `nonAppTileCornerRadius` (the tile
    /// chrome inset + global clip-shape). Setting any of these
    /// lets a theme (or the user) tune individual rendering sizes ,
    /// e.g. 3x widgets with zero padding and zero corner radius for
    /// a Windows-style edge-to-edge look, without affecting 1x/2x.
    var widget1xContentPadding: CGFloat? {
        didSet {
            guard widget1xContentPadding != oldValue else { return }
            persistOptionalDouble(widget1xContentPadding, forKey: Keys.widget1xContentPadding)
            if widget1xContentPadding == nil {
                clearAppearanceOverride(Keys.widget1xContentPadding)
            } else {
                markAppearanceOverride(Keys.widget1xContentPadding)
            }
        }
    }

    var widget1xCornerRadius: CGFloat? {
        didSet {
            guard widget1xCornerRadius != oldValue else { return }
            persistOptionalDouble(widget1xCornerRadius, forKey: Keys.widget1xCornerRadius)
            if widget1xCornerRadius == nil {
                clearAppearanceOverride(Keys.widget1xCornerRadius)
            } else {
                markAppearanceOverride(Keys.widget1xCornerRadius)
            }
        }
    }

    var widget2xContentPadding: CGFloat? {
        didSet {
            guard widget2xContentPadding != oldValue else { return }
            persistOptionalDouble(widget2xContentPadding, forKey: Keys.widget2xContentPadding)
            if widget2xContentPadding == nil {
                clearAppearanceOverride(Keys.widget2xContentPadding)
            } else {
                markAppearanceOverride(Keys.widget2xContentPadding)
            }
        }
    }

    var widget2xCornerRadius: CGFloat? {
        didSet {
            guard widget2xCornerRadius != oldValue else { return }
            persistOptionalDouble(widget2xCornerRadius, forKey: Keys.widget2xCornerRadius)
            if widget2xCornerRadius == nil {
                clearAppearanceOverride(Keys.widget2xCornerRadius)
            } else {
                markAppearanceOverride(Keys.widget2xCornerRadius)
            }
        }
    }

    var widget3xContentPadding: CGFloat? {
        didSet {
            guard widget3xContentPadding != oldValue else { return }
            persistOptionalDouble(widget3xContentPadding, forKey: Keys.widget3xContentPadding)
            if widget3xContentPadding == nil {
                clearAppearanceOverride(Keys.widget3xContentPadding)
            } else {
                markAppearanceOverride(Keys.widget3xContentPadding)
            }
        }
    }

    var widget3xCornerRadius: CGFloat? {
        didSet {
            guard widget3xCornerRadius != oldValue else { return }
            persistOptionalDouble(widget3xCornerRadius, forKey: Keys.widget3xCornerRadius)
            if widget3xCornerRadius == nil {
                clearAppearanceOverride(Keys.widget3xCornerRadius)
            } else {
                markAppearanceOverride(Keys.widget3xCornerRadius)
            }
        }
    }

    var widget4xContentPadding: CGFloat? {
        didSet {
            guard widget4xContentPadding != oldValue else { return }
            persistOptionalDouble(widget4xContentPadding, forKey: Keys.widget4xContentPadding)
            if widget4xContentPadding == nil {
                clearAppearanceOverride(Keys.widget4xContentPadding)
            } else {
                markAppearanceOverride(Keys.widget4xContentPadding)
            }
        }
    }

    var widget4xCornerRadius: CGFloat? {
        didSet {
            guard widget4xCornerRadius != oldValue else { return }
            persistOptionalDouble(widget4xCornerRadius, forKey: Keys.widget4xCornerRadius)
            if widget4xCornerRadius == nil {
                clearAppearanceOverride(Keys.widget4xCornerRadius)
            } else {
                markAppearanceOverride(Keys.widget4xCornerRadius)
            }
        }
    }

    /// Resolves the effective content padding override for a widget
    /// rendered at the given span. Returns `nil` if neither the user
    /// nor the theme provided one, caller falls back to its own
    /// default (typically `nonAppContentPadding`).
    func effectiveWidgetContentPadding(for span: TileSpan) -> CGFloat? {
        let (userKey, userValue) = widgetContentPaddingPair(for: span)
        let themed = themedWidgetSpan(for: span)?.contentPadding
        if isAppearanceOverridden(userKey), let userValue {
            return max(0, userValue)
        }
        if let themed {
            return max(0, themed)
        }
        return nil
    }

    func effectiveWidgetCornerRadius(for span: TileSpan) -> CGFloat? {
        let (userKey, userValue) = widgetCornerRadiusPair(for: span)
        let themed = themedWidgetSpan(for: span)?.cornerRadius
        if isAppearanceOverridden(userKey), let userValue {
            return max(0, userValue)
        }
        if let themed {
            return max(0, themed)
        }
        return nil
    }

    private func widgetContentPaddingPair(for span: TileSpan) -> (String, CGFloat?) {
        switch span {
        case .one: (Keys.widget1xContentPadding, widget1xContentPadding)
        case .two: (Keys.widget2xContentPadding, widget2xContentPadding)
        case .three: (Keys.widget3xContentPadding, widget3xContentPadding)
        case .four: (Keys.widget4xContentPadding, widget4xContentPadding)
        }
    }

    private func widgetCornerRadiusPair(for span: TileSpan) -> (String, CGFloat?) {
        switch span {
        case .one: (Keys.widget1xCornerRadius, widget1xCornerRadius)
        case .two: (Keys.widget2xCornerRadius, widget2xCornerRadius)
        case .three: (Keys.widget3xCornerRadius, widget3xCornerRadius)
        case .four: (Keys.widget4xCornerRadius, widget4xCornerRadius)
        }
    }

    /// Theme-only flag (no user override surface). Returns `true` when
    /// the active theme says this span's widgets should ignore the
    /// theme-level tile icon padding.
    func effectiveWidgetIgnoresAddedPaddings(for span: TileSpan) -> Bool {
        themedWidgetSpan(for: span)?.ignoresAddedPaddings ?? false
    }

    private func themedWidgetSpan(for span: TileSpan) -> ThemeWidgetSpan? {
        let widgets = ThemeManager.shared.activeManifest?.appearance.widgets
        switch span {
        case .one: return widgets?.oneX
        case .two: return widgets?.twoX
        case .three: return widgets?.threeX
        case .four: return widgets?.fourX
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

    /// Per-corner overrides; `nil` inherits `windowCornerRadius`. Lets a
    /// theme keep only the screen-facing edge rounded (taskbar look).
    var windowCornerRadiusTopLeading: CGFloat? {
        didSet {
            guard windowCornerRadiusTopLeading != oldValue else { return }
            persistOptionalDouble(windowCornerRadiusTopLeading, forKey: Keys.windowCornerRadiusTopLeading)
            markAppearanceOverride(Keys.windowCornerRadiusTopLeading)
        }
    }

    var windowCornerRadiusTopTrailing: CGFloat? {
        didSet {
            guard windowCornerRadiusTopTrailing != oldValue else { return }
            persistOptionalDouble(windowCornerRadiusTopTrailing, forKey: Keys.windowCornerRadiusTopTrailing)
            markAppearanceOverride(Keys.windowCornerRadiusTopTrailing)
        }
    }

    var windowCornerRadiusBottomLeading: CGFloat? {
        didSet {
            guard windowCornerRadiusBottomLeading != oldValue else { return }
            persistOptionalDouble(windowCornerRadiusBottomLeading, forKey: Keys.windowCornerRadiusBottomLeading)
            markAppearanceOverride(Keys.windowCornerRadiusBottomLeading)
        }
    }

    var windowCornerRadiusBottomTrailing: CGFloat? {
        didSet {
            guard windowCornerRadiusBottomTrailing != oldValue else { return }
            persistOptionalDouble(windowCornerRadiusBottomTrailing, forKey: Keys.windowCornerRadiusBottomTrailing)
            markAppearanceOverride(Keys.windowCornerRadiusBottomTrailing)
        }
    }

    /// Per-edge padding between the dock panel and the chrome view.
    /// Defaults to 2pt; full-axis mode forces 0 at the
    /// `MainWindowContainerView` layer regardless of this setting.
    var windowContentInsetTop: CGFloat {
        didSet {
            guard windowContentInsetTop != oldValue else { return }
            defaults.set(Double(windowContentInsetTop), forKey: Keys.windowContentInsetTop)
            markAppearanceOverride(Keys.windowContentInsetTop)
        }
    }

    var windowContentInsetLeading: CGFloat {
        didSet {
            guard windowContentInsetLeading != oldValue else { return }
            defaults.set(Double(windowContentInsetLeading), forKey: Keys.windowContentInsetLeading)
            markAppearanceOverride(Keys.windowContentInsetLeading)
        }
    }

    var windowContentInsetBottom: CGFloat {
        didSet {
            guard windowContentInsetBottom != oldValue else { return }
            defaults.set(Double(windowContentInsetBottom), forKey: Keys.windowContentInsetBottom)
            markAppearanceOverride(Keys.windowContentInsetBottom)
        }
    }

    var windowContentInsetTrailing: CGFloat {
        didSet {
            guard windowContentInsetTrailing != oldValue else { return }
            defaults.set(Double(windowContentInsetTrailing), forKey: Keys.windowContentInsetTrailing)
            markAppearanceOverride(Keys.windowContentInsetTrailing)
        }
    }

    private func persistOptionalDouble(_ value: CGFloat?, forKey key: String) {
        if let value {
            defaults.set(Double(value), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
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

    /// Optional flat-color outline drawn around the dock chrome. When
    /// `nil` the chrome falls back to the default glass border (or no
    /// border when glass is disabled).
    var windowBorderColor: DockColor? {
        didSet {
            guard windowBorderColor != oldValue else { return }
            persistOptionalColor(windowBorderColor, forKey: Keys.windowBorderColor)
            if windowBorderColor == nil {
                clearAppearanceOverride(Keys.windowBorderColor)
            } else {
                markAppearanceOverride(Keys.windowBorderColor)
            }
        }
    }

    /// Stroke width applied to `windowBorderColor`. Ignored when the
    /// color is nil. Stored even when there's no color so the slider
    /// remembers its position between toggles.
    var windowBorderWidth: CGFloat {
        didSet {
            guard windowBorderWidth != oldValue else { return }
            defaults.set(Double(windowBorderWidth), forKey: Keys.windowBorderWidth)
            markAppearanceOverride(Keys.windowBorderWidth)
        }
    }

    /// Optional drop shadow color applied behind icon-bearing tiles.
    /// `nil` disables the shadow regardless of the radius/opacity
    /// values, those are kept around so the user's slider state
    /// persists across toggles.
    var iconShadowColor: DockColor? {
        didSet {
            guard iconShadowColor != oldValue else { return }
            persistOptionalColor(iconShadowColor, forKey: Keys.iconShadowColor)
            if iconShadowColor == nil {
                clearAppearanceOverride(Keys.iconShadowColor)
            } else {
                markAppearanceOverride(Keys.iconShadowColor)
            }
        }
    }

    /// Blur radius of the icon shadow in points.
    var iconShadowRadius: CGFloat {
        didSet {
            guard iconShadowRadius != oldValue else { return }
            defaults.set(Double(iconShadowRadius), forKey: Keys.iconShadowRadius)
            markAppearanceOverride(Keys.iconShadowRadius)
        }
    }

    /// Alpha multiplier applied to `iconShadowColor`. 1.0 = full
    /// strength, 0 = invisible. Multiplied with the color's own alpha
    /// at render time.
    var iconShadowOpacity: CGFloat {
        didSet {
            guard iconShadowOpacity != oldValue else { return }
            defaults.set(Double(iconShadowOpacity), forKey: Keys.iconShadowOpacity)
            markAppearanceOverride(Keys.iconShadowOpacity)
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
            markAppearanceOverride(Keys.windowAxisSizing)
        }
    }

    /// Theme-aware accessor. Falls through to the active theme's
    /// `behavior.windowAxisSizing` when the user hasn't picked a value
    /// of their own; otherwise returns the user's choice.
    var effectiveWindowAxisSizing: DockWindowAxisSizing {
        let themed = ThemeManager.shared.activeManifest?.behavior?.windowAxisSizing
            .flatMap(DockWindowAxisSizing.init(rawValue:))
        return appearanceOverride(
            Keys.windowAxisSizing,
            raw: windowAxisSizing,
            themed: themed
        )
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
            markAppearanceOverride(Keys.showsActivePinnedSeparator)
        }
    }

    /// Theme-aware accessor. Themes can suppress the pinned/active
    /// divider for taskbar-style layouts; user overrides win when set.
    var effectiveShowsActivePinnedSeparator: Bool {
        appearanceOverride(
            Keys.showsActivePinnedSeparator,
            raw: showsActivePinnedSeparator,
            themed: ThemeManager.shared.activeManifest?.behavior?.showsActivePinnedSeparator
        )
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
    /// Default true, matches the system Dock and what existed before this
    /// preference was added. Turning it off keeps Docky pinned over
    /// fullscreen apps.
    var hidesDuringFullscreen: Bool {
        didSet {
            guard hidesDuringFullscreen != oldValue else { return }
            defaults.set(hidesDuringFullscreen, forKey: Keys.hidesDuringFullscreen)
        }
    }

    /// Shelve mode: hides the Finder and/or Trash tiles so the dock
    /// reads as a pure shelf of pinned apps + widgets. The granular
    /// `shelveHidesFinder` / `shelveHidesTrash` prefs decide *which*
    /// fixtures disappear when this is on; both default to `true` for
    /// backward compatibility with the original boolean behavior.
    var enablesShelveMode: Bool {
        didSet {
            guard enablesShelveMode != oldValue else { return }
            defaults.set(enablesShelveMode, forKey: Keys.enablesShelveMode)
        }
    }

    /// While shelve mode is on, whether the Finder tile is suppressed.
    /// Has no effect when `enablesShelveMode` is `false`.
    var shelveHidesFinder: Bool {
        didSet {
            guard shelveHidesFinder != oldValue else { return }
            defaults.set(shelveHidesFinder, forKey: Keys.shelveHidesFinder)
        }
    }

    /// While shelve mode is on, whether the Trash tile is suppressed.
    var shelveHidesTrash: Bool {
        didSet {
            guard shelveHidesTrash != oldValue else { return }
            defaults.set(shelveHidesTrash, forKey: Keys.shelveHidesTrash)
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

    /// Hides the profile switcher strip even when more than one profile
    /// exists. When `false` (default), the strip still hides itself
    /// automatically while only the "Default" profile is around;
    /// `ProfileSwitcherWindowController` observes both this flag and
    /// the live profile count to drive show/hide.
    var hidesProfileStrip: Bool {
        didSet {
            guard hidesProfileStrip != oldValue else { return }
            defaults.set(hidesProfileStrip, forKey: Keys.hidesProfileStrip)
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

    /// Alpha multiplier applied to dividers. 1.0 = fully opaque, 0 = invisible.
    var dividerOpacity: CGFloat {
        didSet {
            guard dividerOpacity != oldValue else { return }
            defaults.set(dividerOpacity, forKey: Keys.dividerOpacity)
            markAppearanceOverride(Keys.dividerOpacity)
        }
    }

    /// Optional flat fill color used when no divider image is set.
    /// `nil` falls back to SwiftUI's hierarchical `.primary` so the
    /// divider tracks the system label color by default.
    var dividerColor: DockColor? {
        didSet {
            guard dividerColor != oldValue else { return }
            persistOptionalColor(dividerColor, forKey: Keys.dividerColor)
            if dividerColor == nil {
                clearAppearanceOverride(Keys.dividerColor)
            } else {
                markAppearanceOverride(Keys.dividerColor)
            }
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

    /// Optional image path used to replace the Start Menu tile's icon.
    var startMenuIconPath: String? {
        didSet {
            guard startMenuIconPath != oldValue else { return }

            if let startMenuIconPath, !startMenuIconPath.isEmpty {
                defaults.set(startMenuIconPath, forKey: Keys.startMenuIconPath)
            } else {
                defaults.removeObject(forKey: Keys.startMenuIconPath)
            }
        }
    }

    /// Optional padding fraction applied around the Start Menu override icon.
    var startMenuIconPaddingFraction: CGFloat? {
        didSet {
            guard startMenuIconPaddingFraction != oldValue else { return }

            if let startMenuIconPaddingFraction {
                defaults.set(Double(startMenuIconPaddingFraction), forKey: Keys.startMenuIconPaddingFraction)
            } else {
                defaults.removeObject(forKey: Keys.startMenuIconPaddingFraction)
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
            mirrorToActiveProfile { $0.hiddenAppBundleIdentifiers = normalizedIdentifiers }
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

    /// Whether Docky's Start menu overlay is enabled. Gates the tile
    /// click handler, the ⌃⌥S hotkey, and visibility of the Start menu
    /// widget in the dock editor palette.
    var enablesStartMenuOverlay: Bool {
        didSet {
            guard enablesStartMenuOverlay != oldValue else { return }
            defaults.set(enablesStartMenuOverlay, forKey: Keys.enablesStartMenuOverlay)
        }
    }

    /// When true, clicking the Finder tile opens the Start menu instead
    /// of activating Finder. Off by default so the Finder tile behaves
    /// like every other app tile unless the user opts in.
    var opensStartMenuFromFinderTile: Bool {
        didSet {
            guard opensStartMenuFromFinderTile != oldValue else { return }
            defaults.set(opensStartMenuFromFinderTile, forKey: Keys.opensStartMenuFromFinderTile)
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

    /// Icon edge length used by the Launchpad overlay at the 1440p
    /// reference height. Doubles as the upper bound (smaller displays
    /// scale down linearly from here; larger displays are clamped to
    /// this value). Range comes from `DefaultValues.launchpadBaseIconSize`
    /// bookends; the setter clamps so a corrupt stored value can't push
    /// the icon outside that range.
    var launchpadBaseIconSize: CGFloat {
        didSet {
            let clampedValue = min(
                max(launchpadBaseIconSize, DefaultValues.launchpadBaseIconSizeMin),
                DefaultValues.launchpadBaseIconSizeMax
            )
            guard clampedValue != oldValue else {
                if launchpadBaseIconSize != clampedValue {
                    launchpadBaseIconSize = clampedValue
                }
                return
            }

            if launchpadBaseIconSize != clampedValue {
                launchpadBaseIconSize = clampedValue
                return
            }

            defaults.set(Double(clampedValue), forKey: Keys.launchpadBaseIconSize)
        }
    }

    /// Horizontal gap between Launchpad cells at the reference height.
    /// Scaled down on smaller displays with the same screen-height
    /// factor as the icon. Clamped to the bookends below.
    var launchpadColumnSpacing: CGFloat {
        didSet {
            let clampedValue = min(
                max(launchpadColumnSpacing, DefaultValues.launchpadSpacingMin),
                DefaultValues.launchpadSpacingMax
            )
            guard clampedValue != oldValue else {
                if launchpadColumnSpacing != clampedValue {
                    launchpadColumnSpacing = clampedValue
                }
                return
            }

            if launchpadColumnSpacing != clampedValue {
                launchpadColumnSpacing = clampedValue
                return
            }

            defaults.set(Double(clampedValue), forKey: Keys.launchpadColumnSpacing)
        }
    }

    /// Scroll axis for the Launchpad overlay. `.horizontal` keeps the
    /// classic Apple paged layout; `.vertical` renders a single
    /// continuous grid (matches macOS Tahoe's Apps view). Row count is
    /// only consulted in horizontal mode.
    var launchpadLayoutAxis: LaunchpadLayoutAxis {
        didSet {
            guard launchpadLayoutAxis != oldValue else { return }
            defaults.set(launchpadLayoutAxis.rawValue, forKey: Keys.launchpadLayoutAxis)
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

    /// Single-key (no modifier — switcher's own modifier is already held)
    /// pressed inside the open switcher to minimize the selected window.
    var switcherMinimizeKeyCode: UInt16 {
        didSet {
            guard switcherMinimizeKeyCode != oldValue else { return }
            defaults.set(Int(switcherMinimizeKeyCode), forKey: Keys.switcherMinimizeKeyCode)
        }
    }

    /// Single-key pressed inside the open switcher to close the selected window.
    var switcherCloseKeyCode: UInt16 {
        didSet {
            guard switcherCloseKeyCode != oldValue else { return }
            defaults.set(Int(switcherCloseKeyCode), forKey: Keys.switcherCloseKeyCode)
        }
    }

    /// Single-key pressed inside the open switcher to zoom (green-button) the selected window.
    var switcherZoomKeyCode: UInt16 {
        didSet {
            guard switcherZoomKeyCode != oldValue else { return }
            defaults.set(Int(switcherZoomKeyCode), forKey: Keys.switcherZoomKeyCode)
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
            let snapshot = pinnedItems
            mirrorToActiveProfile { $0.pinnedItems = snapshot }

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
            let snapshot = widgetPlacements
            mirrorToActiveProfile { $0.widgetPlacements = snapshot }
        }
    }

    /// Optional widget substitutions for app tiles.
    var appWidgetDisplays: [AppWidgetDisplay] {
        didSet {
            guard appWidgetDisplays != oldValue else { return }
            persistAppWidgetDisplays(appWidgetDisplays)
            let snapshot = appWidgetDisplays
            mirrorToActiveProfile { $0.appWidgetDisplays = snapshot }
        }
    }

    /// Docky-owned ordered folder/trash section items.
    var trailingItems: [TrailingTileItem] {
        didSet {
            guard trailingItems != oldValue else { return }
            persistTrailingItems(trailingItems)
            let snapshot = trailingItems
            mirrorToActiveProfile { $0.trailingItems = snapshot }
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

    /// When `true`, tile-store didSet observers skip the push to
    /// `ProfileService`. Used by `applyProfile(_:)` so loading a profile
    /// doesn't immediately overwrite it with the values just loaded.
    private var isApplyingProfile = false

    /// Swap the active profile's tile-store fields into this preferences
    /// object. Each assignment fires its didSet — those still persist to
    /// the legacy top-level keys (which now act as a snapshot of the
    /// active profile) but skip mirroring back to `ProfileService` while
    /// `isApplyingProfile` is set.
    func applyProfile(_ profile: DockProfile) {
        isApplyingProfile = true
        defer { isApplyingProfile = false }
        pinnedItems = profile.pinnedItems
        trailingItems = profile.trailingItems
        widgetPlacements = profile.widgetPlacements
        appWidgetDisplays = profile.appWidgetDisplays
        hiddenAppBundleIdentifiers = profile.hiddenAppBundleIdentifiers
    }

    /// Mirror a tile-store edit to the active profile so it survives the
    /// next profile switch. No-op while a profile is being applied.
    fileprivate func mirrorToActiveProfile(_ mutate: @escaping (inout DockProfile) -> Void) {
        guard !isApplyingProfile else { return }
        ProfileService.shared.updateActiveProfile(mutate)
    }

    // MARK: - Effective appearance values (theme override layer)
    //
    // Each `effective<X>` accessor returns `userValue` when
    // `isAppearanceOverridden(Keys.X)` is true, otherwise falls
    // through to the active theme's manifest value (if any), then
    // finally to the raw stored value (which is initialized to the
    // built-in default when the key isn't in UserDefaults).
    //
    // Consumers in `Views/` should read `effective<X>` rather than
    // the raw stored property. Settings UI is the exception, its
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

    var effectiveTileIconPadding: CGFloat {
        let resolved = appearanceOverride(
            Keys.tileIconPadding,
            raw: tileIconPadding,
            themed: ThemeManager.shared.activeManifest?.appearance.tile?.iconPadding
        )
        return max(0, resolved)
    }

    /// Hover opacity multiplier; 1.0 when no theme/user value is set.
    var effectiveTileHoverOpacity: CGFloat {
        let themed = ThemeManager.shared.activeManifest?.appearance.tile?.hover?.opacity
        if isAppearanceOverridden(Keys.tileHoverOpacity), let user = tileHoverOpacity {
            return max(0, min(1, user))
        }
        if let themed {
            return max(0, min(1, themed))
        }
        return 1
    }

    /// Hover scale; 1.0 when no theme/user value is set.
    var effectiveTileHoverScale: CGFloat {
        let themed = ThemeManager.shared.activeManifest?.appearance.tile?.hover?.scale
        if isAppearanceOverridden(Keys.tileHoverScale), let user = tileHoverScale {
            return max(0.1, user)
        }
        if let themed {
            return max(0.1, themed)
        }
        return 1
    }

    var effectiveTileHoverBackgroundColor: NSColor? {
        if isAppearanceOverridden(Keys.tileHoverBackgroundColor), let user = tileHoverBackgroundColor {
            return user.nsColor
        }
        if let themed = ThemeManager.shared.activeManifest?.appearance.tile?.hover?.backgroundColor,
           let resolved = themed.nsColor {
            return resolved
        }
        return nil
    }

    var effectiveTileHoverBackgroundImageURL: URL? {
        if isAppearanceOverridden(Keys.tileHoverBackgroundImagePath),
           let path = tileHoverBackgroundImagePath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let assetPath = ThemeManager.shared.activeManifest?.appearance.tile?.hover?.backgroundImage,
           let url = ThemeManager.shared.activeAssetURL(assetPath) {
            return url
        }
        return nil
    }

    var effectiveTileHoverBackgroundOpacity: CGFloat {
        let themed = ThemeManager.shared.activeManifest?.appearance.tile?.hover?.backgroundOpacity
        if isAppearanceOverridden(Keys.tileHoverBackgroundOpacity), let user = tileHoverBackgroundOpacity {
            return max(0, min(1, user))
        }
        if let themed {
            return max(0, min(1, themed))
        }
        return 1
    }

    var effectiveTileHoverBackgroundCornerRadius: CGFloat {
        let themed = ThemeManager.shared.activeManifest?.appearance.tile?.hover?.backgroundCornerRadius
        if isAppearanceOverridden(Keys.tileHoverBackgroundCornerRadius), let user = tileHoverBackgroundCornerRadius {
            return max(0, user)
        }
        if let themed {
            return max(0, themed)
        }
        return 0
    }

    var effectiveTileActiveBackgroundColor: NSColor? {
        if isAppearanceOverridden(Keys.tileActiveBackgroundColor), let user = tileActiveBackgroundColor {
            return user.nsColor
        }
        if let themed = ThemeManager.shared.activeManifest?.appearance.tile?.active?.backgroundColor,
           let resolved = themed.nsColor {
            return resolved
        }
        return nil
    }

    var effectiveTileActiveBackgroundImageURL: URL? {
        if isAppearanceOverridden(Keys.tileActiveBackgroundImagePath),
           let path = tileActiveBackgroundImagePath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let assetPath = ThemeManager.shared.activeManifest?.appearance.tile?.active?.backgroundImage,
           let url = ThemeManager.shared.activeAssetURL(assetPath) {
            return url
        }
        return nil
    }

    var effectiveTileActiveBackgroundOpacity: CGFloat {
        let themed = ThemeManager.shared.activeManifest?.appearance.tile?.active?.backgroundOpacity
        if isAppearanceOverridden(Keys.tileActiveBackgroundOpacity), let user = tileActiveBackgroundOpacity {
            return max(0, min(1, user))
        }
        if let themed {
            return max(0, min(1, themed))
        }
        return 1
    }

    var effectiveTileActiveBackgroundCornerRadius: CGFloat {
        let themed = ThemeManager.shared.activeManifest?.appearance.tile?.active?.backgroundCornerRadius
        if isAppearanceOverridden(Keys.tileActiveBackgroundCornerRadius), let user = tileActiveBackgroundCornerRadius {
            return max(0, user)
        }
        if let themed {
            return max(0, themed)
        }
        return 0
    }

    var effectiveWindowCornerRadius: CGFloat {
        appearanceOverride(
            Keys.windowCornerRadius,
            raw: windowCornerRadius,
            themed: ThemeManager.shared.activeManifest?.appearance.window?.cornerRadius
        )
    }

    /// Resolves a single corner's radius. Layered the same as every
    /// other appearance value (user override > theme value > fallback),
    /// with the *fallback* being the uniform `effectiveWindowCornerRadius`
    /// rather than a hardcoded default, so a theme that only specifies
    /// e.g. `bottomLeading: 0` flattens just that corner and leaves the
    /// rest at the uniform value.
    private func effectiveCornerRadius(
        userKey: String,
        userValue: CGFloat?,
        themed: CGFloat?
    ) -> CGFloat {
        if isAppearanceOverridden(userKey), let userValue {
            return max(0, userValue)
        }
        if let themed {
            return max(0, themed)
        }
        return effectiveWindowCornerRadius
    }

    var effectiveWindowCornerRadiusTopLeading: CGFloat {
        effectiveCornerRadius(
            userKey: Keys.windowCornerRadiusTopLeading,
            userValue: windowCornerRadiusTopLeading,
            themed: ThemeManager.shared.activeManifest?.appearance.window?.cornerRadii?.topLeading
        )
    }

    var effectiveWindowCornerRadiusTopTrailing: CGFloat {
        effectiveCornerRadius(
            userKey: Keys.windowCornerRadiusTopTrailing,
            userValue: windowCornerRadiusTopTrailing,
            themed: ThemeManager.shared.activeManifest?.appearance.window?.cornerRadii?.topTrailing
        )
    }

    var effectiveWindowCornerRadiusBottomLeading: CGFloat {
        effectiveCornerRadius(
            userKey: Keys.windowCornerRadiusBottomLeading,
            userValue: windowCornerRadiusBottomLeading,
            themed: ThemeManager.shared.activeManifest?.appearance.window?.cornerRadii?.bottomLeading
        )
    }

    var effectiveWindowCornerRadiusBottomTrailing: CGFloat {
        effectiveCornerRadius(
            userKey: Keys.windowCornerRadiusBottomTrailing,
            userValue: windowCornerRadiusBottomTrailing,
            themed: ThemeManager.shared.activeManifest?.appearance.window?.cornerRadii?.bottomTrailing
        )
    }

    var effectiveWindowContentInsetTop: CGFloat {
        appearanceOverride(
            Keys.windowContentInsetTop,
            raw: windowContentInsetTop,
            themed: ThemeManager.shared.activeManifest?.appearance.window?.contentInsets?.top
        )
    }

    var effectiveWindowContentInsetLeading: CGFloat {
        appearanceOverride(
            Keys.windowContentInsetLeading,
            raw: windowContentInsetLeading,
            themed: ThemeManager.shared.activeManifest?.appearance.window?.contentInsets?.leading
        )
    }

    var effectiveWindowContentInsetBottom: CGFloat {
        appearanceOverride(
            Keys.windowContentInsetBottom,
            raw: windowContentInsetBottom,
            themed: ThemeManager.shared.activeManifest?.appearance.window?.contentInsets?.bottom
        )
    }

    var effectiveWindowContentInsetTrailing: CGFloat {
        appearanceOverride(
            Keys.windowContentInsetTrailing,
            raw: windowContentInsetTrailing,
            themed: ThemeManager.shared.activeManifest?.appearance.window?.contentInsets?.trailing
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
        if let themed = ThemeManager.shared.activeManifest?.appearance.window?.tintColor,
           let resolved = themed.nsColor {
            return resolved
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

    /// Theme-aware border color. `nil` means no theme-supplied border
    /// is set; callers should fall back to the default glass treatment.
    var effectiveWindowBorderColor: NSColor? {
        if isAppearanceOverridden(Keys.windowBorderColor), let user = windowBorderColor {
            return user.nsColor
        }
        if let themed = ThemeManager.shared.activeManifest?.appearance.window?.borderColor,
           let resolved = themed.nsColor {
            return resolved
        }
        return nil
    }

    var effectiveWindowBorderWidth: CGFloat {
        appearanceOverride(
            Keys.windowBorderWidth,
            raw: windowBorderWidth,
            themed: ThemeManager.shared.activeManifest?.appearance.window?.borderWidth
        )
    }

    /// Theme-aware icon shadow color. `nil` disables the shadow.
    var effectiveIconShadowColor: NSColor? {
        if isAppearanceOverridden(Keys.iconShadowColor), let user = iconShadowColor {
            return user.nsColor
        }
        if let themed = ThemeManager.shared.activeManifest?.appearance.iconShadow?.color,
           let resolved = themed.nsColor {
            return resolved
        }
        return nil
    }

    var effectiveIconShadowRadius: CGFloat {
        appearanceOverride(
            Keys.iconShadowRadius,
            raw: iconShadowRadius,
            themed: ThemeManager.shared.activeManifest?.appearance.iconShadow?.radius
        )
    }

    var effectiveIconShadowOpacity: CGFloat {
        let raw = appearanceOverride(
            Keys.iconShadowOpacity,
            raw: iconShadowOpacity,
            themed: ThemeManager.shared.activeManifest?.appearance.iconShadow?.opacity
        )
        return min(max(raw, 0), 1)
    }

    /// Theme-aware flat divider fill. `nil` means the divider should
    /// fall back to SwiftUI's `.primary`.
    var effectiveDividerColor: NSColor? {
        if isAppearanceOverridden(Keys.dividerColor), let user = dividerColor {
            return user.nsColor
        }
        if let themed = ThemeManager.shared.activeManifest?.appearance.indicators?.divider?.color,
           let resolved = themed.nsColor {
            return resolved
        }
        return nil
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
        if let themed = ThemeManager.shared.activeManifest?.appearance.indicators?.color,
           let resolved = themed.nsColor {
            return resolved
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

    var effectiveDividerOpacity: CGFloat {
        appearanceOverride(
            Keys.dividerOpacity,
            raw: dividerOpacity,
            themed: ThemeManager.shared.activeManifest?.appearance.indicators?.divider?.opacity
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
    // Returns the color when it comes from a deliberate source ,
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

    var explicitWindowBorderColor: ThemeColor? {
        if isAppearanceOverridden(Keys.windowBorderColor), let user = windowBorderColor {
            return ThemeColor(r: user.red, g: user.green, b: user.blue)
        }
        if let themed = ThemeManager.shared.activeManifest?.appearance.window?.borderColor {
            return themed
        }
        return nil
    }

    var explicitIconShadowColor: ThemeColor? {
        if isAppearanceOverridden(Keys.iconShadowColor), let user = iconShadowColor {
            return ThemeColor(r: user.red, g: user.green, b: user.blue)
        }
        if let themed = ThemeManager.shared.activeManifest?.appearance.iconShadow?.color {
            return themed
        }
        return nil
    }

    var explicitDividerColor: ThemeColor? {
        if isAppearanceOverridden(Keys.dividerColor), let user = dividerColor {
            return ThemeColor(r: user.red, g: user.green, b: user.blue)
        }
        if let themed = ThemeManager.shared.activeManifest?.appearance.indicators?.divider?.color {
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
        // `customAppIcons` flag, consistent with how other
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
    /// app has no override yet, callers should set an icon first.
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

    var effectiveStartMenuIconOverrideURL: URL? {
        guard ProductService.shared.isUnlocked(.customAppIcons) else {
            return nil
        }
        guard let path = startMenuIconPath, !path.isEmpty else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    var effectiveStartMenuIconOverridePadding: CGFloat {
        guard effectiveStartMenuIconOverrideURL != nil else { return 0 }
        return startMenuIconPaddingFraction ?? 0
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
        // hidden-apps list would be a confusing no-op, refuse it.
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
        static let tileIconPadding = "docky.tileIconPadding"
        static let tileHoverOpacity = "docky.tileHoverOpacity"
        static let tileHoverScale = "docky.tileHoverScale"
        static let tileHoverBackgroundColor = "docky.tileHoverBackgroundColor"
        static let tileHoverBackgroundImagePath = "docky.tileHoverBackgroundImagePath"
        static let tileHoverBackgroundOpacity = "docky.tileHoverBackgroundOpacity"
        static let tileHoverBackgroundCornerRadius = "docky.tileHoverBackgroundCornerRadius"
        static let tileActiveBackgroundColor = "docky.tileActiveBackgroundColor"
        static let tileActiveBackgroundImagePath = "docky.tileActiveBackgroundImagePath"
        static let tileActiveBackgroundOpacity = "docky.tileActiveBackgroundOpacity"
        static let tileActiveBackgroundCornerRadius = "docky.tileActiveBackgroundCornerRadius"
        static let widget1xContentPadding = "docky.widget1xContentPadding"
        static let widget1xCornerRadius = "docky.widget1xCornerRadius"
        static let widget2xContentPadding = "docky.widget2xContentPadding"
        static let widget2xCornerRadius = "docky.widget2xCornerRadius"
        static let widget3xContentPadding = "docky.widget3xContentPadding"
        static let widget3xCornerRadius = "docky.widget3xCornerRadius"
        static let widget4xContentPadding = "docky.widget4xContentPadding"
        static let widget4xCornerRadius = "docky.widget4xCornerRadius"
        static let windowCornerRadius = "docky.windowCornerRadius"
        static let windowCornerRadiusTopLeading = "docky.windowCornerRadiusTopLeading"
        static let windowCornerRadiusTopTrailing = "docky.windowCornerRadiusTopTrailing"
        static let windowCornerRadiusBottomLeading = "docky.windowCornerRadiusBottomLeading"
        static let windowCornerRadiusBottomTrailing = "docky.windowCornerRadiusBottomTrailing"
        static let windowContentInsetTop = "docky.windowContentInsetTop"
        static let windowContentInsetLeading = "docky.windowContentInsetLeading"
        static let windowContentInsetBottom = "docky.windowContentInsetBottom"
        static let windowContentInsetTrailing = "docky.windowContentInsetTrailing"
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
        static let shelveHidesFinder = "docky.shelveHidesFinder"
        static let shelveHidesTrash = "docky.shelveHidesTrash"
        static let hidesRecentApps = "docky.hidesRecentApps"
        static let hidesProfileStrip = "docky.hidesProfileStrip"
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
        static let dividerOpacity = "docky.dividerOpacity"
        static let dividerColor = "docky.dividerColor"
        static let windowBorderColor = "docky.windowBorderColor"
        static let windowBorderWidth = "docky.windowBorderWidth"
        static let iconShadowColor = "docky.iconShadowColor"
        static let iconShadowRadius = "docky.iconShadowRadius"
        static let iconShadowOpacity = "docky.iconShadowOpacity"
        static let appIconOverrides = "docky.appIconOverrides"
        static let trashIconOverrides = "docky.trashIconOverrides"
        static let folderIconOverrides = "docky.folderIconOverrides"
        static let launchpadIconPath = "docky.launchpadIconPath"
        static let launchpadIconPaddingFraction = "docky.launchpadIconPaddingFraction"
        static let startMenuIconPath = "docky.startMenuIconPath"
        static let startMenuIconPaddingFraction = "docky.startMenuIconPaddingFraction"
        static let hiddenAppBundleIdentifiers = "docky.hiddenAppBundleIdentifiers"
        static let showsGroupedOpenedAppsInDock = "docky.showsGroupedOpenedAppsInDock"
        static let showsGroupedOpenedAppsBackdrop = "docky.showsGroupedOpenedAppsBackdrop"
        static let enablesLaunchpadOverlay = "docky.enablesLaunchpadOverlay"
        static let enablesStartMenuOverlay = "docky.enablesStartMenuOverlay"
        static let opensStartMenuFromFinderTile = "docky.opensStartMenuFromFinderTile"
        static let launchpadOverlayTransparency = "docky.launchpadOverlayTransparency"
        static let launchpadGridColumnCount = "docky.launchpadGridColumnCount"
        static let launchpadGridRowCount = "docky.launchpadGridRowCount"
        static let launchpadBaseIconSize = "docky.launchpadBaseIconSize"
        static let launchpadColumnSpacing = "docky.launchpadColumnSpacing"
        static let launchpadLayoutAxis = "docky.launchpadLayoutAxis"
        static let launchpadShortcut = "docky.launchpadShortcut"
        static let enablesWindowSwitcher = "docky.enablesWindowSwitcher"
        static let windowSwitcherShortcut = "docky.windowSwitcherShortcut"
        static let showsWindowSwitcherFocusPreview = "docky.showsWindowSwitcherFocusPreview"
        static let windowSwitcherPreviewMode = "docky.windowSwitcherPreviewMode"
        static let windowSwitcherLayout = "docky.windowSwitcherLayout"
        static let switcherMinimizeKeyCode = "docky.switcherMinimizeKeyCode"
        static let switcherCloseKeyCode = "docky.switcherCloseKeyCode"
        static let switcherZoomKeyCode = "docky.switcherZoomKeyCode"
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
        static let tileIconPadding: CGFloat = 0
        static let tileHoverOptional: CGFloat? = nil
        static let tileHoverBackgroundColor: DockColor? = nil
        static let tileHoverBackgroundImagePath: String? = nil
        static let windowCornerRadius: CGFloat = 24
        static let windowCornerRadiusPerCorner: CGFloat? = nil
        static let windowContentInset: CGFloat = 2
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
        static let shelveHidesFinder = true
        static let shelveHidesTrash = true
        static let hidesRecentApps = false
        static let hidesProfileStrip = false
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
        static let dividerOpacity: CGFloat = 1
        static let dividerColor: DockColor? = nil
        static let windowBorderColor: DockColor? = nil
        static let windowBorderWidth: CGFloat = 1
        static let iconShadowColor: DockColor? = nil
        static let iconShadowRadius: CGFloat = 4
        static let iconShadowOpacity: CGFloat = 0.5
        static let appIconOverrides: [AppIconOverride] = []
        static let trashIconOverrides: [TrashIconOverride] = []
        static let folderIconOverrides: [FolderIconOverride] = []
        static let launchpadIconPath: String? = nil
        static let launchpadIconPaddingFraction: CGFloat? = nil
        static let startMenuIconPath: String? = nil
        static let startMenuIconPaddingFraction: CGFloat? = nil
        static let hiddenAppBundleIdentifiers: [String] = []
        static let showsGroupedOpenedAppsInDock = true
        static let showsGroupedOpenedAppsBackdrop = true
        static let enablesLaunchpadOverlay = true
        static let enablesStartMenuOverlay = true
        static let opensStartMenuFromFinderTile = false
        static let launchpadOverlayTransparency: CGFloat = 0.75
        static let launchpadGridColumnCount = 7
        static let launchpadGridRowCount = 5
        static let launchpadBaseIconSize: CGFloat = 128
        static let launchpadBaseIconSizeMin: CGFloat = 48
        static let launchpadBaseIconSizeMax: CGFloat = 192
        static let launchpadColumnSpacing: CGFloat = 96
        static let launchpadSpacingMin: CGFloat = 0
        static let launchpadSpacingMax: CGFloat = 96
        static let launchpadLayoutAxis: LaunchpadLayoutAxis = .defaultForCurrentOS
        static let launchpadShortcut = KeyboardShortcut.empty
        static let enablesWindowSwitcher = true
        static let windowSwitcherShortcut = KeyboardShortcut(keyCode: 48, modifierFlags: [.option])
        static let showsWindowSwitcherFocusPreview = true
        static let windowSwitcherPreviewMode: WindowSwitcherPreviewMode = .inPlace
        static let windowSwitcherLayout: WindowSwitcherLayout = .auto
        static let switcherMinimizeKeyCode: UInt16 = 46
        static let switcherCloseKeyCode: UInt16 = 13
        static let switcherZoomKeyCode: UInt16 = 6
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
        let storedTileIconPadding = defaults.object(forKey: Keys.tileIconPadding) as? Double
        let storedTileHoverOpacity = defaults.object(forKey: Keys.tileHoverOpacity) as? Double
        let storedTileHoverScale = defaults.object(forKey: Keys.tileHoverScale) as? Double
        let storedTileHoverBackgroundColor = defaults.data(forKey: Keys.tileHoverBackgroundColor)
        let storedTileHoverBackgroundImagePath = defaults.string(forKey: Keys.tileHoverBackgroundImagePath)
        let storedTileHoverBackgroundOpacity = defaults.object(forKey: Keys.tileHoverBackgroundOpacity) as? Double
        let storedTileHoverBackgroundCornerRadius = defaults.object(forKey: Keys.tileHoverBackgroundCornerRadius) as? Double
        let storedTileActiveBackgroundColor = defaults.data(forKey: Keys.tileActiveBackgroundColor)
        let storedTileActiveBackgroundImagePath = defaults.string(forKey: Keys.tileActiveBackgroundImagePath)
        let storedTileActiveBackgroundOpacity = defaults.object(forKey: Keys.tileActiveBackgroundOpacity) as? Double
        let storedTileActiveBackgroundCornerRadius = defaults.object(forKey: Keys.tileActiveBackgroundCornerRadius) as? Double
        let storedWidget1xContentPadding = defaults.object(forKey: Keys.widget1xContentPadding) as? Double
        let storedWidget1xCornerRadius = defaults.object(forKey: Keys.widget1xCornerRadius) as? Double
        let storedWidget2xContentPadding = defaults.object(forKey: Keys.widget2xContentPadding) as? Double
        let storedWidget2xCornerRadius = defaults.object(forKey: Keys.widget2xCornerRadius) as? Double
        let storedWidget3xContentPadding = defaults.object(forKey: Keys.widget3xContentPadding) as? Double
        let storedWidget3xCornerRadius = defaults.object(forKey: Keys.widget3xCornerRadius) as? Double
        let storedWidget4xContentPadding = defaults.object(forKey: Keys.widget4xContentPadding) as? Double
        let storedWidget4xCornerRadius = defaults.object(forKey: Keys.widget4xCornerRadius) as? Double
        let storedWindowCornerRadius = defaults.object(forKey: Keys.windowCornerRadius) as? Double
        let storedWindowCornerRadiusTopLeading = defaults.object(forKey: Keys.windowCornerRadiusTopLeading) as? Double
        let storedWindowCornerRadiusTopTrailing = defaults.object(forKey: Keys.windowCornerRadiusTopTrailing) as? Double
        let storedWindowCornerRadiusBottomLeading = defaults.object(forKey: Keys.windowCornerRadiusBottomLeading) as? Double
        let storedWindowCornerRadiusBottomTrailing = defaults.object(forKey: Keys.windowCornerRadiusBottomTrailing) as? Double
        let storedWindowContentInsetTop = defaults.object(forKey: Keys.windowContentInsetTop) as? Double
        let storedWindowContentInsetLeading = defaults.object(forKey: Keys.windowContentInsetLeading) as? Double
        let storedWindowContentInsetBottom = defaults.object(forKey: Keys.windowContentInsetBottom) as? Double
        let storedWindowContentInsetTrailing = defaults.object(forKey: Keys.windowContentInsetTrailing) as? Double
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
        let storedShelveHidesFinder = defaults.object(forKey: Keys.shelveHidesFinder) as? Bool
        let storedShelveHidesTrash = defaults.object(forKey: Keys.shelveHidesTrash) as? Bool
        let storedHidesRecentApps = defaults.object(forKey: Keys.hidesRecentApps) as? Bool
        let storedHidesProfileStrip = defaults.object(forKey: Keys.hidesProfileStrip) as? Bool
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
        let storedDividerOpacity = defaults.object(forKey: Keys.dividerOpacity) as? Double
        let storedDividerColor = defaults.data(forKey: Keys.dividerColor)
        let storedWindowBorderColor = defaults.data(forKey: Keys.windowBorderColor)
        let storedWindowBorderWidth = defaults.object(forKey: Keys.windowBorderWidth) as? Double
        let storedIconShadowColor = defaults.data(forKey: Keys.iconShadowColor)
        let storedIconShadowRadius = defaults.object(forKey: Keys.iconShadowRadius) as? Double
        let storedIconShadowOpacity = defaults.object(forKey: Keys.iconShadowOpacity) as? Double
        let storedAppIconOverrides = defaults.data(forKey: Keys.appIconOverrides)
        let storedTrashIconOverrides = defaults.data(forKey: Keys.trashIconOverrides)
        let storedFolderIconOverrides = defaults.data(forKey: Keys.folderIconOverrides)
        let storedLaunchpadIconPath = defaults.string(forKey: Keys.launchpadIconPath)
        let storedLaunchpadIconPaddingFraction = defaults.object(forKey: Keys.launchpadIconPaddingFraction) as? Double
        let storedStartMenuIconPath = defaults.string(forKey: Keys.startMenuIconPath)
        let storedStartMenuIconPaddingFraction = defaults.object(forKey: Keys.startMenuIconPaddingFraction) as? Double
        let storedHiddenAppBundleIdentifiers = defaults.stringArray(forKey: Keys.hiddenAppBundleIdentifiers)
        let storedShowsGroupedOpenedAppsInDock = defaults.object(forKey: Keys.showsGroupedOpenedAppsInDock) as? Bool
        let storedShowsGroupedOpenedAppsBackdrop = defaults.object(forKey: Keys.showsGroupedOpenedAppsBackdrop) as? Bool
        let storedEnablesLaunchpadOverlay = defaults.object(forKey: Keys.enablesLaunchpadOverlay) as? Bool
        let storedEnablesStartMenuOverlay = defaults.object(forKey: Keys.enablesStartMenuOverlay) as? Bool
        let storedOpensStartMenuFromFinderTile = defaults.object(forKey: Keys.opensStartMenuFromFinderTile) as? Bool
        let storedLaunchpadOverlayTransparency = defaults.object(forKey: Keys.launchpadOverlayTransparency) as? Double
        let storedLaunchpadGridColumnCount = defaults.object(forKey: Keys.launchpadGridColumnCount) as? Int
        let storedLaunchpadGridRowCount = defaults.object(forKey: Keys.launchpadGridRowCount) as? Int
        let storedLaunchpadBaseIconSize = defaults.object(forKey: Keys.launchpadBaseIconSize) as? Double
        let storedLaunchpadColumnSpacing = defaults.object(forKey: Keys.launchpadColumnSpacing) as? Double
        let storedLaunchpadLayoutAxis = defaults.string(forKey: Keys.launchpadLayoutAxis)
        let storedLaunchpadShortcut = defaults.data(forKey: Keys.launchpadShortcut)
        let storedEnablesWindowSwitcher = defaults.object(forKey: Keys.enablesWindowSwitcher) as? Bool
        let storedWindowSwitcherShortcut = defaults.data(forKey: Keys.windowSwitcherShortcut)
        let storedShowsWindowSwitcherFocusPreview = defaults.object(forKey: Keys.showsWindowSwitcherFocusPreview) as? Bool
        let storedWindowSwitcherPreviewMode = defaults.string(forKey: Keys.windowSwitcherPreviewMode)
        let storedWindowSwitcherLayout = defaults.string(forKey: Keys.windowSwitcherLayout)
        let storedSwitcherMinimizeKeyCode = defaults.object(forKey: Keys.switcherMinimizeKeyCode) as? Int
        let storedSwitcherCloseKeyCode = defaults.object(forKey: Keys.switcherCloseKeyCode) as? Int
        let storedSwitcherZoomKeyCode = defaults.object(forKey: Keys.switcherZoomKeyCode) as? Int
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
        self.tileIconPadding = storedTileIconPadding.map { CGFloat($0) } ?? DefaultValues.tileIconPadding
        self.tileHoverOpacity = storedTileHoverOpacity.map { CGFloat($0) }
        self.tileHoverScale = storedTileHoverScale.map { CGFloat($0) }
        self.tileHoverBackgroundColor = Self.decodeColor(from: storedTileHoverBackgroundColor)
        self.tileHoverBackgroundImagePath = storedTileHoverBackgroundImagePath
        self.tileHoverBackgroundOpacity = storedTileHoverBackgroundOpacity.map { CGFloat($0) }
        self.tileHoverBackgroundCornerRadius = storedTileHoverBackgroundCornerRadius.map { CGFloat($0) }
        self.tileActiveBackgroundColor = Self.decodeColor(from: storedTileActiveBackgroundColor)
        self.tileActiveBackgroundImagePath = storedTileActiveBackgroundImagePath
        self.tileActiveBackgroundOpacity = storedTileActiveBackgroundOpacity.map { CGFloat($0) }
        self.tileActiveBackgroundCornerRadius = storedTileActiveBackgroundCornerRadius.map { CGFloat($0) }
        self.widget1xContentPadding = storedWidget1xContentPadding.map { CGFloat($0) }
        self.widget1xCornerRadius = storedWidget1xCornerRadius.map { CGFloat($0) }
        self.widget2xContentPadding = storedWidget2xContentPadding.map { CGFloat($0) }
        self.widget2xCornerRadius = storedWidget2xCornerRadius.map { CGFloat($0) }
        self.widget3xContentPadding = storedWidget3xContentPadding.map { CGFloat($0) }
        self.widget3xCornerRadius = storedWidget3xCornerRadius.map { CGFloat($0) }
        self.widget4xContentPadding = storedWidget4xContentPadding.map { CGFloat($0) }
        self.widget4xCornerRadius = storedWidget4xCornerRadius.map { CGFloat($0) }
        self.windowCornerRadius = storedWindowCornerRadius.map { CGFloat($0) } ?? DefaultValues.windowCornerRadius
        self.windowCornerRadiusTopLeading = storedWindowCornerRadiusTopLeading.map { CGFloat($0) }
        self.windowCornerRadiusTopTrailing = storedWindowCornerRadiusTopTrailing.map { CGFloat($0) }
        self.windowCornerRadiusBottomLeading = storedWindowCornerRadiusBottomLeading.map { CGFloat($0) }
        self.windowCornerRadiusBottomTrailing = storedWindowCornerRadiusBottomTrailing.map { CGFloat($0) }
        self.windowContentInsetTop = storedWindowContentInsetTop.map { CGFloat($0) } ?? DefaultValues.windowContentInset
        self.windowContentInsetLeading = storedWindowContentInsetLeading.map { CGFloat($0) } ?? DefaultValues.windowContentInset
        self.windowContentInsetBottom = storedWindowContentInsetBottom.map { CGFloat($0) } ?? DefaultValues.windowContentInset
        self.windowContentInsetTrailing = storedWindowContentInsetTrailing.map { CGFloat($0) } ?? DefaultValues.windowContentInset
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
        self.shelveHidesFinder = storedShelveHidesFinder ?? DefaultValues.shelveHidesFinder
        self.shelveHidesTrash = storedShelveHidesTrash ?? DefaultValues.shelveHidesTrash
        self.hidesRecentApps = storedHidesRecentApps ?? DefaultValues.hidesRecentApps
        self.hidesProfileStrip = storedHidesProfileStrip ?? DefaultValues.hidesProfileStrip
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
        self.dividerOpacity = min(max(storedDividerOpacity.map { CGFloat($0) } ?? DefaultValues.dividerOpacity, 0), 1)
        self.dividerColor = Self.decodeColor(from: storedDividerColor) ?? DefaultValues.dividerColor
        self.windowBorderColor = Self.decodeColor(from: storedWindowBorderColor) ?? DefaultValues.windowBorderColor
        self.windowBorderWidth = max(0, storedWindowBorderWidth.map { CGFloat($0) } ?? DefaultValues.windowBorderWidth)
        self.iconShadowColor = Self.decodeColor(from: storedIconShadowColor) ?? DefaultValues.iconShadowColor
        self.iconShadowRadius = max(0, storedIconShadowRadius.map { CGFloat($0) } ?? DefaultValues.iconShadowRadius)
        self.iconShadowOpacity = min(max(storedIconShadowOpacity.map { CGFloat($0) } ?? DefaultValues.iconShadowOpacity, 0), 1)
        self.appIconOverrides = Self.decodeAppIconOverrides(from: storedAppIconOverrides) ?? DefaultValues.appIconOverrides
        self.trashIconOverrides = Self.decodeTrashIconOverrides(from: storedTrashIconOverrides) ?? DefaultValues.trashIconOverrides
        self.folderIconOverrides = Self.decodeFolderIconOverrides(from: storedFolderIconOverrides) ?? DefaultValues.folderIconOverrides
        self.launchpadIconPath = storedLaunchpadIconPath ?? DefaultValues.launchpadIconPath
        self.launchpadIconPaddingFraction = storedLaunchpadIconPaddingFraction.map { CGFloat($0) }
        self.startMenuIconPath = storedStartMenuIconPath ?? DefaultValues.startMenuIconPath
        self.startMenuIconPaddingFraction = storedStartMenuIconPaddingFraction.map { CGFloat($0) }
            ?? DefaultValues.launchpadIconPaddingFraction
        self.hiddenAppBundleIdentifiers = Self.normalizedBundleIdentifiers(storedHiddenAppBundleIdentifiers ?? DefaultValues.hiddenAppBundleIdentifiers)
        self.showsGroupedOpenedAppsInDock = storedShowsGroupedOpenedAppsInDock ?? DefaultValues.showsGroupedOpenedAppsInDock
        self.showsGroupedOpenedAppsBackdrop = storedShowsGroupedOpenedAppsBackdrop ?? DefaultValues.showsGroupedOpenedAppsBackdrop
        self.enablesLaunchpadOverlay = storedEnablesLaunchpadOverlay ?? DefaultValues.enablesLaunchpadOverlay
        self.enablesStartMenuOverlay = storedEnablesStartMenuOverlay ?? DefaultValues.enablesStartMenuOverlay
        self.opensStartMenuFromFinderTile = storedOpensStartMenuFromFinderTile ?? DefaultValues.opensStartMenuFromFinderTile
        self.launchpadOverlayTransparency = min(max(
            storedLaunchpadOverlayTransparency.map { CGFloat($0) } ?? DefaultValues.launchpadOverlayTransparency,
            0
        ), 1)
        self.launchpadGridColumnCount = max(storedLaunchpadGridColumnCount ?? DefaultValues.launchpadGridColumnCount, 1)
        self.launchpadGridRowCount = max(storedLaunchpadGridRowCount ?? DefaultValues.launchpadGridRowCount, 1)
        self.launchpadBaseIconSize = min(
            max(
                storedLaunchpadBaseIconSize.map { CGFloat($0) } ?? DefaultValues.launchpadBaseIconSize,
                DefaultValues.launchpadBaseIconSizeMin
            ),
            DefaultValues.launchpadBaseIconSizeMax
        )
        self.launchpadColumnSpacing = min(
            max(
                storedLaunchpadColumnSpacing.map { CGFloat($0) } ?? DefaultValues.launchpadColumnSpacing,
                DefaultValues.launchpadSpacingMin
            ),
            DefaultValues.launchpadSpacingMax
        )
        self.launchpadLayoutAxis = storedLaunchpadLayoutAxis
            .flatMap(LaunchpadLayoutAxis.init(rawValue:))
            ?? DefaultValues.launchpadLayoutAxis
        self.launchpadShortcut = Self.decodeKeyboardShortcut(from: storedLaunchpadShortcut) ?? DefaultValues.launchpadShortcut
        self.enablesWindowSwitcher = storedEnablesWindowSwitcher ?? DefaultValues.enablesWindowSwitcher
        self.windowSwitcherShortcut = Self.decodeKeyboardShortcut(from: storedWindowSwitcherShortcut) ?? DefaultValues.windowSwitcherShortcut
        self.showsWindowSwitcherFocusPreview = storedShowsWindowSwitcherFocusPreview ?? DefaultValues.showsWindowSwitcherFocusPreview
        self.windowSwitcherPreviewMode = storedWindowSwitcherPreviewMode.flatMap(WindowSwitcherPreviewMode.init(rawValue:)) ?? DefaultValues.windowSwitcherPreviewMode
        self.windowSwitcherLayout = storedWindowSwitcherLayout.flatMap(WindowSwitcherLayout.init(rawValue:)) ?? DefaultValues.windowSwitcherLayout
        self.switcherMinimizeKeyCode = storedSwitcherMinimizeKeyCode.map(UInt16.init) ?? DefaultValues.switcherMinimizeKeyCode
        self.switcherCloseKeyCode = storedSwitcherCloseKeyCode.map(UInt16.init) ?? DefaultValues.switcherCloseKeyCode
        self.switcherZoomKeyCode = storedSwitcherZoomKeyCode.map(UInt16.init) ?? DefaultValues.switcherZoomKeyCode
        self.pinnedAppBundleIdentifiers = initialPinnedAppBundleIdentifiers
        self.pinnedItems = initialPinnedItems
        self.widgetPlacements = Self.decodeWidgetPlacements(from: storedWidgetPlacements) ?? DefaultValues.widgetPlacements
        self.appWidgetDisplays = Self.decodeAppWidgetDisplays(from: storedAppWidgetDisplays) ?? DefaultValues.appWidgetDisplays
        self.trailingItems = Self.decodeTrailingItems(from: storedTrailingItems) ?? DefaultValues.trailingItems
        self.hasSeenDockEditorHint = storedHasSeenDockEditorHint ?? DefaultValues.hasSeenDockEditorHint

        // Load the user-override set, then run the one-shot migration
        // that infers overrides from existing UserDefaults presence.
        // After this runs once, the set is the authoritative source of
        // truth, appearance setters maintain it from then on.
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
    /// window-management, and system-dock settings are untouched ,
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
        dividerOpacity = DefaultValues.dividerOpacity
        dividerColor = DefaultValues.dividerColor

        // Tile Layout (system tile size + magnification live on
        // DockSettingsService and aren't reset here)
        tileClipShape = DefaultValues.tileClipShape
        tileVerticalPadding = DefaultValues.tileVerticalPadding
        tileSpacing = DefaultValues.tileSpacing
        tileIconPadding = DefaultValues.tileIconPadding

        // Tile Hover Effect
        tileHoverOpacity = nil
        tileHoverScale = nil
        tileHoverBackgroundColor = nil
        tileHoverBackgroundImagePath = nil
        tileHoverBackgroundOpacity = nil
        tileHoverBackgroundCornerRadius = nil

        // Tile Active Background
        tileActiveBackgroundColor = nil
        tileActiveBackgroundImagePath = nil
        tileActiveBackgroundOpacity = nil
        tileActiveBackgroundCornerRadius = nil

        // Per-span widget chrome overrides
        widget1xContentPadding = nil
        widget1xCornerRadius = nil
        widget2xContentPadding = nil
        widget2xCornerRadius = nil
        widget3xContentPadding = nil
        widget3xCornerRadius = nil
        widget4xContentPadding = nil
        widget4xCornerRadius = nil

        // Icon Shadow (lives next to Tile Layout in the UI)
        iconShadowColor = DefaultValues.iconShadowColor
        iconShadowRadius = DefaultValues.iconShadowRadius
        iconShadowOpacity = DefaultValues.iconShadowOpacity

        // Window Shape
        windowClipShape = DefaultValues.windowClipShape
        windowCornerRadius = DefaultValues.windowCornerRadius
        windowCornerRadiusTopLeading = nil
        windowCornerRadiusTopTrailing = nil
        windowCornerRadiusBottomLeading = nil
        windowCornerRadiusBottomTrailing = nil
        windowContentInsetTop = DefaultValues.windowContentInset
        windowContentInsetLeading = DefaultValues.windowContentInset
        windowContentInsetBottom = DefaultValues.windowContentInset
        windowContentInsetTrailing = DefaultValues.windowContentInset
        windowBorderColor = DefaultValues.windowBorderColor
        windowBorderWidth = DefaultValues.windowBorderWidth

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

    /// Resets every preference surfaced in the Behavior settings panes
    /// (placement, visibility, app-tile click, app folders, widgets,
    /// launch, system-dock). Leaves appearance, app icons, hidden apps,
    /// pinned tiles, and feature-specific surfaces (Launchpad / Window
    /// Manager / Actions) untouched. Mirrors `resetAppearanceToDefaults`.
    func resetBehaviorToDefaults() {
        // Placement
        windowPosition = DefaultValues.windowPosition
        windowDisplayTarget = DefaultValues.windowDisplayTarget
        windowSpaceBehavior = DefaultValues.windowSpaceBehavior
        windowAxisSizing = DefaultValues.windowAxisSizing
        maximizedWindowBehavior = DefaultValues.maximizedWindowBehavior
        overflowBehavior = DefaultValues.overflowBehavior

        // Visibility
        autohidesWindow = DefaultValues.autohidesWindow
        autohideWindowDelay = DefaultValues.autohideWindowDelay
        hidesDuringFullscreen = DefaultValues.hidesDuringFullscreen
        fullscreenRevealDelay = DefaultValues.fullscreenRevealDelay
        enablesShelveMode = DefaultValues.enablesShelveMode
        shelveHidesFinder = DefaultValues.shelveHidesFinder
        shelveHidesTrash = DefaultValues.shelveHidesTrash
        hidesRecentApps = DefaultValues.hidesRecentApps
        showsRunningApps = DefaultValues.showsRunningApps
        showsMinimizedWindows = DefaultValues.showsMinimizedWindows
        showsActivePinnedSeparator = DefaultValues.showsActivePinnedSeparator

        // App-tile click
        appTileFrontmostClickBehavior = DefaultValues.appTileFrontmostClickBehavior

        // App folders
        showsGroupedOpenedAppsInDock = DefaultValues.showsGroupedOpenedAppsInDock
        showsGroupedOpenedAppsBackdrop = DefaultValues.showsGroupedOpenedAppsBackdrop

        // Widgets
        enablesWidgetHoverPreview = DefaultValues.enablesWidgetHoverPreview
        widgetHoverPreviewSpans = DefaultValues.widgetHoverPreviewSpans
        widgetHoverPreviewDelay = DefaultValues.widgetHoverPreviewDelay
        windowPreviewHoverDelay = DefaultValues.windowPreviewHoverDelay
        windowPreviewLayout = DefaultValues.windowPreviewLayout

        // Launch
        opensAtLogin = DefaultValues.opensAtLogin

        // System dock
        hidesSystemDock = DefaultValues.hidesSystemDock

        // Same rationale as `resetAppearanceToDefaults`: setters guard
        // against same-value writes, so any pre-existing override flag
        // would survive without an explicit wipe. The behavior keys
        // currently in `appearanceKeys` (windowAxisSizing, tileSize,
        // largeSize, magnification) get their override status cleared
        // alongside the rest, themes can drive these again.
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
        shelveHidesFinder = DefaultValues.shelveHidesFinder
        shelveHidesTrash = DefaultValues.shelveHidesTrash
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
        dividerOpacity = DefaultValues.dividerOpacity
        appIconOverrides = DefaultValues.appIconOverrides
        trashIconOverrides = DefaultValues.trashIconOverrides
        folderIconOverrides = DefaultValues.folderIconOverrides
        launchpadIconPath = DefaultValues.launchpadIconPath
        launchpadIconPaddingFraction = DefaultValues.launchpadIconPaddingFraction
        startMenuIconPath = DefaultValues.startMenuIconPath
        startMenuIconPaddingFraction = DefaultValues.startMenuIconPaddingFraction
        hiddenAppBundleIdentifiers = DefaultValues.hiddenAppBundleIdentifiers
        showsGroupedOpenedAppsInDock = DefaultValues.showsGroupedOpenedAppsInDock
        showsGroupedOpenedAppsBackdrop = DefaultValues.showsGroupedOpenedAppsBackdrop
        enablesLaunchpadOverlay = DefaultValues.enablesLaunchpadOverlay
        enablesStartMenuOverlay = DefaultValues.enablesStartMenuOverlay
        opensStartMenuFromFinderTile = DefaultValues.opensStartMenuFromFinderTile
        launchpadOverlayTransparency = DefaultValues.launchpadOverlayTransparency
        launchpadGridColumnCount = DefaultValues.launchpadGridColumnCount
        launchpadGridRowCount = DefaultValues.launchpadGridRowCount
        launchpadShortcut = DefaultValues.launchpadShortcut
        enablesWindowSwitcher = DefaultValues.enablesWindowSwitcher
        windowSwitcherShortcut = DefaultValues.windowSwitcherShortcut
        showsWindowSwitcherFocusPreview = DefaultValues.showsWindowSwitcherFocusPreview
        windowSwitcherPreviewMode = DefaultValues.windowSwitcherPreviewMode
        windowSwitcherLayout = DefaultValues.windowSwitcherLayout
        switcherMinimizeKeyCode = DefaultValues.switcherMinimizeKeyCode
        switcherCloseKeyCode = DefaultValues.switcherCloseKeyCode
        switcherZoomKeyCode = DefaultValues.switcherZoomKeyCode
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

    /// Generic persistence helper for `DockColor?` defaults. Used by
    /// the newer optional-color fields (border, icon shadow, divider)
    /// so each one doesn't need its own dedicated `persist…Color`
    /// function.
    private func persistOptionalColor(_ color: DockColor?, forKey key: String) {
        guard let color else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? encoder.encode(color) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
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
