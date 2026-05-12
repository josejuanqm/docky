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
    case widget(WidgetTile)
    case smartStack(SmartStackTile)
    case folder(FolderTile)
    case spacer
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

enum WidgetKind: String, CaseIterable, Codable, Identifiable {
    case calendar
    case calendarDate
    case reminders
    case batteries
    case systemStatus
    case nowPlaying
    case weather

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
        }
    }

    nonisolated var supportedSpans: [TileSpan] {
        switch self {
        case .calendarDate:
            [.one]
        case .calendar, .reminders, .batteries, .systemStatus, .nowPlaying, .weather:
            TileSpan.allCases
        }
    }

    nonisolated var expansionExtent: WidgetExpansionExtent {
        switch self {
        case .nowPlaying:
            WidgetExpansionExtent(widthTiles: 5, heightTiles: 2)
        case .calendar, .calendarDate, .reminders, .batteries, .systemStatus, .weather:
            .standard
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
