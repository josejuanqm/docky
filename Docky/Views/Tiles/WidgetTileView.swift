//
//  WidgetTileView.swift
//  Docky
//

import SwiftUI

struct WidgetTileView: View {
    let tile: WidgetTile
    @ObservedObject private var mediaPlayback = MediaPlaybackService.shared

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(0.08))
            .overlay {
                Group {
                    switch tile.span {
                    case .one:
                        compactBody
                    case .two, .three:
                        expandedBody
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
    }

    @ViewBuilder
    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            artworkView(size: 34)

            Spacer(minLength: 0)

            Text(playbackTitle)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)

            if let playbackState, playbackState.isPlaying {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            } else {
                Text(ownerDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var expandedBody: some View {
        HStack(spacing: 10) {
            artworkView(size: 48)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(playbackTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let playbackState, playbackState.supportsFavorite, playbackState.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.yellow)
                    }
                }

                Text(playbackSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(tile.span == .three ? 2 : 1)

                if let playbackState, playbackState.duration > 0 {
                    ProgressView(value: playbackState.estimatedCurrentTime, total: playbackState.duration)
                        .tint(.primary.opacity(0.8))
                        .controlSize(.mini)
                }

                if tile.span == .three {
                    HStack(spacing: 10) {
                        controlSymbol("backward.fill")
                        controlSymbol(playbackState?.isPlaying == true ? "pause.fill" : "play.fill")
                        controlSymbol("forward.fill")
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func artworkView(size: CGFloat) -> some View {
        if let artworkData = playbackState?.artworkData,
           let artworkImage = NSImage(data: artworkData) {
            Image(nsImage: artworkImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(nsImage: IconCacheService.shared.icon(forBundleIdentifier: tile.ownerBundleIdentifier))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
    }

    private func controlSymbol(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .semibold))
    }

    private var playbackState: MediaPlaybackState? {
        mediaPlayback.state(for: tile.ownerBundleIdentifier)
    }

    private var ownerDisplayName: String {
        playbackState?.displayName
            ?? (NSWorkspace.shared.urlForApplication(withBundleIdentifier: tile.ownerBundleIdentifier).map {
                FileManager.default.displayName(atPath: $0.path)
            } ?? tile.title)
    }

    private var playbackTitle: String {
        guard let playbackState, playbackState.isAvailable else {
            return tile.title
        }

        return playbackState.title.isEmpty ? ownerDisplayName : playbackState.title
    }

    private var playbackSubtitle: String {
        guard let playbackState, playbackState.isAvailable else {
            return subtitle
        }

        let components = [playbackState.artist, playbackState.album].filter { !$0.isEmpty }
        return components.isEmpty ? ownerDisplayName : components.joined(separator: " • ")
    }

    private var subtitle: String {
        switch tile.kind {
        case .nowPlaying:
            "Playback controls for \(ownerDisplayName)."
        }
    }
}
