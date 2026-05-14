//
//  TrashTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct TrashTileView: View {
    @ObservedObject private var trash = TrashService.shared
    @Bindable private var preferences = DockyPreferences.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(overridePadding(in: proxy.size))
                    .opacity(trash.hasAccess ? 1 : 0.45)

                if !trash.hasAccess {
                    // Sandboxed-build affordance: a small key badge
                    // signals that the tile needs a one-time grant.
                    // Tapping the tile triggers `TrashService.requestAccess()`
                    // via `TileView.handleTap`, opening the NSOpenPanel
                    // pre-filled to `~/.Trash`.
                    Image(systemName: "key.horizontal.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: proxy.size.width * 0.32,
                               height: proxy.size.width * 0.32)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(2)
                }
            }
        }
    }

    private func overridePadding(in size: CGSize) -> CGFloat {
        let state: TrashIconState = trash.isEmpty ? .empty : .full
        guard preferences.effectiveTrashIconOverrideURL(forState: state) != nil else {
            return 0
        }
        return preferences.trashIconOverridePadding(forState: state) * min(size.width, size.height)
    }

    private var icon: NSImage {
        let state: TrashIconState = trash.isEmpty ? .empty : .full

        if let overrideURL = preferences.effectiveTrashIconOverrideURL(forState: state),
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return NSImage(named: state.systemImageName)
            ?? NSImage(named: TrashIconState.empty.systemImageName)
            ?? NSImage()
    }
}
