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
}

struct MinimizedWindowTile: Equatable {
    let windowIdentifier: String
    let windowNumber: Int?
    let bundleIdentifier: String
    let appDisplayName: String
    let windowTitle: String
}

struct AppFolderTile: Equatable {
    let identifier: String
    let displayName: String
    let apps: [AppTile]

    nonisolated var bundleIdentifiers: [String] {
        apps.map(\.bundleIdentifier)
    }
}

enum WidgetKind: String, CaseIterable, Codable, Identifiable {
    case nowPlaying

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying:
            "Now Playing"
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

struct WidgetTile: Equatable {
    let identifier: String
    let title: String
    let kind: WidgetKind
    let ownerBundleIdentifier: String
    let span: TileSpan

    var effectiveSpan: TileSpan {
        span
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
}
