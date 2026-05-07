//
//  FolderTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct FolderTileView: View {
    let tile: FolderTile
    let isOpen: Bool
    @ObservedObject private var permissions = PermissionsService.shared
    @ObservedObject private var folderAccess = FolderAccessService.shared
    @ObservedObject private var preferences = DockyPreferences.shared
    @State private var preview: [URL] = []

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: reloadKey) {
                preview = FolderAccessService.shared.recentContents(of: tile.url, sortMode: tile.sortMode, limit: 3)
            }
            .onAppear {
                folderAccess.beginWatching(tile.url, ownerID: watcherOwnerID)
            }
            .onDisappear {
                folderAccess.endWatching(tile.url, ownerID: watcherOwnerID)
            }
    }

    @ViewBuilder
    private var content: some View {
        if isOpen {
            openPlaceholder
        } else if tile.displayMode == .folder {
            folderIcon
        } else {
            GeometryReader { geo in
                contentsStack(in: geo.size)
            }
        }
    }

    private var openPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.primary.opacity(0.16))

            Image(systemName: "chevron.down")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))
        }
        .padding(6)
    }

    private var folderIcon: some View {
        GeometryReader { proxy in
            Image(nsImage: resolvedFolderIconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(overrideIconPadding(in: proxy.size))
        }
    }

    private func overrideIconPadding(in size: CGSize) -> CGFloat {
        guard preferences.effectiveFolderIconOverrideURL(forPath: tile.url.path) != nil else {
            return 0
        }
        return preferences.folderIconOverridePadding(forPath: tile.url.path) * min(size.width, size.height)
    }

    private var resolvedFolderIconImage: NSImage {
        if let overrideURL = preferences.effectiveFolderIconOverrideURL(forPath: tile.url.path),
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }
        return IconCacheService.shared.previewIcon(forFileURL: tile.url)
    }

    @ViewBuilder
    private func contentsStack(in size: CGSize) -> some View {
        if preview.isEmpty {
            fallbackStack(in: size)
        } else {
            stack(in: size)
        }
    }

    private func stack(in size: CGSize) -> some View {
        let side = min(size.width, size.height) * 0.82
        let verticalStep: CGFloat = 4
        let centeredBaseOffset = CGFloat(preview.count - 1) / 2

        return ZStack {
            ForEach(Array(preview.enumerated()).reversed(), id: \.element) { pair in
                let depth = CGFloat(pair.offset)

                Image(nsImage: IconCacheService.shared.previewIcon(forFileURL: pair.element))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
                    .opacity(1.0 - (depth * 0.12))
                    .offset(y: (centeredBaseOffset - CGFloat(pair.offset)) * verticalStep)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .center)
    }

    private func fallbackStack(in size: CGSize) -> some View {
        let side = min(size.width, size.height) * 0.8
        let offsets: [CGFloat] = [-4, 0, 4]

        return ZStack {
            ForEach(Array(offsets.enumerated()), id: \.offset) { index, offset in
                Image(nsImage: IconCacheService.shared.previewIcon(forFileURL: tile.url))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
                    .opacity(index == 1 ? 1 : 0.55)
                    .offset(y: offset)
                    .scaleEffect(index == 1 ? 1 : 0.92)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .center)
    }

    private var reloadKey: String {
        "\(tile.url.path)|\(permissions.userFolders)|\(tile.displayMode.rawValue)|\(tile.sortMode.rawValue)|\(folderAccess.changeToken)"
    }

    private var watcherOwnerID: String {
        "folder-tile:\(tile.url.standardizedFileURL.path)"
    }
}

extension PermissionStatus: Hashable {}
