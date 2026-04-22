//
//  MinimizedWindowTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct MinimizedWindowTileView: View {
    let tile: MinimizedWindowTile

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: IconCacheService.shared.icon(forBundleIdentifier: tile.bundleIdentifier))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)

            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(3)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .offset(x: 1, y: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
