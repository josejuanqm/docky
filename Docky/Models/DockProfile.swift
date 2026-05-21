//
//  DockProfile.swift
//  Docky
//
//  Persistent per-profile snapshot of the dock's tile-store fields. Each
//  profile owns its own pinned/trailing items, widget placements, app
//  widget displays, and hidden-app list. The user switches between them
//  via the profile-switcher ball at the leading edge of the dock; the
//  remaining preferences (theme, sizing, behavior, shortcuts) stay global.
//

import Foundation

struct DockProfile: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var symbolName: String
    var dateCreated: Date
    var pinnedItems: [PinnedTileItem]
    var trailingItems: [TrailingTileItem]
    var widgetPlacements: [WidgetPlacement]
    var appWidgetDisplays: [AppWidgetDisplay]
    var hiddenAppBundleIdentifiers: [String]
    /// Auto-switch rules. Empty means the profile only activates manually.
    /// Decoded with `decodeIfPresent` so blobs persisted before this
    /// field existed still round-trip.
    var triggers: [ProfileTrigger]

    init(
        id: String = UUID().uuidString,
        name: String,
        symbolName: String = "house.fill",
        dateCreated: Date = Date(),
        pinnedItems: [PinnedTileItem] = [],
        trailingItems: [TrailingTileItem] = [],
        widgetPlacements: [WidgetPlacement] = [],
        appWidgetDisplays: [AppWidgetDisplay] = [],
        hiddenAppBundleIdentifiers: [String] = [],
        triggers: [ProfileTrigger] = []
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.dateCreated = dateCreated
        self.pinnedItems = pinnedItems
        self.trailingItems = trailingItems
        self.widgetPlacements = widgetPlacements
        self.appWidgetDisplays = appWidgetDisplays
        self.hiddenAppBundleIdentifiers = hiddenAppBundleIdentifiers
        self.triggers = triggers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        pinnedItems = try container.decode([PinnedTileItem].self, forKey: .pinnedItems)
        trailingItems = try container.decode([TrailingTileItem].self, forKey: .trailingItems)
        widgetPlacements = try container.decode([WidgetPlacement].self, forKey: .widgetPlacements)
        appWidgetDisplays = try container.decode([AppWidgetDisplay].self, forKey: .appWidgetDisplays)
        hiddenAppBundleIdentifiers = try container.decode([String].self, forKey: .hiddenAppBundleIdentifiers)
        triggers = try container.decodeIfPresent([ProfileTrigger].self, forKey: .triggers) ?? []
    }
}
