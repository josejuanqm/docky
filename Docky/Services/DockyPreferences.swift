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

    nonisolated static func smartStack(hiddenWidgetOwnerBundleIdentifiers: [String] = []) -> Self {
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

enum DockWindowDisplayTarget: String, CaseIterable, Identifiable {
    case primaryDisplay
    case displayContainingPointer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primaryDisplay: "Primary Display"
        case .displayContainingPointer: "Display With Pointer"
        }
    }
}

enum DockWindowSpaceBehavior: String, CaseIterable, Identifiable {
    case activeSpace
    case allSpaces

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activeSpace: "Active Space"
        case .allSpaces: "All Spaces"
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
        case .none: "Do Nothing"
        case .hide: "Hide App"
        case .cycleWindows: "Cycle Windows"
        case .minimizeAll: "Minimize All Windows"
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

enum AppFolderTileDisplayMode: String, CaseIterable, Codable, Identifiable {
    case grid
    case stack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Grid"
        case .stack: "Stack"
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
        case .name: "Name"
        case .dateModified: "Date Modified"
        case .dateCreated: "Date Created"
        case .dateAdded: "Date Added"
        case .kind: "Kind"
        case .size: "Size"
        }
    }
}

enum WindowSwitcherPreviewMode: String, CaseIterable, Codable, Identifiable {
    case inPlace
    case instantFocus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inPlace: "In Place"
        case .instantFocus: "Instant Focus"
        }
    }

    var summary: String {
        switch self {
        case .inPlace:
            "Hold on one selection to preview that window behind the switcher without changing focus until you release the shortcut."
        case .instantFocus:
            "Focus each selected window immediately while keeping the original cycling order frozen until you release the shortcut."
        }
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
            syncSystemDockPositionIfNeeded()
        }
    }

    /// Which display owns Docky's single main window.
    @Published var windowDisplayTarget: DockWindowDisplayTarget {
        didSet {
            guard windowDisplayTarget != oldValue else { return }
            defaults.set(windowDisplayTarget.rawValue, forKey: Keys.windowDisplayTarget)
        }
    }

    /// Whether Docky's windows stay in the active Space or join all Spaces.
    @Published var windowSpaceBehavior: DockWindowSpaceBehavior {
        didSet {
            guard windowSpaceBehavior != oldValue else { return }
            defaults.set(windowSpaceBehavior.rawValue, forKey: Keys.windowSpaceBehavior)
        }
    }

    /// Whether Docky's main window should slide off-screen until revealed.
    @Published var autohidesWindow: Bool {
        didSet {
            guard autohidesWindow != oldValue else { return }
            defaults.set(autohidesWindow, forKey: Keys.autohidesWindow)
        }
    }

    /// Whether Docky should register itself to launch when the user logs in.
    @Published var opensAtLogin: Bool {
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
    @Published var autohideWindowDelay: TimeInterval {
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

    /// Whether Docky should hide the macOS system Dock while running.
    /// Turning this on snapshots the user's current Dock preferences and
    /// overwrites autohide/bounce behavior; turning it off restores the
    /// snapshot. The snapshot is also restored when Docky quits.
    @Published var hidesSystemDock: Bool {
        didSet {
            guard hidesSystemDock != oldValue else { return }
            defaults.set(hidesSystemDock, forKey: Keys.hidesSystemDock)
            applySystemDockVisibilityPreference()
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

    /// Whether hovering an expandable widget tile presents the expanded preview window.
    @Published var enablesWidgetHoverPreview: Bool {
        didSet {
            guard enablesWidgetHoverPreview != oldValue else { return }
            defaults.set(enablesWidgetHoverPreview, forKey: Keys.enablesWidgetHoverPreview)
        }
    }

    /// Tile spans for which the expanded hover preview is allowed to appear.
    @Published var widgetHoverPreviewSpans: Set<TileSpan> {
        didSet {
            guard widgetHoverPreviewSpans != oldValue else { return }
            defaults.set(widgetHoverPreviewSpans.map(\.rawValue), forKey: Keys.widgetHoverPreviewSpans)
        }
    }

    /// How long the cursor must rest on a widget before its expanded preview appears. Zero = immediate.
    @Published var widgetHoverPreviewDelay: TimeInterval {
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
    @Published var showsActivePinnedSeparator: Bool {
        didSet {
            guard showsActivePinnedSeparator != oldValue else { return }
            defaults.set(showsActivePinnedSeparator, forKey: Keys.showsActivePinnedSeparator)
        }
    }

    /// Whether Docky surfaces unpinned running apps. Disable to use Docky as a static shelf alongside the system Dock.
    @Published var showsRunningApps: Bool {
        didSet {
            guard showsRunningApps != oldValue else { return }
            defaults.set(showsRunningApps, forKey: Keys.showsRunningApps)
        }
    }

    /// Behavior when clicking an app tile whose app is already frontmost with at least one
    /// visible window. `.none` is the default; `.cycleWindows` and `.minimizeAll` are pro-only.
    @Published var appTileFrontmostClickBehavior: AppTileFrontmostClickBehavior {
        didSet {
            guard appTileFrontmostClickBehavior != oldValue else { return }
            defaults.set(appTileFrontmostClickBehavior.rawValue, forKey: Keys.appTileFrontmostClickBehavior)
        }
    }

    /// Whether Docky surfaces minimized window tiles in the trailing section.
    @Published var showsMinimizedWindows: Bool {
        didSet {
            guard showsMinimizedWindows != oldValue else { return }
            defaults.set(showsMinimizedWindows, forKey: Keys.showsMinimizedWindows)
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

    /// Bundle identifiers hidden from Docky's app tile surfaces.
    @Published var hiddenAppBundleIdentifiers: [String] {
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
    @Published var showsGroupedOpenedAppsInDock: Bool {
        didSet {
            guard showsGroupedOpenedAppsInDock != oldValue else { return }
            defaults.set(showsGroupedOpenedAppsInDock, forKey: Keys.showsGroupedOpenedAppsInDock)
        }
    }

    /// Whether Docky's Launchpad overlay is enabled.
    @Published var enablesLaunchpadOverlay: Bool {
        didSet {
            guard enablesLaunchpadOverlay != oldValue else { return }
            defaults.set(enablesLaunchpadOverlay, forKey: Keys.enablesLaunchpadOverlay)
        }
    }

    /// Preferred column count for the Launchpad overlay grid.
    @Published var launchpadGridColumnCount: Int {
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

    /// Global shortcut that toggles Docky's Launchpad overlay.
    @Published var launchpadShortcut: KeyboardShortcut {
        didSet {
            guard launchpadShortcut != oldValue else { return }
            persistLaunchpadShortcut(launchpadShortcut)
        }
    }

    /// Whether Docky's window switcher is enabled.
    @Published var enablesWindowSwitcher: Bool {
        didSet {
            guard enablesWindowSwitcher != oldValue else { return }
            defaults.set(enablesWindowSwitcher, forKey: Keys.enablesWindowSwitcher)
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

    /// Which behavior Docky's window switcher should use when previewing the selected window.
    @Published var windowSwitcherPreviewMode: WindowSwitcherPreviewMode {
        didSet {
            guard windowSwitcherPreviewMode != oldValue else { return }
            defaults.set(windowSwitcherPreviewMode.rawValue, forKey: Keys.windowSwitcherPreviewMode)
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

    /// Whether Docky has already shown the divider edit hint chip.
    @Published var hasSeenDockEditorHint: Bool {
        didSet {
            guard hasSeenDockEditorHint != oldValue else { return }
            defaults.set(hasSeenDockEditorHint, forKey: Keys.hasSeenDockEditorHint)
        }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isSyncingOpenAtLoginPreference = false

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
        guard ProductService.shared.isUnlocked(.customAppIcons) else {
            return nil
        }

        return appIconOverrides.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func effectiveAppIconOverrideURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        appIconOverride(forBundleIdentifier: bundleIdentifier)?.effectiveIconURL
    }

    func setAppIconOverride(bundleIdentifier: String, iconPath: String) {
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
            iconPath: iconPath
        )
        appIconOverrides = overridesByBundleIdentifier.values.sorted {
            $0.bundleIdentifier.localizedCaseInsensitiveCompare($1.bundleIdentifier) == .orderedAscending
        }
    }

    func removeAppIconOverride(bundleIdentifier: String) {
        appIconOverrides.removeAll { $0.bundleIdentifier == bundleIdentifier }
    }

    func isAppHiddenInDocky(bundleIdentifier: String) -> Bool {
        hiddenAppBundleIdentifiers.contains(bundleIdentifier)
    }

    func setAppHiddenInDocky(bundleIdentifier: String, isHidden: Bool) {
        guard !bundleIdentifier.isEmpty else {
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
        static let windowPosition = "docky.windowPosition"
        static let windowDisplayTarget = "docky.windowDisplayTarget"
        static let windowSpaceBehavior = "docky.windowSpaceBehavior"
        static let autohidesWindow = "docky.autohidesWindow"
        static let opensAtLogin = "docky.opensAtLogin"
        static let autohideWindowDelay = "docky.autohideWindowDelay"
        static let hidesSystemDock = "docky.hidesSystemDock"
        static let overflowBehavior = "docky.overflowBehavior"
        static let windowAxisSizing = "docky.windowAxisSizing"
        static let enablesWidgetHoverPreview = "docky.enablesWidgetHoverPreview"
        static let widgetHoverPreviewSpans = "docky.widgetHoverPreviewSpans"
        static let widgetHoverPreviewDelay = "docky.widgetHoverGrowDelay"
        static let showsActivePinnedSeparator = "docky.showsActivePinnedSeparator"
        static let showsRunningApps = "docky.showsRunningApps"
        static let showsMinimizedWindows = "docky.showsMinimizedWindows"
        static let appTileFrontmostClickBehavior = "docky.appTileFrontmostClickBehavior"
        static let activeIndicatorShape = "docky.activeIndicatorShape"
        static let activeIndicatorImagePath = "docky.activeIndicatorImagePath"
        static let activeIndicatorColor = "docky.activeIndicatorColor"
        static let appIconOverrides = "docky.appIconOverrides"
        static let hiddenAppBundleIdentifiers = "docky.hiddenAppBundleIdentifiers"
        static let showsGroupedOpenedAppsInDock = "docky.showsGroupedOpenedAppsInDock"
        static let enablesLaunchpadOverlay = "docky.enablesLaunchpadOverlay"
        static let launchpadGridColumnCount = "docky.launchpadGridColumnCount"
        static let launchpadShortcut = "docky.launchpadShortcut"
        static let enablesWindowSwitcher = "docky.enablesWindowSwitcher"
        static let windowSwitcherShortcut = "docky.windowSwitcherShortcut"
        static let showsWindowSwitcherFocusPreview = "docky.showsWindowSwitcherFocusPreview"
        static let windowSwitcherPreviewMode = "docky.windowSwitcherPreviewMode"
        static let pinnedAppBundleIdentifiers = "docky.pinnedAppBundleIdentifiers"
        static let pinnedItems = "docky.pinnedItems"
        static let widgetPlacements = "docky.widgetPlacements"
        static let appWidgetDisplays = "docky.appWidgetDisplays"
        static let trailingItems = "docky.trailingItems"
        static let hasSeenDockEditorHint = "docky.hasSeenDockEditorHint"
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
        static let windowDisplayTarget: DockWindowDisplayTarget = .primaryDisplay
        static let windowSpaceBehavior: DockWindowSpaceBehavior = .allSpaces
        static let autohidesWindow = false
        static let opensAtLogin = true
        static let autohideWindowDelay: TimeInterval = 0.5
        static let hidesSystemDock = true
        static let overflowBehavior: DockOverflowBehavior = .rescale
        static let windowAxisSizing: DockWindowAxisSizing = .fitContent
        static let enablesWidgetHoverPreview = true
        static let widgetHoverPreviewSpans: Set<TileSpan> = Set(TileSpan.allCases)
        static let widgetHoverPreviewDelay: TimeInterval = 1
        static let showsActivePinnedSeparator = true
        static let showsRunningApps = true
        static let showsMinimizedWindows = true
        static let appTileFrontmostClickBehavior: AppTileFrontmostClickBehavior = .none
        static let activeIndicatorShape: DockTileIndicatorShape = .dot
        static let activeIndicatorImagePath: String? = nil
        static let activeIndicatorColor: DockColor? = nil
        static let appIconOverrides: [AppIconOverride] = []
        static let hiddenAppBundleIdentifiers: [String] = []
        static let showsGroupedOpenedAppsInDock = true
        static let enablesLaunchpadOverlay = true
        static let launchpadGridColumnCount = 7
        static let launchpadShortcut = KeyboardShortcut.empty
        static let enablesWindowSwitcher = true
        static let windowSwitcherShortcut = KeyboardShortcut(keyCode: 48, modifierFlags: [.option])
        static let showsWindowSwitcherFocusPreview = true
        static let windowSwitcherPreviewMode: WindowSwitcherPreviewMode = .inPlace
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
        let storedWindowPosition = defaults.string(forKey: Keys.windowPosition)
        let storedWindowDisplayTarget = defaults.string(forKey: Keys.windowDisplayTarget)
        let storedWindowSpaceBehavior = defaults.string(forKey: Keys.windowSpaceBehavior)
        let storedAutohidesWindow = defaults.object(forKey: Keys.autohidesWindow) as? Bool
        let storedOpensAtLogin = defaults.object(forKey: Keys.opensAtLogin) as? Bool
        let storedAutohideWindowDelay = defaults.object(forKey: Keys.autohideWindowDelay) as? Double
        let storedHidesSystemDock = defaults.object(forKey: Keys.hidesSystemDock) as? Bool
        let storedOverflowBehavior = defaults.string(forKey: Keys.overflowBehavior)
        let storedWindowAxisSizing = defaults.string(forKey: Keys.windowAxisSizing)
        let storedEnablesWidgetHoverPreview = defaults.object(forKey: Keys.enablesWidgetHoverPreview) as? Bool
        let storedWidgetHoverPreviewSpans = defaults.array(forKey: Keys.widgetHoverPreviewSpans) as? [Int]
        let storedWidgetHoverPreviewDelay = defaults.object(forKey: Keys.widgetHoverPreviewDelay) as? Double
        let storedShowsActivePinnedSeparator = defaults.object(forKey: Keys.showsActivePinnedSeparator) as? Bool
        let storedShowsRunningApps = defaults.object(forKey: Keys.showsRunningApps) as? Bool
        let storedShowsMinimizedWindows = defaults.object(forKey: Keys.showsMinimizedWindows) as? Bool
        let storedAppTileFrontmostClickBehavior = defaults.string(forKey: Keys.appTileFrontmostClickBehavior)
        let storedActiveIndicatorShape = defaults.string(forKey: Keys.activeIndicatorShape)
        let storedActiveIndicatorImagePath = defaults.string(forKey: Keys.activeIndicatorImagePath)
        let storedActiveIndicatorColor = defaults.data(forKey: Keys.activeIndicatorColor)
        let storedAppIconOverrides = defaults.data(forKey: Keys.appIconOverrides)
        let storedHiddenAppBundleIdentifiers = defaults.stringArray(forKey: Keys.hiddenAppBundleIdentifiers)
        let storedShowsGroupedOpenedAppsInDock = defaults.object(forKey: Keys.showsGroupedOpenedAppsInDock) as? Bool
        let storedEnablesLaunchpadOverlay = defaults.object(forKey: Keys.enablesLaunchpadOverlay) as? Bool
        let storedLaunchpadGridColumnCount = defaults.object(forKey: Keys.launchpadGridColumnCount) as? Int
        let storedLaunchpadShortcut = defaults.data(forKey: Keys.launchpadShortcut)
        let storedEnablesWindowSwitcher = defaults.object(forKey: Keys.enablesWindowSwitcher) as? Bool
        let storedWindowSwitcherShortcut = defaults.data(forKey: Keys.windowSwitcherShortcut)
        let storedShowsWindowSwitcherFocusPreview = defaults.object(forKey: Keys.showsWindowSwitcherFocusPreview) as? Bool
        let storedWindowSwitcherPreviewMode = defaults.string(forKey: Keys.windowSwitcherPreviewMode)
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
        self.windowPosition = (storedWindowPosition.flatMap(DockWindowPosition.init(rawValue:)) ?? DefaultValues.windowPosition)
        self.windowDisplayTarget = (storedWindowDisplayTarget.flatMap(DockWindowDisplayTarget.init(rawValue:)) ?? DefaultValues.windowDisplayTarget)
        self.windowSpaceBehavior = (storedWindowSpaceBehavior.flatMap(DockWindowSpaceBehavior.init(rawValue:)) ?? DefaultValues.windowSpaceBehavior)
        self.autohidesWindow = storedAutohidesWindow ?? DefaultValues.autohidesWindow
        self.opensAtLogin = storedOpensAtLogin ?? LaunchAtLoginService.shared.isEnabled
        self.autohideWindowDelay = max(storedAutohideWindowDelay ?? DefaultValues.autohideWindowDelay, 0)
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
        self.appTileFrontmostClickBehavior = storedAppTileFrontmostClickBehavior
            .flatMap(AppTileFrontmostClickBehavior.init(rawValue:))
            ?? DefaultValues.appTileFrontmostClickBehavior
        self.activeIndicatorShape = (storedActiveIndicatorShape.flatMap(DockTileIndicatorShape.init(rawValue:)) ?? DefaultValues.activeIndicatorShape)
        self.activeIndicatorImagePath = storedActiveIndicatorImagePath ?? DefaultValues.activeIndicatorImagePath
        self.activeIndicatorColor = Self.decodeColor(from: storedActiveIndicatorColor) ?? DefaultValues.activeIndicatorColor
        self.appIconOverrides = Self.decodeAppIconOverrides(from: storedAppIconOverrides) ?? DefaultValues.appIconOverrides
        self.hiddenAppBundleIdentifiers = Self.normalizedBundleIdentifiers(storedHiddenAppBundleIdentifiers ?? DefaultValues.hiddenAppBundleIdentifiers)
        self.showsGroupedOpenedAppsInDock = storedShowsGroupedOpenedAppsInDock ?? DefaultValues.showsGroupedOpenedAppsInDock
        self.enablesLaunchpadOverlay = storedEnablesLaunchpadOverlay ?? DefaultValues.enablesLaunchpadOverlay
        self.launchpadGridColumnCount = max(storedLaunchpadGridColumnCount ?? DefaultValues.launchpadGridColumnCount, 1)
        self.launchpadShortcut = Self.decodeKeyboardShortcut(from: storedLaunchpadShortcut) ?? DefaultValues.launchpadShortcut
        self.enablesWindowSwitcher = storedEnablesWindowSwitcher ?? DefaultValues.enablesWindowSwitcher
        self.windowSwitcherShortcut = Self.decodeKeyboardShortcut(from: storedWindowSwitcherShortcut) ?? DefaultValues.windowSwitcherShortcut
        self.showsWindowSwitcherFocusPreview = storedShowsWindowSwitcherFocusPreview ?? DefaultValues.showsWindowSwitcherFocusPreview
        self.windowSwitcherPreviewMode = storedWindowSwitcherPreviewMode.flatMap(WindowSwitcherPreviewMode.init(rawValue:)) ?? DefaultValues.windowSwitcherPreviewMode
        self.pinnedAppBundleIdentifiers = initialPinnedAppBundleIdentifiers
        self.pinnedItems = initialPinnedItems
        self.widgetPlacements = Self.decodeWidgetPlacements(from: storedWidgetPlacements) ?? DefaultValues.widgetPlacements
        self.appWidgetDisplays = Self.decodeAppWidgetDisplays(from: storedAppWidgetDisplays) ?? DefaultValues.appWidgetDisplays
        self.trailingItems = Self.decodeTrailingItems(from: storedTrailingItems) ?? DefaultValues.trailingItems
        self.hasSeenDockEditorHint = storedHasSeenDockEditorHint ?? DefaultValues.hasSeenDockEditorHint
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
        windowDisplayTarget = DefaultValues.windowDisplayTarget
        windowSpaceBehavior = DefaultValues.windowSpaceBehavior
        autohidesWindow = DefaultValues.autohidesWindow
        opensAtLogin = DefaultValues.opensAtLogin
        autohideWindowDelay = DefaultValues.autohideWindowDelay
        hidesSystemDock = DefaultValues.hidesSystemDock
        overflowBehavior = DefaultValues.overflowBehavior
        windowAxisSizing = DefaultValues.windowAxisSizing
        enablesWidgetHoverPreview = DefaultValues.enablesWidgetHoverPreview
        widgetHoverPreviewSpans = DefaultValues.widgetHoverPreviewSpans
        widgetHoverPreviewDelay = DefaultValues.widgetHoverPreviewDelay
        showsActivePinnedSeparator = DefaultValues.showsActivePinnedSeparator
        showsRunningApps = DefaultValues.showsRunningApps
        showsMinimizedWindows = DefaultValues.showsMinimizedWindows
        appTileFrontmostClickBehavior = DefaultValues.appTileFrontmostClickBehavior
        activeIndicatorShape = DefaultValues.activeIndicatorShape
        activeIndicatorImagePath = DefaultValues.activeIndicatorImagePath
        activeIndicatorColor = DefaultValues.activeIndicatorColor
        appIconOverrides = DefaultValues.appIconOverrides
        hiddenAppBundleIdentifiers = DefaultValues.hiddenAppBundleIdentifiers
        showsGroupedOpenedAppsInDock = DefaultValues.showsGroupedOpenedAppsInDock
        enablesLaunchpadOverlay = DefaultValues.enablesLaunchpadOverlay
        launchpadGridColumnCount = DefaultValues.launchpadGridColumnCount
        launchpadShortcut = DefaultValues.launchpadShortcut
        enablesWindowSwitcher = DefaultValues.enablesWindowSwitcher
        windowSwitcherShortcut = DefaultValues.windowSwitcherShortcut
        showsWindowSwitcherFocusPreview = DefaultValues.showsWindowSwitcherFocusPreview
        windowSwitcherPreviewMode = DefaultValues.windowSwitcherPreviewMode
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

    private static func normalizedBundleIdentifiers(_ bundleIdentifiers: [String]) -> [String] {
        Array(Set(bundleIdentifiers.filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
