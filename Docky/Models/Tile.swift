//
//  Tile.swift
//  Docky
//

import Foundation

struct Tile: Identifiable, Equatable {
    let id: String
    var content: TileContent

    nonisolated init(id: String = UUID().uuidString, content: TileContent) {
        self.id = id
        self.content = content
    }
}

enum TileContent: Equatable {
    case app(AppTile)
    case minimizedWindow(AppWindow)
    case appFolder(AppFolderTile)
    case launchpad(LaunchpadTile)
    case startMenu(StartMenuTile)
    case widget(WidgetTile)
    case smartStack(SmartStackTile)
    case folder(FolderTile)
    case spacer
    case flexibleSpacer
    case divider
    case trash
}

struct AppTile: Equatable {
    let bundleIdentifier: String
    let displayName: String
    let displayedWidget: WidgetTile?

    nonisolated init(
        bundleIdentifier: String,
        displayName: String,
        displayedWidget: WidgetTile? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.displayedWidget = displayedWidget
    }
}

struct AppFolderTile: Equatable {
    let identifier: String
    let displayName: String
    let apps: [AppTile]
    let displayMode: AppFolderTileDisplayMode
    let contentViewMode: FolderTileContentViewMode

    nonisolated init(
        identifier: String,
        displayName: String,
        apps: [AppTile],
        displayMode: AppFolderTileDisplayMode = .grid,
        contentViewMode: FolderTileContentViewMode = .grid
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.apps = apps
        self.displayMode = displayMode
        self.contentViewMode = contentViewMode
    }

    nonisolated var bundleIdentifiers: [String] {
        apps.map(\.bundleIdentifier)
    }
}

struct LaunchpadTile: Equatable {
    nonisolated static let spotlightBundleIdentifier = "com.apple.Spotlight"

    let identifier: String
    let title: String

    nonisolated init(identifier: String, title: String = "Launchpad") {
        self.identifier = identifier
        self.title = title
    }
}

/// Tile that, when clicked, toggles Docky's Start menu overlay. Renders
/// as a regular AppTileView pointed at Docky's own bundle id so the icon
/// pipeline resolves to the running app icon (and the user can swap it
/// out via the App Icons settings pane like the Launchpad tile).
struct StartMenuTile: Equatable {
    nonisolated static let iconBundleIdentifier = "gt.quintero.Docky"

    let identifier: String
    let title: String

    nonisolated init(identifier: String, title: String = "Start") {
        self.identifier = identifier
        self.title = title
    }
}

enum WidgetKind: Codable, Identifiable, Hashable {
    case calendar
    case calendarDate
    case reminders
    case batteries
    case systemStatus
    case nowPlaying
    case weather
    case search
    case photoFrame
    /// Widget supplied by a community bundle loaded at startup. The
    /// associated value is the plugin's stable identifier (e.g.
    /// "com.example.MyWidget"); the live registration is owned by
    /// ExternalWidgetRegistry.
    case external(String)

    nonisolated static let builtInCases: [WidgetKind] = [
        .calendar,
        .calendarDate,
        .reminders,
        .batteries,
        .systemStatus,
        .nowPlaying,
        .weather,
        .search,
        .photoFrame,
    ]

    /// Round-trips through DockyPreferences / persistence as a single
    /// string. External widgets use an `external:<identifier>` prefix
    /// so existing values stay valid and unknown values can be
    /// detected by inspecting the prefix.
    nonisolated var rawValue: String {
        switch self {
        case .calendar: "calendar"
        case .calendarDate: "calendarDate"
        case .reminders: "reminders"
        case .batteries: "batteries"
        case .systemStatus: "systemStatus"
        case .nowPlaying: "nowPlaying"
        case .weather: "weather"
        case .search: "search"
        case .photoFrame: "photoFrame"
        case .external(let identifier): "external:\(identifier)"
        }
    }

