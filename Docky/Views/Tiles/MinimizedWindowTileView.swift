//
//  MinimizedWindowTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct MinimizedWindowTileView: View {
    let tile: AppWindow
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var workspace = WorkspaceService.shared

    var body: some View {
        GeometryReader { geo in
            ZStack {
                previewCard(in: geo.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width * 0.32, height: geo.size.width * 0.32)
                    .padding(overrideIconPadding(side: geo.size.width * 0.32))
                    .padding(5)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 2, y: 2)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func previewCard(in size: CGSize) -> some View {
        let cardSize = CGSize(width: size.width, height: size.height * 0.8)
        let cornerRadius = min(cardSize.width, cardSize.height) * 0.06

        ZStack {
            if let preview = workspace.minimizedWindowPreview(for: tile) {
                Image(nsImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
                    .frame(width: cardSize.width - 4, height: cardSize.height - 4)
            } else {
                Image(systemName: "rectangle.inset.filled")
                    .font(.system(size: cardSize.height * 0.42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
    }

    private var icon: NSImage {
        if let overrideURL = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: tile.bundleIdentifier),
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return IconCacheService.shared.icon(forBundleIdentifier: tile.bundleIdentifier)
    }

    private func overrideIconPadding(side: CGFloat) -> CGFloat {
        guard preferences.effectiveAppIconOverrideURL(forBundleIdentifier: tile.bundleIdentifier) != nil else {
            return 0
        }
        return preferences.appIconOverridePadding(forBundleIdentifier: tile.bundleIdentifier) * side
    }
}
