//
//  NowPlayingWidgetTileView.swift
//  Docky
//

import AppKit
import CoreImage
import SwiftUI

struct NowPlayingWidgetTileView: View {
    @Environment(\.widgetTextScale) private var textScale

    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool
    var isExpanded: Bool = false
    var isExpandedPreviewOpen: Bool = false
    @ObservedObject private var mediaPlayback = MediaPlaybackService.shared
    @State private var isHovering = false
    @State private var isLyricsOverlayPresented = false

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        GeometryReader { proxy in
            let layout = layout(in: proxy.size)
            let expandedLayout = expandedLayout(in: proxy.size)

            ZStack {
                Color(nsColor: prominentTintColor)
                    .dockyGlassBorder(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                if !isWithinStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }

                content(layout: layout)
                    .opacity(isExpandedPreviewOpen && isExpanded ? 0 : 1)

                if isExpanded {
                    expandedContent(layout: expandedLayout)
                        .frame(height: proxy.size.height)
                        .transition(
                            .opacity.animation(
                                .easeInOut(duration: 0.22).delay(0.22)
                            ).combined(with: .scale).combined(with: .slide)
                        )
                }

                if isExpanded && isLyricsOverlayPresented {
                    lyricsOverlay(layout: expandedLayout)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isLyricsOverlayPresented)
            .animation(.easeInOut(duration: 0.22), value: isExpanded)
            .animation(.easeOut(duration: 0.12), value: isExpandedPreviewOpen)
        }
        .opacity(isExpandedPreviewOpen && !isExpanded ? 0.5 : 1)
        .animation(.easeOut(duration: 0.12), value: isExpandedPreviewOpen)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func content(layout: LayoutMetrics) -> some View {
        switch renderedSpan {
        case .one:
            nowPlayingOneUp(layout: layout)
        case .two:
            nowPlayingTwoUp(layout: layout)
        case .three, .four:
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

    private func expandedContent(layout: ExpandedLayoutMetrics) -> some View {
        HStack(spacing: layout.contentGap) {
            artworkView(size: layout.artworkSize, artworkCornerRadius: layout.artworkCornerRadius)
                .frame(width: layout.artworkSize, height: layout.artworkSize)
                .shadow(color: .black.opacity(0.18), radius: layout.artworkSize * 0.05, x: 0, y: layout.artworkSize * 0.03)

            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                VStack(alignment: .leading, spacing: layout.titleStackSpacing) {
                    Text(playbackTitle)
                        .font(.system(size: layout.titleFontSize, weight: .semibold))
                        .foregroundStyle(primaryForegroundColor)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(secondaryDescription)
                        .font(.system(size: layout.subtitleFontSize, weight: .medium))
                        .foregroundStyle(secondaryForegroundColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                controlRow(layout: layout)

                progressSection(layout: layout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func progressSection(layout: ExpandedLayoutMetrics) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let elapsed = playbackState?.estimatedCurrentTime ?? 0
            let total = max(playbackState?.duration ?? 0, 0)
            let progress: Double = total > 0 ? min(max(elapsed / total, 0), 1) : 0
            let remaining = max(total - elapsed, 0)

            VStack(spacing: layout.progressLabelSpacing) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(secondaryForegroundColor.opacity(0.28))

                        Capsule(style: .continuous)
                            .fill(primaryForegroundColor)
                            .frame(width: max(0, proxy.size.width * progress))
                    }
                }
                .frame(height: layout.progressBarHeight)

                HStack {
                    Text(formatPlaybackTime(elapsed))
                        .foregroundStyle(secondaryForegroundColor)
                    Spacer(minLength: 0)
                    Text(total > 0 ? "-\(formatPlaybackTime(remaining))" : formatPlaybackTime(elapsed))
                        .foregroundStyle(secondaryForegroundColor)
                }
                .font(.system(size: layout.timestampFontSize, weight: .medium, design: .rounded))
                .monospacedDigit()
            }
        }
    }

    private func controlRow(layout: ExpandedLayoutMetrics) -> some View {
        HStack(spacing: layout.controlClusterSpacing) {
            expandedControlButton(
                "backward.fill",
                size: layout.controlButtonSize,
                iconSize: layout.controlIconSize,
                action: skipToPrevious
            )

            expandedControlButton(
                playbackState?.isPlaying == true ? "pause.fill" : "play.fill",
                size: layout.primaryControlButtonSize,
                iconSize: layout.primaryControlIconSize,
                action: togglePlayPause
            )

            expandedControlButton(
                "forward.fill",
                size: layout.controlButtonSize,
                iconSize: layout.controlIconSize,
                action: skipToNext
            )

            if playbackState?.supportsFavorite == true {
                expandedControlButton(
                    playbackState?.isFavorite == true ? "heart.fill" : "heart",
                    size: layout.controlButtonSize,
                    iconSize: layout.controlIconSize,
                    action: toggleFavorite
                )
            }

            if mediaPlayback.supportsLyrics(for: effectiveBundleIdentifier) {
                expandedControlButton(
                    "quote.bubble.fill",
                    size: layout.controlButtonSize,
                    iconSize: layout.controlIconSize,
                    action: toggleLyricsOverlay
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleLyricsOverlay() {
        if !isLyricsOverlayPresented {
            mediaPlayback.requestLyrics(for: effectiveBundleIdentifier)
        }
        isLyricsOverlayPresented.toggle()
    }

    @ViewBuilder
    private func lyricsOverlay(layout: ExpandedLayoutMetrics) -> some View {
        let state = mediaPlayback.lyricsState(for: effectiveBundleIdentifier)

        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            ZStack(alignment: .leading) {
                VStack {
                    HStack {
                        
                        Spacer()

                        Button {
                            isLyricsOverlayPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: layout.controlIconSize, weight: .semibold))
                                .foregroundStyle(primaryForegroundColor)
                                .frame(width: layout.controlButtonSize, height: layout.controlButtonSize)
                                .background(
                                    Circle()
                                        .fill(secondaryForegroundColor.opacity(0.18))
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                }

                lyricsBody(state: state, layout: layout)
            }
            .padding(layout.contentPadding)
        }
        .onChange(of: trackChangeKey) { _ in
            mediaPlayback.requestLyrics(for: effectiveBundleIdentifier)
        }
    }

    @ViewBuilder
    private func lyricsBody(state: LyricsLoadState?, layout: ExpandedLayoutMetrics) -> some View {
        switch state {
        case .loaded(let content):
            if content.hasSyncedLines {
                KaraokeLyricsView(
                    lines: content.lines,
                    layout: layout,
                    primaryColor: primaryForegroundColor,
                    secondaryColor: secondaryForegroundColor,
                    bundleIdentifier: effectiveBundleIdentifier,
                    mediaPlayback: mediaPlayback
                )
            } else {
                ScrollView {
                    Text(content.plain)
                        .font(.system(size: layout.subtitleFontSize))
                        .foregroundStyle(primaryForegroundColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        case .unavailable:
            VStack {
                Spacer()
                Text("No lyrics available")
                    .font(.system(size: layout.subtitleFontSize))
                    .foregroundStyle(secondaryForegroundColor)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        case .loading, .none:
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var trackChangeKey: String {
        "\(effectiveBundleIdentifier)|\(playbackState?.title ?? "")|\(playbackState?.artist ?? "")|\(playbackState?.album ?? "")"
    }

    private func expandedControlButton(_ systemName: String, size: CGFloat, iconSize: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(primaryForegroundColor)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(secondaryForegroundColor.opacity(0.18))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var secondaryDescription: String {
        let artist = playbackArtist
        let album = playbackState?.album ?? ""
        let parts = [artist, album].filter { !$0.isEmpty }
        return parts.isEmpty ? ownerDisplayName : parts.joined(separator: " • ")
    }

    private func formatPlaybackTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        let hours = minutes / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes % 60, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }

    private func toggleFavorite() {
        let next = !(playbackState?.isFavorite ?? false)
        Task {
            await mediaPlayback.setFavorite(next, for: effectiveBundleIdentifier)
        }
    }

    @ViewBuilder
    private func artworkView(size: CGFloat?, artworkCornerRadius: CGFloat) -> some View {
        if let artworkImage = playbackState?.artwork?.image,
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

    private func expandedLayout(in size: CGSize) -> ExpandedLayoutMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let minSide = min(width, height)
        let contentPadding = min(max(minSide * 0.07, 12), 22)
        let contentGap = min(max(minSide * 0.05, 12), 22)
        let sectionSpacing = min(max(minSide * 0.04, 8), 16)
        let titleStackSpacing = min(max(minSide * 0.012, 2), 6)
        let progressBarHeight = min(max(minSide * 0.018, 4), 7)
        let progressLabelSpacing = min(max(minSide * 0.012, 3), 6)

        let availableHeight = max(0, height - contentPadding * 2)
        let artworkSize = availableHeight

        let primaryControlButtonSize = min(max(minSide * 0.16, 36), 60)
        let controlButtonSize = min(max(minSide * 0.12, 28), 46)

        return ExpandedLayoutMetrics(
            contentPadding: contentPadding,
            contentGap: contentGap,
            sectionSpacing: sectionSpacing,
            titleStackSpacing: titleStackSpacing,
            artworkSize: artworkSize,
            artworkCornerRadius: min(max(artworkSize * 0.08, 8), 18),
            titleFontSize: min(max(minSide * 0.07, 14), 22) * textScale,
            subtitleFontSize: min(max(minSide * 0.05, 11), 16) * textScale,
            progressBarHeight: progressBarHeight,
            progressLabelSpacing: progressLabelSpacing,
            timestampFontSize: min(max(minSide * 0.04, 10), 13) * textScale,
            controlClusterSpacing: min(max(minSide * 0.04, 10), 18),
            primaryControlButtonSize: primaryControlButtonSize,
            primaryControlIconSize: primaryControlButtonSize * 0.5,
            controlButtonSize: controlButtonSize,
            controlIconSize: controlButtonSize * 0.5
        )
    }

    private func layout(in size: CGSize) -> LayoutMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let minSide = min(width, height)
        let contentPadding = min(minSide * 0.12, minSide * 0.18)
        let availableHeight = max(0, height - contentPadding * 2)
        let contentGap = min(minSide * 0.1, minSide * 0.2)
        let stackSpacing = min(minSide * 0.05, minSide * 0.1)
        let controlClusterSpacing = min(minSide * 0.08, minSide * 0.14)
        let controlButtonSize = min(minSide * 0.24, availableHeight)
        let artworkWidthFraction: CGFloat = renderedSpan == .two ? 0.34 : 0.24
        let artworkSize = min(availableHeight, width * artworkWidthFraction)
        let artworkCornerRadius = min(artworkSize / 2, max(0, cornerRadius - contentPadding))
        let titleFontSize = min(minSide * 0.18, 16) * textScale
        let subtitleFontSize = min(minSide * 0.14, 13) * textScale
        let controlIconSize = min(controlButtonSize * 0.72, controlButtonSize)
        let largeGlyphSize = min(minSide * 0.42, minSide * 0.56)

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

    /// Media app to track: the per-instance setting pins one, else fall back to the owner bundle id (existing generic now-playing behavior).
    private var effectiveBundleIdentifier: String {
        if let configured = tile.settings.string(NowPlayingWidgetSettings.appBundleIdentifierKey),
           !configured.isEmpty {
            return configured
        }
        return tile.ownerBundleIdentifier
    }

    private var playbackState: MediaPlaybackState? {
        mediaPlayback.state(for: effectiveBundleIdentifier)
    }

    private var prominentTintColor: NSColor {
        guard playbackState?.isPresentable == true else {
            return (NSColor.windowBackgroundColor.blended(withFraction: 0.18, of: .black) ?? .windowBackgroundColor)
        }
        
        if let averageColor = playbackState?.artwork?.averageColor {
            let extractedColor = averageColor.withSystemEffect(.pressed)
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
            ?? (NSWorkspace.shared.urlForApplication(withBundleIdentifier: effectiveBundleIdentifier).map {
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
            await mediaPlayback.pressPlayPauseButton(for: effectiveBundleIdentifier)
        }
    }

    private func skipToNext() {
        Task {
            await mediaPlayback.skipToNext(for: effectiveBundleIdentifier)
        }
    }

    private func skipToPrevious() {
        Task {
            await mediaPlayback.skipToPrevious(for: effectiveBundleIdentifier)
        }
    }
}

private struct KaraokeLyricsView: View {
    let lines: [SyncedLyricsLine]
    let layout: ExpandedLayoutMetrics
    let primaryColor: Color
    let secondaryColor: Color
    let bundleIdentifier: String
    @ObservedObject var mediaPlayback: MediaPlaybackService
    @State private var activeIndex = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: layout.titleStackSpacing * 4) {
                    Color.clear.frame(height: layout.controlButtonSize)

                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(
                                size: layout.titleFontSize * 1.2,
                                weight: .semibold,
                                design: .rounded
                            ))
                            .foregroundStyle(index == activeIndex ? primaryColor : secondaryColor)
                            .opacity(opacity(for: index))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                            .animation(.easeInOut(duration: 0.22), value: activeIndex)
                    }

                    Color.clear.frame(height: layout.controlButtonSize)
                }
            }
            .onChange(of: activeIndex) { newIndex in
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(activeIndex, anchor: .center)
            }
        }
        .task {
            await trackPlayback()
        }
    }

    private func opacity(for index: Int) -> Double {
        let distance = abs(index - activeIndex)
        switch distance {
        case 0: return 1.0
        case 1: return 0.7
        case 2: return 0.5
        case 3: return 0.35
        default: return 0.22
        }
    }

    private func trackPlayback() async {
        activeIndex = currentIndex(at: estimatedTime())
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
            let newIndex = currentIndex(at: estimatedTime())
            if newIndex != activeIndex {
                activeIndex = newIndex
            }
        }
    }

    private func estimatedTime() -> TimeInterval {
        mediaPlayback.state(for: bundleIdentifier)?.estimatedCurrentTime ?? 0
    }

    private func currentIndex(at time: TimeInterval) -> Int {
        guard !lines.isEmpty else { return 0 }
        var index = 0
        for (i, line) in lines.enumerated() {
            if line.time <= time + 0.05 {
                index = i
            } else {
                break
            }
        }
        return index
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

private struct ExpandedLayoutMetrics {
    let contentPadding: CGFloat
    let contentGap: CGFloat
    let sectionSpacing: CGFloat
    let titleStackSpacing: CGFloat
    let artworkSize: CGFloat
    let artworkCornerRadius: CGFloat
    let titleFontSize: CGFloat
    let subtitleFontSize: CGFloat
    let progressBarHeight: CGFloat
    let progressLabelSpacing: CGFloat
    let timestampFontSize: CGFloat
    let controlClusterSpacing: CGFloat
    let primaryControlButtonSize: CGFloat
    let primaryControlIconSize: CGFloat
    let controlButtonSize: CGFloat
    let controlIconSize: CGFloat
}

private extension NSColor {
    var perceivedLuminance: CGFloat {
        guard let rgbColor = usingColorSpace(.deviceRGB) else {
            return 0
        }

        return (0.2126 * rgbColor.redComponent) + (0.7152 * rgbColor.greenComponent) + (0.0722 * rgbColor.blueComponent)
    }
}