    nonisolated init?(rawValue: String) {
        if rawValue.hasPrefix("external:") {
            let identifier = String(rawValue.dropFirst("external:".count))
            guard !identifier.isEmpty else { return nil }
            self = .external(identifier)
            return
        }
        switch rawValue {
        case "calendar": self = .calendar
        case "calendarDate": self = .calendarDate
        case "reminders": self = .reminders
        case "batteries": self = .batteries
        case "systemStatus": self = .systemStatus
        case "nowPlaying": self = .nowPlaying
        case "weather": self = .weather
        case "search": self = .search
        case "photoFrame": self = .photoFrame
        default: return nil
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let kind = WidgetKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown WidgetKind rawValue: \(raw)"
            )
        }
        self = kind
    }

    var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .calendar:
            String(localized: "Calendar")
        case .calendarDate:
            String(localized: "Date")
        case .reminders:
            String(localized: "Reminders")
        case .batteries:
            String(localized: "Batteries")
        case .systemStatus:
            String(localized: "System Status")
        case .nowPlaying:
            String(localized: "Now Playing")
        case .weather:
            String(localized: "Weather")
        case .search:
            String(localized: "Search")
        case .photoFrame:
            String(localized: "Photo Frame")
        case .external(let identifier):
            ExternalWidgetRegistry.shared.metadata(for: identifier)?.displayName ?? identifier
        }
    }

    nonisolated var supportedSpans: [TileSpan] {
        switch self {
        case .calendarDate:
            [.one]
        case .calendar, .reminders, .batteries, .systemStatus, .nowPlaying, .weather, .search, .photoFrame:
            TileSpan.allCases
        case .external(let identifier):
            ExternalWidgetRegistry.shared.metadata(for: identifier)?.supportedSpans ?? TileSpan.allCases
        }
    }

    nonisolated var expansionExtent: WidgetExpansionExtent {
        switch self {
        case .nowPlaying:
            WidgetExpansionExtent(widthTiles: 5, heightTiles: 2)
        case .calendar, .calendarDate, .reminders, .batteries, .systemStatus, .weather, .search, .photoFrame:
            .standard
        case .external(let identifier):
            ExternalWidgetRegistry.shared.metadata(for: identifier)?.expansionExtent ?? .standard
        }
    }

    /// Whether hovering this widget triggers the larger preview window
    /// after the dwell delay. Defaults to `true` for widgets that have
    /// genuine extra content at expanded size. Widgets whose 1x/2x/3x
    /// representation IS the full thing (search field, calendar date)
    /// stay inline.
    nonisolated var isExpandable: Bool {
        switch self {
        case .calendar, .reminders, .batteries, .systemStatus, .nowPlaying, .weather, .photoFrame:
            true
        case .calendarDate, .search:
            false
        case .external(let identifier):
            ExternalWidgetRegistry.shared.metadata(for: identifier)?.isExpandable ?? false
        }
    }
}

struct WidgetExpansionExtent: Equatable {
    let widthTiles: Int
    let heightTiles: Int

    static let standard = WidgetExpansionExtent(widthTiles: 3, heightTiles: 3)
}

enum TileSpan: Int, CaseIterable, Codable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    /// Theme-only span. Not surfaced in the user's widget palette /
    /// "Span" submenu, themes can inject `"span": 4` via
    /// `layout.insertions` for extra-wide affordances (a stretched
    /// search bar, a wide weather rail, etc.).
    case four = 4

    var id: Int { rawValue }
}

struct WidgetPlacement: Codable, Equatable, Identifiable {
    let kind: WidgetKind
    let ownerBundleIdentifier: String
    let span: TileSpan

    var id: String {
        "\(ownerBundleIdentifier):\(kind.rawValue)"
    }
}

struct AppWidgetDisplay: Codable, Equatable, Identifiable {
    let bundleIdentifier: String
    let kind: WidgetKind
    let span: TileSpan

    var id: String {
        bundleIdentifier
    }
}

struct WidgetTile: Equatable {
    let identifier: String
    let title: String
    let kind: WidgetKind
    let ownerBundleIdentifier: String
    let span: TileSpan

    var effectiveSpan: TileSpan {
        kind.supportedSpans.contains(span) ? span : kind.supportedSpans.last ?? .one
    }
}

struct SmartStackTile: Equatable {
    let identifier: String
    let title: String
    let widgets: [WidgetTile]
    let span: TileSpan

    var allWidgetOwnerBundleIdentifiers: [String] {
        Array(Set(widgets.map(\.ownerBundleIdentifier))).sorted()
    }
}

struct FolderTile: Equatable {
    let url: URL
    let displayName: String
    let displayMode: FolderTileDisplayMode
    let contentViewMode: FolderTileContentViewMode
    let sortMode: FolderTileSortMode

    nonisolated init(
        url: URL,
        displayName: String,
        displayMode: FolderTileDisplayMode,
        contentViewMode: FolderTileContentViewMode = .grid,
        sortMode: FolderTileSortMode = .dateAdded
    ) {
        self.url = url
        self.displayName = displayName
        self.displayMode = displayMode
        self.contentViewMode = contentViewMode
        self.sortMode = sortMode
    }
}
