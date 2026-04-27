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
    case minimizedWindow(MinimizedWindowTile)
    case appFolder(AppFolderTile)
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

struct MinimizedWindowTile: Equatable {
    let windowIdentifier: String
    let windowNumber: Int?
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let appDisplayName: String
    let windowTitle: String
    let previewLookupIndex: Int
}

struct AppFolderTile: Equatable {
    let identifier: String
    let displayName: String
    let apps: [AppTile]
    let contentViewMode: FolderTileContentViewMode

    nonisolated init(
        identifier: String,
        displayName: String,
        apps: [AppTile],
        contentViewMode: FolderTileContentViewMode = .grid
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.apps = apps
        self.contentViewMode = contentViewMode
    }

    nonisolated var bundleIdentifiers: [String] {
        apps.map(\.bundleIdentifier)
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

    var title: String {
        switch self {
        case .calendar:
            "Calendar"
        case .calendarDate:
            "Date"
        case .reminders:
            "Reminders"
        case .batteries:
            "Batteries"
        case .systemStatus:
            "System Status"
        case .nowPlaying:
            "Now Playing"
        case .weather:
            "Weather"
        }
    }

    var supportedSpans: [TileSpan] {
        switch self {
        case .calendarDate:
            [.one]
        case .calendar, .reminders, .batteries, .systemStatus, .nowPlaying, .weather:
            TileSpan.allCases
        }
    }
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

    nonisolated init(
        url: URL,
        displayName: String,
        displayMode: FolderTileDisplayMode,
        contentViewMode: FolderTileContentViewMode = .grid
    ) {
        self.url = url
        self.displayName = displayName
        self.displayMode = displayMode
        self.contentViewMode = contentViewMode
    }
}
