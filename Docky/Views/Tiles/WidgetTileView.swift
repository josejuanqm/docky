//
//  WidgetTileView.swift
//  Docky
//

import SwiftUI

struct WidgetTileView: View {
    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool

    var body: some View {
        switch tile.kind {
        case .calendar, .calendarDate:
            CalendarWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack
            )
        case .reminders:
            RemindersWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack
            )
        case .batteries:
            BatteriesWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack
            )
        case .systemStatus:
            SystemStatusWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack
            )
        case .nowPlaying:
            NowPlayingWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack
            )
        case .weather:
            WeatherWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack
            )
        }
    }
}
