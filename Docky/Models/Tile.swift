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
    case widget(WidgetTile)
    case folder(FolderTile)
    case spacer
    case divider
    case trash
}

struct AppTile: Equatable {
    let bundleIdentifier: String
    let displayName: String
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
}

struct FolderTile: Equatable {
    let url: URL
    let displayName: String
}
