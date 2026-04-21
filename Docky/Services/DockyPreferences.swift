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

import Combine
import Foundation

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
    case dot
    case pill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dot: "Dot"
        case .pill: "Pill"
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

    /// Corner radius applied to the main dock window.
    @Published var windowCornerRadius: CGFloat {
        didSet {
            guard windowCornerRadius != oldValue else { return }
            defaults.set(Double(windowCornerRadius), forKey: Keys.windowCornerRadius)
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

    /// Docky-owned ordered pinned app bundle identifiers.
    @Published var pinnedAppBundleIdentifiers: [String] {
        didSet {
            guard pinnedAppBundleIdentifiers != oldValue else { return }
            defaults.set(pinnedAppBundleIdentifiers, forKey: Keys.pinnedAppBundleIdentifiers)
        }
    }

    /// Enabled widgets grouped by the app tile they extend.
    @Published var widgetPlacements: [WidgetPlacement] {
        didSet {
            guard widgetPlacements != oldValue else { return }
            persistWidgetPlacements(widgetPlacements)
        }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static let tileVerticalPadding = "docky.tileVerticalPadding"
        static let tileSpacing = "docky.tileSpacing"
        static let windowCornerRadius = "docky.windowCornerRadius"
        static let windowPosition = "docky.windowPosition"
        static let autohidesWindow = "docky.autohidesWindow"
        static let activeIndicatorShape = "docky.activeIndicatorShape"
        static let pinnedAppBundleIdentifiers = "docky.pinnedAppBundleIdentifiers"
        static let widgetPlacements = "docky.widgetPlacements"
    }

    private enum DefaultValues {
        static let tileVerticalPadding: CGFloat = 16
        static let tileSpacing: CGFloat = 0
        static let windowCornerRadius: CGFloat = 24
        static let windowPosition: DockWindowPosition = .system
        static let autohidesWindow = false
        static let activeIndicatorShape: DockTileIndicatorShape = .dot
        static let pinnedAppBundleIdentifiers: [String] = []
        static let widgetPlacements: [WidgetPlacement] = []
    }

    private init() {
        self.defaults = .standard
        let storedVerticalPadding = defaults.object(forKey: Keys.tileVerticalPadding) as? Double
        let storedTileSpacing = defaults.object(forKey: Keys.tileSpacing) as? Double
        let storedWindowCornerRadius = defaults.object(forKey: Keys.windowCornerRadius) as? Double
        let storedWindowPosition = defaults.string(forKey: Keys.windowPosition)
        let storedAutohidesWindow = defaults.object(forKey: Keys.autohidesWindow) as? Bool
        let storedActiveIndicatorShape = defaults.string(forKey: Keys.activeIndicatorShape)
        let storedPinnedAppBundleIdentifiers = defaults.stringArray(forKey: Keys.pinnedAppBundleIdentifiers)
        let storedWidgetPlacements = defaults.data(forKey: Keys.widgetPlacements)
        self.tileVerticalPadding = storedVerticalPadding.map { CGFloat($0) } ?? DefaultValues.tileVerticalPadding
        self.tileSpacing = storedTileSpacing.map { CGFloat($0) } ?? DefaultValues.tileSpacing
        self.windowCornerRadius = storedWindowCornerRadius.map { CGFloat($0) } ?? DefaultValues.windowCornerRadius
        self.windowPosition = (storedWindowPosition.flatMap(DockWindowPosition.init(rawValue:)) ?? DefaultValues.windowPosition)
        self.autohidesWindow = storedAutohidesWindow ?? DefaultValues.autohidesWindow
        self.activeIndicatorShape = (storedActiveIndicatorShape.flatMap(DockTileIndicatorShape.init(rawValue:)) ?? DefaultValues.activeIndicatorShape)
        self.pinnedAppBundleIdentifiers = storedPinnedAppBundleIdentifiers ?? DefaultValues.pinnedAppBundleIdentifiers
        self.widgetPlacements = Self.decodeWidgetPlacements(from: storedWidgetPlacements) ?? DefaultValues.widgetPlacements
    }

    func resetToDefaults() {
        tileVerticalPadding = DefaultValues.tileVerticalPadding
        tileSpacing = DefaultValues.tileSpacing
        windowCornerRadius = DefaultValues.windowCornerRadius
        windowPosition = DefaultValues.windowPosition
        autohidesWindow = DefaultValues.autohidesWindow
        activeIndicatorShape = DefaultValues.activeIndicatorShape
        pinnedAppBundleIdentifiers = DefaultValues.pinnedAppBundleIdentifiers
        widgetPlacements = DefaultValues.widgetPlacements
    }

    private func persistWidgetPlacements(_ placements: [WidgetPlacement]) {
        guard let data = try? encoder.encode(placements) else {
            defaults.removeObject(forKey: Keys.widgetPlacements)
            return
        }

        defaults.set(data, forKey: Keys.widgetPlacements)
    }

    private static func decodeWidgetPlacements(from data: Data?) -> [WidgetPlacement]? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode([WidgetPlacement].self, from: data)
    }
}
