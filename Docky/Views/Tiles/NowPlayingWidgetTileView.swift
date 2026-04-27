//
//  NowPlayingWidgetTileView.swift
//  Docky
//

import AppKit
import CoreImage
import SwiftUI

struct NowPlayingWidgetTileView: View {
    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool
    @ObservedObject private var mediaPlayback = MediaPlaybackService.shared
    @State private var isHovering = false

    var body: some View {
        GeometryReader { proxy in
            let layout = layout(in: proxy.size)

            ZStack {
                Color(nsColor: prominentTintColor)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))

                if !isWithinStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }

                content(layout: layout)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func content(layout: LayoutMetrics) -> some View {
        switch renderedSpan {
        case .one:
            nowPlayingOneUp(layout: layout)
        case .two:
            nowPlayingTwoUp(layout: layout)
        case .three:
            nowPlayingThreeUp(layout: layout)
        }
    }

    private func nowPlayingOneUp(layout: LayoutMetrics) -> some View {
        artworkView(size: nil, artworkCornerRadius: layout.artworkCornerRadius)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isHovering {
                    ZStack {
                        Color.black.opacity(0.18)

                        Image(systemName: playbackState?.isPlaying == true ? "pause.fill" : "play.fill")
                            .font(.system(size: layout.largeGlyphSize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .offset(x: playbackState?.isPlaying == true ? 0 : -layout.largeGlyphSize * 0.06)
                    }
                    .transition(.opacity)
                }
            }
            .onHover { isHovering = $0 }
    }

    private func nowPlayingTwoUp(layout: LayoutMetrics) -> some View {
        HStack(spacing: layout.contentGap) {
            artworkView(size: layout.artworkSize, artworkCornerRadius: layout.artworkCornerRadius)

            HStack(spacing: layout.controlClusterSpacing) {
                controlButton("backward.fill", layout: layout, action: skipToPrevious)
                controlButton(
                    playbackState?.isPlaying == true ? "pause.fill" : "play.fill",
                    layout: layout,
                    action: togglePlayPause
                )
                controlButton("forward.fill", layout: layout, action: skipToNext)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func nowPlayingThreeUp(layout: LayoutMetrics) -> some View {
        HStack(spacing: layout.contentGap) {
            artworkView(size: layout.artworkSize, artworkCornerRadius: layout.artworkCornerRadius)

            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                Text(playbackState?.isPresentable == false ? (playbackState?.title ?? "Not Playing") : playbackTitle)
                    .font(.system(size: layout.titleFontSize, weight: .semibold))
                    .foregroundStyle(primaryForegroundColor)
                    .lineLimit(1)

                if playbackArtist.isEmpty == false {
                    Text(playbackArtist)
                        .font(.system(size: layout.subtitleFontSize))
                        .foregroundStyle(secondaryForegroundColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: layout.contentGap) {
                controlButton(
                    playbackState?.isPlaying == true ? "pause.fill" : "play.fill",
                    layout: layout,
                    action: togglePlayPause
                )
                controlButton("forward.fill", layout: layout, action: skipToNext)
            }
            .fixedSize()
            .padding(.trailing, layout.trailingControlPadding)
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func artworkView(size: CGFloat?, artworkCornerRadius: CGFloat) -> some View {
        if let artworkData = playbackState?.artworkData,
           let artworkImage = NSImage(data: artworkData),
           playbackState?.isPresentable == true {
            Image(nsImage: artworkImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
        } else {
            Color.primary
                .opacity(0.06)
                .aspectRatio(contentMode: size == nil ? .fill : .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
        }
    }

    private func controlButton(_ systemName: String, layout: LayoutMetrics, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: layout.controlIconSize, weight: .semibold))
                .foregroundStyle(primaryForegroundColor)
                .frame(width: layout.controlButtonSize, height: layout.controlButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func layout(in size: CGSize) -> LayoutMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let minSide = min(width, height)
        let contentPadding = min(max(minSide * 0.12, 4), minSide * 0.18)
        let availableHeight = max(0, height - contentPadding * 2)
        let contentGap = min(max(minSide * 0.1, 4), minSide * 0.2)
        let stackSpacing = min(max(minSide * 0.05, 2), minSide * 0.1)
        let controlClusterSpacing = min(max(minSide * 0.08, 4), minSide * 0.14)
        let controlButtonSize = min(max(minSide * 0.24, 16), availableHeight)
        let artworkWidthFraction: CGFloat = renderedSpan == .two ? 0.34 : 0.24
        let artworkSize = min(availableHeight, width * artworkWidthFraction)
        let artworkCornerRadius = min(artworkSize / 2, max(0, cornerRadius - contentPadding))
        let titleFontSize = min(max(minSide * 0.18, 11), 16)
        let subtitleFontSize = min(max(minSide * 0.14, 9), 13)
        let controlIconSize = min(max(controlButtonSize * 0.72, 11), controlButtonSize)
        let largeGlyphSize = min(max(minSide * 0.42, 18), minSide * 0.56)

        return LayoutMetrics(
            contentPadding: contentPadding,
            contentGap: contentGap,
            controlClusterSpacing: controlClusterSpacing,
            stackSpacing: stackSpacing,
            trailingControlPadding: stackSpacing,
            artworkSize: artworkSize,
            artworkCornerRadius: artworkCornerRadius,
            titleFontSize: titleFontSize,
            subtitleFontSize: subtitleFontSize,
            controlIconSize: controlIconSize,
            controlButtonSize: controlButtonSize,
            largeGlyphSize: largeGlyphSize
        )
    }

    private var playbackState: MediaPlaybackState? {
        mediaPlayback.state(for: tile.ownerBundleIdentifier)
    }

    private var prominentTintColor: NSColor {
        guard playbackState?.isPresentable == true else {
            return (NSColor.windowBackgroundColor.blended(withFraction: 0.18, of: .black) ?? .windowBackgroundColor)
        }
        
        if let artworkData = playbackState?.artworkData,
           let artworkImage = NSImage(data: artworkData),
           let extractedColor = Self.prominentColor(from: artworkImage) {
            return extractedColor.usingColorSpace(.deviceRGB) ?? extractedColor
        }

        return (NSColor.windowBackgroundColor.blended(withFraction: 0.18, of: .black) ?? .windowBackgroundColor)
    }

    private var usesDarkForeground: Bool {
        prominentTintColor.perceivedLuminance > 0.62
    }

    private var primaryForegroundColor: Color {
        Color(nsColor: usesDarkForeground ? .black.withAlphaComponent(0.82) : .white.withAlphaComponent(0.96))
    }

    private var secondaryForegroundColor: Color {
        Color(nsColor: usesDarkForeground ? .black.withAlphaComponent(0.56) : .white.withAlphaComponent(0.72))
    }

    private var ownerDisplayName: String {
        playbackState?.displayName
            ?? (NSWorkspace.shared.urlForApplication(withBundleIdentifier: tile.ownerBundleIdentifier).map {
                FileManager.default.displayName(atPath: $0.path)
            } ?? "")
    }

    private var playbackTitle: String {
        guard let playbackState, playbackState.hasContent else {
            return "Not Playing"
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
            await mediaPlayback.pressPlayPauseButton(for: tile.ownerBundleIdentifier)
        }
    }

    private func skipToNext() {
        Task {
            await mediaPlayback.skipToNext(for: tile.ownerBundleIdentifier)
        }
    }

    private func skipToPrevious() {
        Task {
            await mediaPlayback.skipToPrevious(for: tile.ownerBundleIdentifier)
        }
    }

    private static let ciContext = CIContext(options: nil)

    private static func prominentColor(from image: NSImage) -> NSColor? {
        guard let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return nil
        }

        let extent = ciImage.extent
        guard !extent.isEmpty,
              let filter = CIFilter(name: "CIAreaAverage") else {
            return nil
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)

        guard let outputImage = filter.outputImage else {
            return nil
        }

        var rgba = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &rgba,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let baseColor = NSColor(
            red: CGFloat(rgba[0]) / 255,
            green: CGFloat(rgba[1]) / 255,
            blue: CGFloat(rgba[2]) / 255,
            alpha: 1
        )

        return baseColor.withSystemEffect(.pressed)
    }
}

private struct LayoutMetrics {
    let contentPadding: CGFloat
    let contentGap: CGFloat
    let controlClusterSpacing: CGFloat
    let stackSpacing: CGFloat
    let trailingControlPadding: CGFloat
    let artworkSize: CGFloat
    let artworkCornerRadius: CGFloat
    let titleFontSize: CGFloat
    let subtitleFontSize: CGFloat
    let controlIconSize: CGFloat
    let controlButtonSize: CGFloat
    let largeGlyphSize: CGFloat
}

private extension NSColor {
    var perceivedLuminance: CGFloat {
        guard let rgbColor = usingColorSpace(.deviceRGB) else {
            return 0
        }

        return (0.2126 * rgbColor.redComponent) + (0.7152 * rgbColor.greenComponent) + (0.0722 * rgbColor.blueComponent)
    }
}
