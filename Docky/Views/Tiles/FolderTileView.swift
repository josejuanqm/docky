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
    @State private var preview: [URL] = []

    var body: some View {
        VStack(spacing: 2) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            indicatorPlaceholder
        }
            .task(id: reloadKey) {
                preview = FolderAccessService.shared.recentContents(of: tile.url, limit: 3)
            }
    }

    @ViewBuilder
    private var content: some View {
        if preview.isEmpty {
            folderIcon
        } else {
            GeometryReader { geo in
                stack(in: geo.size)
            }
        }
    }

    private var folderIcon: some View {
        Image(nsImage: IconCacheService.shared.icon(forFileURL: tile.url))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    private func stack(in size: CGSize) -> some View {
        let side = min(size.width, size.height) * 0.82
        return ZStack {
            ForEach(Array(preview.enumerated().reversed()), id: \.element) { pair in
                Image(nsImage: IconCacheService.shared.icon(forFileURL: pair.element))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(Double(pair.offset) * -6))
                    .offset(
                        x: CGFloat(pair.offset) * -3,
                        y: CGFloat(pair.offset) * 2
                    )
                    .shadow(radius: 1, y: 1)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .center)
    }

    private var indicatorPlaceholder: some View {
        Circle()
            .frame(width: 4, height: 4)
            .foregroundStyle(.clear)
    }

    private var reloadKey: String {
        "\(tile.url.path)|\(permissions.userFolders)"
    }
}

extension PermissionStatus: Hashable {}
