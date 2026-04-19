//
//  AppTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct AppTileView: View {
    let tile: AppTile
    @ObservedObject private var workspace = WorkspaceService.shared

    private var isRunning: Bool {
        workspace.isRunning(bundleIdentifier: tile.bundleIdentifier)
    }

    private var isHidden: Bool {
        workspace.isHidden(bundleIdentifier: tile.bundleIdentifier)
    }

    var body: some View {
        VStack(spacing: 2) {
            iconView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            runningIndicator
        }
    }

    private var iconView: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .opacity(isHidden ? 0.5 : 1)
    }

    @ViewBuilder
    private var runningIndicator: some View {
        if isRunning {
            Circle()
                .frame(width: 4, height: 4)
                .foregroundStyle(.primary.opacity(0.9))
        } else {
            Color.clear.frame(height: 4)
        }
    }

    private var icon: NSImage {
        IconCacheService.shared.icon(forBundleIdentifier: tile.bundleIdentifier)
    }
}
