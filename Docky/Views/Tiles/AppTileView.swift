//
//  AppTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct AppTileView: View {
    let tile: AppTile
    let clipShape: DockClipShape
    let transparencyCompensationInset: CGFloat
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var workspace = WorkspaceService.shared

    private var isRunning: Bool {
        workspace.isRunning(bundleIdentifier: tile.bundleIdentifier)
    }

    private var isHidden: Bool {
        workspace.isHidden(bundleIdentifier: tile.bundleIdentifier)
    }

    var body: some View {
        GeometryReader { proxy in
            iconView(in: proxy.size)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func iconView(in size: CGSize) -> some View {
        if shouldApplyCircleClip {
            ZStack {
                baseIconView(in: size)
                    .clipShape(Circle())
            }
            .glassEffect()
            .padding(transparencyCompensationInset)
        } else {
            baseIconView(in: size)
        }
    }

    private func baseIconView(in size: CGSize) -> some View {
        let inset = shouldApplyCircleClip ? transparencyCompensationInset + 2 : 0
        let edgeInsets: CGFloat = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: tile.bundleIdentifier) != nil ? -transparencyCompensationInset*4 : inset

        return Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: shouldApplyCircleClip ? .fill : .fit)
            .frame(width: size.width + edgeInsets / 2, height: size.height + edgeInsets / 2)
            .frame(width: size.width - edgeInsets * 2, height: size.height - edgeInsets * 2)
            .opacity(isHidden ? 0.5 : 1)
    }

    private var shouldApplyCircleClip: Bool {
        clipShape == .circle
    }

    private var icon: NSImage {
        if let overrideURL = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: tile.bundleIdentifier),
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return IconCacheService.shared.icon(forBundleIdentifier: tile.bundleIdentifier)
    }
}
