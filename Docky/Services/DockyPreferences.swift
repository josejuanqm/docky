//
//  DockyPreferences.swift
//  Docky
//
//  Docky's own user-adjustable settings. Persisted to UserDefaults.
//  Consume via `DockyPreferences.shared`; publishes changes through
//  ObservableObject + @Published so callers can observe live updates.
//
//  Not backed by a settings window yet — values are mutated in code for now,
//  but the property surface is ready for a future preferences UI.
//

import AppKit
import Combine
import Foundation

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
        contentViewMode: FolderTileContentViewMode = .grid
    ) -> Self {
        Self(
            id: id,
            kind: .appFolder,
            bundleIdentifier: nil,
            folderDisplayName: displayName,
            folderBundleIdentifiers: bundleIdentifiers,
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
            folderContentViewMode: nil,
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func smartStack(hiddenWidgetOwnerBundleIdentifiers: [String] = []) -> Self {
        Self(
            id: "custom:\(UUID().uuidString)",
            kind: .smartStack,
            bundleIdentifier: nil,
            folderDisplayName: nil,
            folderBundleIdentifiers: [],
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

    nonisolated static func folder(
        sourceTileID: String,
        displayMode: FolderTileDisplayMode = .contents,
        contentViewMode: FolderTileContentViewMode = .grid
    ) -> Self {
        Self(
            id: "folder:\(sourceTileID)",
            kind: .folder,
            sourceTileID: sourceTileID,
            folderURL: nil,
            folderDisplayName: nil,
            folderDisplayMode: displayMode,
            folderContentViewMode: contentViewMode,
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
        contentViewMode: FolderTileContentViewMode = .grid
    ) -> Self {
        Self(
            id: id,
            kind: .folder,
            sourceTileID: nil,
            folderURL: url,
            folderDisplayName: displayName,
            folderDisplayMode: displayMode,
            folderContentViewMode: contentViewMode,
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

    nonisolated static func smartStack(hiddenWidgetOwnerBundleIdentifiers: [String] = []) -> Self {
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
        case .system: "System"
        case .left: "Left"
        case .right: "Right"
        case .bottom: "Bottom"
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

enum DockOverflowBehavior: String, CaseIterable, Identifiable {
    case rescale
    case scroll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rescale: "Rescale"
        case .scroll: "Scroll"
        }
    }
}

enum DockWindowAxisSizing: String, CaseIterable, Identifiable {
    case fitContent
    case fullAxis

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fitContent: "Fit Content"
        case .fullAxis: "Full Axis"
        }
    }
}

enum DockClipShape: String, CaseIterable, Identifiable {
    case rounded
    case circle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: "Rounded"
        case .circle: "Circle"
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

enum DockTileIndicatorShape: String, CaseIterable, Identifiable {
    case none
    case dot
    case pill
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .dot: "Dot"
        case .pill: "Pill"
        case .image: "Custom Image"
        }
    }
}

struct AppIconOverride: Codable, Equatable, Identifiable {
    let bundleIdentifier: String
    let iconPath: String

    var id: String { bundleIdentifier }

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
        case .folder: "Folder"
        case .contents: "Contents"
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
        case .grid: "Grid"
        case .list: "List"
        case .inline: "Inline"
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

final class DockyPreferences: ObservableObject {
    static let shared = DockyPreferences()

    /// Padding applied inside each dock tile above and below the icon content.
    /// Total window height becomes `iconHeight + tileVerticalPadding * 2`.
    @Published var tileVerticalPadding: CGFloat {
        didSet {
            guard tileVerticalPadding != oldValue else { return }
            defaults.set(Double(tileVerticalPadding), forKey: Keys.tileVerticalPadding)
        }
    }

    /// Spacing applied between adjacent dock tiles.
    @Published var tileSpacing: CGFloat {
        didSet {
            guard tileSpacing != oldValue else { return }
            defaults.set(Double(tileSpacing), forKey: Keys.tileSpacing)
        }
    }

    /// Clip shape applied to Docky-rendered tile chrome.
    @Published var tileClipShape: DockClipShape {
        didSet {
            guard tileClipShape != oldValue else { return }
            defaults.set(tileClipShape.rawValue, forKey: Keys.tileClipShape)
        }
    }

    /// Corner radius applied to the main dock window.
    @Published var windowCornerRadius: CGFloat {
        didSet {
            guard windowCornerRadius != oldValue else { return }
            defaults.set(Double(windowCornerRadius), forKey: Keys.windowCornerRadius)
        }
    }

    /// Clip shape applied to the main dock chrome.
    @Published var windowClipShape: DockClipShape {
        didSet {
            guard windowClipShape != oldValue else { return }
            defaults.set(windowClipShape.rawValue, forKey: Keys.windowClipShape)
        }
    }

    /// Optional tint override for the main dock window. `nil` follows the system material tint.
    @Published var windowTintColor: DockColor? {
        didSet {
            guard windowTintColor != oldValue else { return }
            persistWindowTintColor(windowTintColor)
        }
    }

    /// Opacity applied to the main dock window tint.
    @Published var windowTintOpacity: CGFloat {
        didSet {
            guard windowTintOpacity != oldValue else { return }
            defaults.set(Double(windowTintOpacity), forKey: Keys.windowTintOpacity)
        }
    }

    /// Whether the main dock window should suppress its gradient border chrome.
    @Published var disablesGlassLook: Bool {
        didSet {
            guard disablesGlassLook != oldValue else { return }
            defaults.set(disablesGlassLook, forKey: Keys.disablesGlassLook)
        }
    }

    /// Optional image path used as the main dock window background.
    @Published var windowBackgroundImagePath: String? {
        didSet {
            guard windowBackgroundImagePath != oldValue else { return }

            if let windowBackgroundImagePath, !windowBackgroundImagePath.isEmpty {
                defaults.set(windowBackgroundImagePath, forKey: Keys.windowBackgroundImagePath)
            } else {
                defaults.removeObject(forKey: Keys.windowBackgroundImagePath)
            }
        }
    }

    /// Edge Docky anchors itself to. `system` mirrors the macOS Dock.
    @Published var windowPosition: DockWindowPosition {
        didSet {
            guard windowPosition != oldValue else { return }
            defaults.set(windowPosition.rawValue, forKey: Keys.windowPosition)
        }
    }

    /// Whether Docky's main window should slide off-screen until revealed.
    @Published var autohidesWindow: Bool {
        didSet {
            guard autohidesWindow != oldValue else { return }
            defaults.set(autohidesWindow, forKey: Keys.autohidesWindow)
        }
    }

    /// Whether Docky should hide the macOS system Dock while running.
    /// Turning this on snapshots the user's current Dock preferences and
    /// overwrites autohide/bounce behavior; turning it off restores the
    /// snapshot. The snapshot is also restored when Docky quits.
    @Published var hidesSystemDock: Bool {
        didSet {
            guard hidesSystemDock != oldValue else { return }
            defaults.set(hidesSystemDock, forKey: Keys.hidesSystemDock)
            if hidesSystemDock {
                SystemDockVisibilityService.shared.hide()
            } else {
                SystemDockVisibilityService.shared.restore()
            }
        }
    }

    /// How Docky handles overflow when tiles exceed the screen on the dock axis.
    @Published var overflowBehavior: DockOverflowBehavior {
        didSet {
            guard overflowBehavior != oldValue else { return }
            defaults.set(overflowBehavior.rawValue, forKey: Keys.overflowBehavior)
        }
    }

    /// Whether Docky's window hugs its content or stretches across the full dock axis.
    @Published var windowAxisSizing: DockWindowAxisSizing {
        didSet {
            guard windowAxisSizing != oldValue else { return }
            defaults.set(windowAxisSizing.rawValue, forKey: Keys.windowAxisSizing)
        }
    }

    /// Whether Docky shows the divider between pinned apps and unpinned running apps.
    @Published var showsActivePinnedSeparator: Bool {
        didSet {
            guard showsActivePinnedSeparator != oldValue else { return }
            defaults.set(showsActivePinnedSeparator, forKey: Keys.showsActivePinnedSeparator)
        }
    }

    /// Shape used for the active app indicator.
    @Published var activeIndicatorShape: DockTileIndicatorShape {
        didSet {
            guard activeIndicatorShape != oldValue else { return }
            defaults.set(activeIndicatorShape.rawValue, forKey: Keys.activeIndicatorShape)
        }
    }

    /// Optional image path used for the custom active app indicator.
    @Published var activeIndicatorImagePath: String? {
        didSet {
            guard activeIndicatorImagePath != oldValue else { return }

            if let activeIndicatorImagePath, !activeIndicatorImagePath.isEmpty {
                defaults.set(activeIndicatorImagePath, forKey: Keys.activeIndicatorImagePath)
            } else {
                defaults.removeObject(forKey: Keys.activeIndicatorImagePath)
            }
        }
    }

    /// Optional color override used for dot and pill active app indicators.
    @Published var activeIndicatorColor: DockColor? {
        didSet {
            guard activeIndicatorColor != oldValue else { return }
            persistActiveIndicatorColor(activeIndicatorColor)
        }
    }

    /// Optional per-app icon overrides used by app tiles.
    @Published var appIconOverrides: [AppIconOverride] {
        didSet {
            guard appIconOverrides != oldValue else { return }
            persistAppIconOverrides(appIconOverrides)
        }
    }

    /// Whether opened apps from an app folder should appear grouped beside that folder.
    @Published var showsGroupedOpenedAppsInDock: Bool {
        didSet {
            guard showsGroupedOpenedAppsInDock != oldValue else { return }
            defaults.set(showsGroupedOpenedAppsInDock, forKey: Keys.showsGroupedOpenedAppsInDock)
        }
    }

    /// Preferred column count for the Launchpad overlay grid.
    @Published var launchpadGridColumnCount: Int {
        didSet {
            let clampedValue = max(1, launchpadGridColumnCount)
            guard clampedValue != oldValue else {
                launchpadGridColumnCount = clampedValue
                return
            }

            if launchpadGridColumnCount != clampedValue {
                launchpadGridColumnCount = clampedValue
                return
            }

            defaults.set(clampedValue, forKey: Keys.launchpadGridColumnCount)
        }
    }

    /// Global shortcut that toggles Docky's Launchpad overlay.
    @Published var launchpadShortcut: KeyboardShortcut {
        didSet {
            guard launchpadShortcut != oldValue else { return }
            persistLaunchpadShortcut(launchpadShortcut)
        }
    }

    /// Global shortcut that opens Docky's window switcher.
    @Published var windowSwitcherShortcut: KeyboardShortcut {
        didSet {
            guard windowSwitcherShortcut != oldValue else { return }
            persistWindowSwitcherShortcut(windowSwitcherShortcut)
        }
    }

    /// Whether the window switcher should preview the selected window in place after a short hold.
    @Published var showsWindowSwitcherFocusPreview: Bool {
        didSet {
            guard showsWindowSwitcherFocusPreview != oldValue else { return }
            defaults.set(showsWindowSwitcherFocusPreview, forKey: Keys.showsWindowSwitcherFocusPreview)
        }
    }

    /// Docky-owned ordered pinned app bundle identifiers.
    @Published var pinnedAppBundleIdentifiers: [String] {
        didSet {
            guard pinnedAppBundleIdentifiers != oldValue else { return }
            defaults.set(pinnedAppBundleIdentifiers, forKey: Keys.pinnedAppBundleIdentifiers)
        }
    }

    /// Docky-owned ordered pinned section items.
    @Published var pinnedItems: [PinnedTileItem] {
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
    @Published var widgetPlacements: [WidgetPlacement] {
        didSet {
            guard widgetPlacements != oldValue else { return }
            persistWidgetPlacements(widgetPlacements)
        }
    }

    /// Optional widget substitutions for app tiles.
    @Published var appWidgetDisplays: [AppWidgetDisplay] {
        didSet {
            guard appWidgetDisplays != oldValue else { return }
            persistAppWidgetDisplays(appWidgetDisplays)
        }
    }

    /// Docky-owned ordered folder/trash section items.
    @Published var trailingItems: [TrailingTileItem] {
        didSet {
            guard trailingItems != oldValue else { return }
            persistTrailingItems(trailingItems)
        }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var effectiveWindowTintColor: NSColor {
        windowTintColor?.nsColor ?? Self.defaultWindowTintColor
    }

    var effectiveActiveIndicatorColor: NSColor {
        activeIndicatorColor?.nsColor ?? .labelColor
    }

    var effectiveWindowTintOpacity: CGFloat {
        min(max(windowTintOpacity, 0), 1)
    }

    var effectiveWindowBackgroundImageURL: URL? {
        guard let windowBackgroundImagePath, !windowBackgroundImagePath.isEmpty else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: windowBackgroundImagePath) else {
            return nil
        }

        return URL(fileURLWithPath: windowBackgroundImagePath)
    }

    var effectiveActiveIndicatorImageURL: URL? {
        guard let activeIndicatorImagePath, !activeIndicatorImagePath.isEmpty else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: activeIndicatorImagePath) else {
            return nil
        }

        return URL(fileURLWithPath: activeIndicatorImagePath)
    }

    func appIconOverride(forBundleIdentifier bundleIdentifier: String) -> AppIconOverride? {
        appIconOverrides.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func effectiveAppIconOverrideURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        appIconOverride(forBundleIdentifier: bundleIdentifier)?.effectiveIconURL
    }

    func setAppIconOverride(bundleIdentifier: String, iconPath: String) {
        guard !bundleIdentifier.isEmpty, !iconPath.isEmpty else {
            return
        }

        var overridesByBundleIdentifier = Dictionary(uniqueKeysWithValues: appIconOverrides.map {
            ($0.bundleIdentifier, $0)
        })
        overridesByBundleIdentifier[bundleIdentifier] = AppIconOverride(
            bundleIdentifier: bundleIdentifier,
            iconPath: iconPath
        )
        appIconOverrides = overridesByBundleIdentifier.values.sorted {
            $0.bundleIdentifier.localizedCaseInsensitiveCompare($1.bundleIdentifier) == .orderedAscending
        }
    }

    func removeAppIconOverride(bundleIdentifier: String) {
        appIconOverrides.removeAll { $0.bundleIdentifier == bundleIdentifier }
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
        static let windowPosition = "docky.windowPosition"
        static let autohidesWindow = "docky.autohidesWindow"
        static let hidesSystemDock = "docky.hidesSystemDock"
        static let overflowBehavior = "docky.overflowBehavior"
        static let windowAxisSizing = "docky.windowAxisSizing"
        static let showsActivePinnedSeparator = "docky.showsActivePinnedSeparator"
        static let activeIndicatorShape = "docky.activeIndicatorShape"
        static let activeIndicatorImagePath = "docky.activeIndicatorImagePath"
        static let activeIndicatorColor = "docky.activeIndicatorColor"
        static let appIconOverrides = "docky.appIconOverrides"
        static let showsGroupedOpenedAppsInDock = "docky.showsGroupedOpenedAppsInDock"
        static let launchpadGridColumnCount = "docky.launchpadGridColumnCount"
        static let launchpadShortcut = "docky.launchpadShortcut"
        static let windowSwitcherShortcut = "docky.windowSwitcherShortcut"
        static let showsWindowSwitcherFocusPreview = "docky.showsWindowSwitcherFocusPreview"
        static let pinnedAppBundleIdentifiers = "docky.pinnedAppBundleIdentifiers"
        static let pinnedItems = "docky.pinnedItems"
        static let widgetPlacements = "docky.widgetPlacements"
        static let appWidgetDisplays = "docky.appWidgetDisplays"
        static let trailingItems = "docky.trailingItems"
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
        static let windowPosition: DockWindowPosition = .system
        static let autohidesWindow = false
        static let hidesSystemDock = false
        static let overflowBehavior: DockOverflowBehavior = .rescale
        static let windowAxisSizing: DockWindowAxisSizing = .fitContent
        static let showsActivePinnedSeparator = true
        static let activeIndicatorShape: DockTileIndicatorShape = .dot
        static let activeIndicatorImagePath: String? = nil
        static let activeIndicatorColor: DockColor? = nil
        static let appIconOverrides: [AppIconOverride] = []
        static let showsGroupedOpenedAppsInDock = true
        static let launchpadGridColumnCount = 7
        static let launchpadShortcut = KeyboardShortcut.empty
        static let windowSwitcherShortcut = KeyboardShortcut(keyCode: 48, modifierFlags: [.option])
        static let showsWindowSwitcherFocusPreview = true
        static let pinnedAppBundleIdentifiers: [String] = []
        static let pinnedItems: [PinnedTileItem] = []
        static let widgetPlacements: [WidgetPlacement] = []
        static let appWidgetDisplays: [AppWidgetDisplay] = []
        static let trailingItems: [TrailingTileItem] = []
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
        let storedWindowPosition = defaults.string(forKey: Keys.windowPosition)
        let storedAutohidesWindow = defaults.object(forKey: Keys.autohidesWindow) as? Bool
        let storedHidesSystemDock = defaults.object(forKey: Keys.hidesSystemDock) as? Bool
        let storedOverflowBehavior = defaults.string(forKey: Keys.overflowBehavior)
        let storedWindowAxisSizing = defaults.string(forKey: Keys.windowAxisSizing)
        let storedShowsActivePinnedSeparator = defaults.object(forKey: Keys.showsActivePinnedSeparator) as? Bool
        let storedActiveIndicatorShape = defaults.string(forKey: Keys.activeIndicatorShape)
        let storedActiveIndicatorImagePath = defaults.string(forKey: Keys.activeIndicatorImagePath)
        let storedActiveIndicatorColor = defaults.data(forKey: Keys.activeIndicatorColor)
        let storedAppIconOverrides = defaults.data(forKey: Keys.appIconOverrides)
        let storedShowsGroupedOpenedAppsInDock = defaults.object(forKey: Keys.showsGroupedOpenedAppsInDock) as? Bool
        let storedLaunchpadGridColumnCount = defaults.object(forKey: Keys.launchpadGridColumnCount) as? Int
        let storedLaunchpadShortcut = defaults.data(forKey: Keys.launchpadShortcut)
        let storedWindowSwitcherShortcut = defaults.data(forKey: Keys.windowSwitcherShortcut)
        let storedShowsWindowSwitcherFocusPreview = defaults.object(forKey: Keys.showsWindowSwitcherFocusPreview) as? Bool
        let storedPinnedAppBundleIdentifiers = defaults.stringArray(forKey: Keys.pinnedAppBundleIdentifiers)
        let storedPinnedItems = defaults.data(forKey: Keys.pinnedItems)
        let storedWidgetPlacements = defaults.data(forKey: Keys.widgetPlacements)
        let storedAppWidgetDisplays = defaults.data(forKey: Keys.appWidgetDisplays)
        let storedTrailingItems = defaults.data(forKey: Keys.trailingItems)
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
        self.windowPosition = (storedWindowPosition.flatMap(DockWindowPosition.init(rawValue:)) ?? DefaultValues.windowPosition)
        self.autohidesWindow = storedAutohidesWindow ?? DefaultValues.autohidesWindow
        self.hidesSystemDock = storedHidesSystemDock ?? DefaultValues.hidesSystemDock
        self.overflowBehavior = (storedOverflowBehavior.flatMap(DockOverflowBehavior.init(rawValue:)) ?? DefaultValues.overflowBehavior)
        self.windowAxisSizing = (storedWindowAxisSizing.flatMap(DockWindowAxisSizing.init(rawValue:)) ?? DefaultValues.windowAxisSizing)
        self.showsActivePinnedSeparator = storedShowsActivePinnedSeparator ?? DefaultValues.showsActivePinnedSeparator
        self.activeIndicatorShape = (storedActiveIndicatorShape.flatMap(DockTileIndicatorShape.init(rawValue:)) ?? DefaultValues.activeIndicatorShape)
        self.activeIndicatorImagePath = storedActiveIndicatorImagePath ?? DefaultValues.activeIndicatorImagePath
        self.activeIndicatorColor = Self.decodeColor(from: storedActiveIndicatorColor) ?? DefaultValues.activeIndicatorColor
        self.appIconOverrides = Self.decodeAppIconOverrides(from: storedAppIconOverrides) ?? DefaultValues.appIconOverrides
        self.showsGroupedOpenedAppsInDock = storedShowsGroupedOpenedAppsInDock ?? DefaultValues.showsGroupedOpenedAppsInDock
        self.launchpadGridColumnCount = max(storedLaunchpadGridColumnCount ?? DefaultValues.launchpadGridColumnCount, 1)
        self.launchpadShortcut = Self.decodeKeyboardShortcut(from: storedLaunchpadShortcut) ?? DefaultValues.launchpadShortcut
        self.windowSwitcherShortcut = Self.decodeKeyboardShortcut(from: storedWindowSwitcherShortcut) ?? DefaultValues.windowSwitcherShortcut
        self.showsWindowSwitcherFocusPreview = storedShowsWindowSwitcherFocusPreview ?? DefaultValues.showsWindowSwitcherFocusPreview
        self.pinnedAppBundleIdentifiers = initialPinnedAppBundleIdentifiers
        self.pinnedItems = initialPinnedItems
        self.widgetPlacements = Self.decodeWidgetPlacements(from: storedWidgetPlacements) ?? DefaultValues.widgetPlacements
        self.appWidgetDisplays = Self.decodeAppWidgetDisplays(from: storedAppWidgetDisplays) ?? DefaultValues.appWidgetDisplays
        self.trailingItems = Self.decodeTrailingItems(from: storedTrailingItems) ?? DefaultValues.trailingItems
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
        windowPosition = DefaultValues.windowPosition
        autohidesWindow = DefaultValues.autohidesWindow
        hidesSystemDock = DefaultValues.hidesSystemDock
        overflowBehavior = DefaultValues.overflowBehavior
        windowAxisSizing = DefaultValues.windowAxisSizing
        showsActivePinnedSeparator = DefaultValues.showsActivePinnedSeparator
        activeIndicatorShape = DefaultValues.activeIndicatorShape
        activeIndicatorImagePath = DefaultValues.activeIndicatorImagePath
        activeIndicatorColor = DefaultValues.activeIndicatorColor
        appIconOverrides = DefaultValues.appIconOverrides
        showsGroupedOpenedAppsInDock = DefaultValues.showsGroupedOpenedAppsInDock
        launchpadGridColumnCount = DefaultValues.launchpadGridColumnCount
        launchpadShortcut = DefaultValues.launchpadShortcut
        windowSwitcherShortcut = DefaultValues.windowSwitcherShortcut
        showsWindowSwitcherFocusPreview = DefaultValues.showsWindowSwitcherFocusPreview
        appWidgetDisplays = DefaultValues.appWidgetDisplays
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
}
