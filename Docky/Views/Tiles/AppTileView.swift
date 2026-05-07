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
    var iconOverrideURL: URL? = nil
    /// Optional padding fraction to use when `iconOverrideURL` is set —
    /// callers that supply a non-app override (e.g. the Launchpad tile)
    /// pass their own padding here, since per-bundle override padding
    /// only applies to real app overrides.
    var iconOverridePaddingFraction: CGFloat? = nil
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

    @ViewBuilder
    private func baseIconView(in size: CGSize) -> some View {
        let hasAppOverride = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: tile.bundleIdentifier) != nil
        let hasOverride = iconOverrideURL != nil || hasAppOverride
        // Caller-supplied padding wins (used by the Launchpad tile);
        // otherwise fall back to the per-bundle override padding.
        let overridePaddingFraction: CGFloat = {
            if let explicit = iconOverridePaddingFraction { return explicit }
            return hasAppOverride
                ? preferences.appIconOverridePadding(forBundleIdentifier: tile.bundleIdentifier)
                : 0
        }()

        if overridePaddingFraction > 0 {
            // User-configured padding bypasses the transparent-edge
            // overshoot used for un-padded overrides: the user has
            // explicitly chosen how much breathing room they want, so
            // render the icon to fit `size` minus that inset.
            let pad = overridePaddingFraction * min(size.width, size.height)
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: shouldApplyCircleClip ? .fill : .fit)
                .padding(pad)
                .opacity(isHidden ? 0.5 : 1)
        } else {
            let inset = shouldApplyCircleClip ? transparencyCompensationInset + 2 : 0
            let edgeInsets: CGFloat = hasOverride ? -transparencyCompensationInset * 4 : inset

            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: shouldApplyCircleClip ? .fill : .fit)
                .frame(width: size.width + edgeInsets / 2, height: size.height + edgeInsets / 2)
                .frame(width: size.width - edgeInsets * 2, height: size.height - edgeInsets * 2)
                .opacity(isHidden ? 0.5 : 1)
        }
    }

    private var shouldApplyCircleClip: Bool {
        clipShape == .circle
    }

    private var icon: NSImage {
        if let iconOverrideURL,
           let image = IconCacheService.shared.image(forImageFileURL: iconOverrideURL) {
            return image
        }

        if let overrideURL = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: tile.bundleIdentifier),
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return IconCacheService.shared.icon(forBundleIdentifier: tile.bundleIdentifier)
    }
}
