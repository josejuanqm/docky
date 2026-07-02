//
//  PhotoFrameWidgetTileView.swift
//  Docky
//
//  Renders the Photo Frame widget: an empty-state "add photos" call to
//  action when nothing is configured, otherwise the user's photos filling
//  the tile and cross-fading between one another as PhotoFrameService
//  advances the slideshow. Picking and clearing photos is driven from the
//  tile's context menu / tap handling in TileView; this view only
//  reflects PhotoFrameService's published state.
//

import AppKit
import SwiftUI

struct PhotoFrameWidgetTileView: View {
    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool
    var isExpanded: Bool = false
    var isExpandedPreviewOpen: Bool = false

    @ObservedObject private var photos = PhotoFrameService.shared

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        GeometryReader { proxy in
            ZStack {
                if let image = photos.currentImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .transition(.opacity)
                        .id(image)
                } else {
                    emptyState(shortSide: min(proxy.size.width, proxy.size.height))
                }

                if !isWithinStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeInOut(duration: 0.6), value: photos.currentImage)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func emptyState(shortSide: CGFloat) -> some View {
        let iconSize = max(14, shortSide * 0.34)
        ZStack {
            Rectangle().fill(.secondary.opacity(0.12))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    Color.secondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
                .padding(4)

            VStack(spacing: max(2, shortSide * 0.06)) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(.secondary)
                // The label doesn't fit a 1x tile; the icon alone reads as
                // "add a photo" there.
                if renderedSpan != .one {
                    Text("Add Photos")
                        .font(.system(size: max(9, shortSide * 0.11), weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 6)
        }
    }
}
