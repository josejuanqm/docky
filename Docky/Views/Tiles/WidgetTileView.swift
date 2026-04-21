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
                switch tile.kind {
                case .nowPlaying:
                    nowPlayingWidget
                }
            }
    }

    @ViewBuilder
    private var nowPlayingWidget: some View {
        switch tile.span {
        case .one:
            nowPlayingOneUp
        case .two:
            nowPlayingTwoUp
        case .three:
            nowPlayingThreeUp
        }
    }

    private var nowPlayingOneUp: some View {
        artworkView(size: 52)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(10)
    }

    private var nowPlayingTwoUp: some View {
        HStack(spacing: 12) {
            artworkView(size: 52)
            controlButton(
                playbackState?.isPlaying == true ? "pause.fill" : "play.fill",
                action: togglePlayPause
            )
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var nowPlayingThreeUp: some View {
        HStack(spacing: 12) {
            artworkView(size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(playbackTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(playbackArtist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                controlButton(
                    playbackState?.isPlaying == true ? "pause.fill" : "play.fill",
                    action: togglePlayPause
                )
                controlButton("forward.fill", action: skipToNext)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

    private func controlButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        guard let playbackState, playbackState.hasContent else {
            return tile.title
        }

        return playbackState.title.isEmpty ? ownerDisplayName : playbackState.title
    }

    private var playbackArtist: String {
        guard let playbackState, playbackState.hasContent else {
            return ownerDisplayName
        }

        if !playbackState.artist.isEmpty {
            return playbackState.artist
        }

        return ownerDisplayName
    }

    private func togglePlayPause() {
        Task {
            await mediaPlayback.togglePlayPause(for: tile.ownerBundleIdentifier)
        }
    }

    private func skipToNext() {
        Task {
            await mediaPlayback.skipToNext(for: tile.ownerBundleIdentifier)
        }
    }

}
