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
            widgetKind: nil,
            widgetOwnerBundleIdentifier: nil,
            widgetSpan: nil,
            hiddenWidgetOwnerBundleIdentifiers: []
        )
    }

    nonisolated static func appFolder(
        id: String = "custom:\(UUID().uuidString)",
        displayName: String = "Folder",
        bundleIdentifiers: [String]
    ) -> Self {
        Self(
            id: id,
            kind: .appFolder,
            bundleIdentifier: nil,
            folderDisplayName: displayName,
            folderBundleIdentifiers: bundleIdentifiers,
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
            bundleIdentifier: nil,
            folderDisplayName: nil,
            folderBundleIdentifiers: [],
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Grid"
        case .list: "List"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? Self.grid.rawValue

        switch rawValue {
        case Self.list.rawValue:
            self = .list
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

    /// Corner radius applied to the main dock window.
    @Published var windowCornerRadius: CGFloat {
        didSet {
            guard windowCornerRadius != oldValue else { return }
            defaults.set(Double(windowCornerRadius), forKey: Keys.windowCornerRadius)
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

    /// Whether opened apps from an app folder should appear grouped beside that folder.
    @Published var showsGroupedOpenedAppsInDock: Bool {
        didSet {
            guard showsGroupedOpenedAppsInDock != oldValue else { return }
            defaults.set(showsGroupedOpenedAppsInDock, forKey: Keys.showsGroupedOpenedAppsInDock)
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

    static var defaultWindowTintColor: NSColor {
        NSColor.windowBackgroundColor.blended(withFraction: 0.18, of: .black) ?? .windowBackgroundColor
    }

    private enum Keys {
        static let tileVerticalPadding = "docky.tileVerticalPadding"
        static let tileSpacing = "docky.tileSpacing"
        static let windowCornerRadius = "docky.windowCornerRadius"
        static let windowTintColor = "docky.windowTintColor"
        static let windowTintOpacity = "docky.windowTintOpacity"
        static let windowBackgroundImagePath = "docky.windowBackgroundImagePath"
        static let windowPosition = "docky.windowPosition"
        static let autohidesWindow = "docky.autohidesWindow"
        static let activeIndicatorShape = "docky.activeIndicatorShape"
        static let activeIndicatorImagePath = "docky.activeIndicatorImagePath"
        static let activeIndicatorColor = "docky.activeIndicatorColor"
        static let showsGroupedOpenedAppsInDock = "docky.showsGroupedOpenedAppsInDock"
        static let pinnedAppBundleIdentifiers = "docky.pinnedAppBundleIdentifiers"
        static let pinnedItems = "docky.pinnedItems"
        static let widgetPlacements = "docky.widgetPlacements"
        static let trailingItems = "docky.trailingItems"
    }

    private enum DefaultValues {
        static let tileVerticalPadding: CGFloat = 16
        static let tileSpacing: CGFloat = 0
        static let windowCornerRadius: CGFloat = 24
        static let windowTintColor: DockColor? = nil
        static let windowTintOpacity: CGFloat = 0.22
        static let windowBackgroundImagePath: String? = nil
        static let windowPosition: DockWindowPosition = .system
        static let autohidesWindow = false
        static let activeIndicatorShape: DockTileIndicatorShape = .dot
        static let activeIndicatorImagePath: String? = nil
        static let activeIndicatorColor: DockColor? = nil
        static let showsGroupedOpenedAppsInDock = true
        static let pinnedAppBundleIdentifiers: [String] = []
        static let pinnedItems: [PinnedTileItem] = []
        static let widgetPlacements: [WidgetPlacement] = []
        static let trailingItems: [TrailingTileItem] = []
    }

    private init() {
        self.defaults = .standard
        let storedVerticalPadding = defaults.object(forKey: Keys.tileVerticalPadding) as? Double
        let storedTileSpacing = defaults.object(forKey: Keys.tileSpacing) as? Double
        let storedWindowCornerRadius = defaults.object(forKey: Keys.windowCornerRadius) as? Double
        let storedWindowTintColor = defaults.data(forKey: Keys.windowTintColor)
        let storedWindowTintOpacity = defaults.object(forKey: Keys.windowTintOpacity) as? Double
        let storedWindowBackgroundImagePath = defaults.string(forKey: Keys.windowBackgroundImagePath)
        let storedWindowPosition = defaults.string(forKey: Keys.windowPosition)
        let storedAutohidesWindow = defaults.object(forKey: Keys.autohidesWindow) as? Bool
        let storedActiveIndicatorShape = defaults.string(forKey: Keys.activeIndicatorShape)
        let storedActiveIndicatorImagePath = defaults.string(forKey: Keys.activeIndicatorImagePath)
        let storedActiveIndicatorColor = defaults.data(forKey: Keys.activeIndicatorColor)
        let storedShowsGroupedOpenedAppsInDock = defaults.object(forKey: Keys.showsGroupedOpenedAppsInDock) as? Bool
        let storedPinnedAppBundleIdentifiers = defaults.stringArray(forKey: Keys.pinnedAppBundleIdentifiers)
        let storedPinnedItems = defaults.data(forKey: Keys.pinnedItems)
        let storedWidgetPlacements = defaults.data(forKey: Keys.widgetPlacements)
        let storedTrailingItems = defaults.data(forKey: Keys.trailingItems)
        let initialPinnedAppBundleIdentifiers = storedPinnedAppBundleIdentifiers ?? DefaultValues.pinnedAppBundleIdentifiers
        let initialPinnedItems = Self.decodePinnedItems(from: storedPinnedItems)
            ?? initialPinnedAppBundleIdentifiers.map(PinnedTileItem.app(bundleIdentifier:))
        self.tileVerticalPadding = storedVerticalPadding.map { CGFloat($0) } ?? DefaultValues.tileVerticalPadding
        self.tileSpacing = storedTileSpacing.map { CGFloat($0) } ?? DefaultValues.tileSpacing
        self.windowCornerRadius = storedWindowCornerRadius.map { CGFloat($0) } ?? DefaultValues.windowCornerRadius
        self.windowTintColor = Self.decodeColor(from: storedWindowTintColor) ?? DefaultValues.windowTintColor
        self.windowTintOpacity = storedWindowTintOpacity.map { CGFloat($0) } ?? DefaultValues.windowTintOpacity
        self.windowBackgroundImagePath = storedWindowBackgroundImagePath ?? DefaultValues.windowBackgroundImagePath
        self.windowPosition = (storedWindowPosition.flatMap(DockWindowPosition.init(rawValue:)) ?? DefaultValues.windowPosition)
        self.autohidesWindow = storedAutohidesWindow ?? DefaultValues.autohidesWindow
        self.activeIndicatorShape = (storedActiveIndicatorShape.flatMap(DockTileIndicatorShape.init(rawValue:)) ?? DefaultValues.activeIndicatorShape)
        self.activeIndicatorImagePath = storedActiveIndicatorImagePath ?? DefaultValues.activeIndicatorImagePath
        self.activeIndicatorColor = Self.decodeColor(from: storedActiveIndicatorColor) ?? DefaultValues.activeIndicatorColor
        self.showsGroupedOpenedAppsInDock = storedShowsGroupedOpenedAppsInDock ?? DefaultValues.showsGroupedOpenedAppsInDock
        self.pinnedAppBundleIdentifiers = initialPinnedAppBundleIdentifiers
        self.pinnedItems = initialPinnedItems
        self.widgetPlacements = Self.decodeWidgetPlacements(from: storedWidgetPlacements) ?? DefaultValues.widgetPlacements
        self.trailingItems = Self.decodeTrailingItems(from: storedTrailingItems) ?? DefaultValues.trailingItems
    }

    func resetToDefaults() {
        tileVerticalPadding = DefaultValues.tileVerticalPadding
        tileSpacing = DefaultValues.tileSpacing
        windowCornerRadius = DefaultValues.windowCornerRadius
        windowTintColor = DefaultValues.windowTintColor
        windowTintOpacity = DefaultValues.windowTintOpacity
        windowBackgroundImagePath = DefaultValues.windowBackgroundImagePath
        windowPosition = DefaultValues.windowPosition
        autohidesWindow = DefaultValues.autohidesWindow
        activeIndicatorShape = DefaultValues.activeIndicatorShape
        activeIndicatorImagePath = DefaultValues.activeIndicatorImagePath
        activeIndicatorColor = DefaultValues.activeIndicatorColor
        showsGroupedOpenedAppsInDock = DefaultValues.showsGroupedOpenedAppsInDock
        pinnedAppBundleIdentifiers = DefaultValues.pinnedAppBundleIdentifiers
        pinnedItems = DefaultValues.pinnedItems
        widgetPlacements = DefaultValues.widgetPlacements
        trailingItems = DefaultValues.trailingItems
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
