//
//  FolderPopoverView.swift
//  Docky
//

import AppKit
import SwiftUI

struct FolderPopoverView: View {
    let tile: FolderTile
    let initialSnapshot: FolderContentsSnapshot
    @Binding var isPresented: Bool

    @ObservedObject private var permissions = PermissionsService.shared
    @State private var snapshot: FolderContentsSnapshot

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 132, maximum: 160), spacing: 8),
        count: 6
    )

    init(tile: FolderTile, initialSnapshot: FolderContentsSnapshot, isPresented: Binding<Bool>) {
        self.tile = tile
        self.initialSnapshot = initialSnapshot
        _isPresented = isPresented
        _snapshot = State(initialValue: initialSnapshot)
    }

    var body: some View {
        Group {
            if case .unreadable = snapshot {
                unreadableState
            } else if items.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(items, id: \.self) { itemURL in
                            Button {
                                open(itemURL)
                            } label: {
                                FolderPopoverItemView(url: itemURL)
                            }
                            .buttonStyle(.plain)
                            .background {
                                ContextActionMenuPresenter(actions: [
                                    .action("Reveal in Finder") {
                                        revealInFinder(itemURL)
                                    },
                                    .action("Open in Finder") {
                                        openInFinder(itemURL)
                                    }
                                ])
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(width: 920, height: min(max(popoverHeight, 400), 840))
            }
        }
        .task(id: reloadKey) {
            snapshot = FolderAccessService.shared.snapshot(of: tile.url)
        }
        .background(.ultraThinMaterial)
    }

    private var items: [URL] {
        if case .loaded(let items) = snapshot {
            return items
        }
        return []
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(nsImage: IconCacheService.shared.icon(forFileURL: tile.url))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 112, height: 112)

            Text("No visible items")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(tile.displayName)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: 320, height: 180)
        .padding(20)
    }

    private var unreadableState: some View {
        VStack(spacing: 12) {
            Image(nsImage: IconCacheService.shared.icon(forFileURL: tile.url))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 112, height: 112)

            Text("Can't read folder contents")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(tile.displayName)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: 360, height: 220)
        .padding(20)
    }

    private var popoverHeight: CGFloat {
        let rows = ceil(Double(items.count) / Double(columns.count))
        return CGFloat(rows) * 170 + 40
    }

    private var reloadKey: String {
        "\(tile.url.path)|\(permissions.userFolders)|\(permissions.userFoldersURL?.path ?? "")|\(isPresented)"
    }

    private func open(_ itemURL: URL) {
        let opened = permissions.withUserFoldersAccess {
            NSWorkspace.shared.open(itemURL)
        }

        if opened {
            isPresented = false
        }
    }

    private func revealInFinder(_ itemURL: URL) {
        Task {
            if await AppleScriptService.shared.revealInFinder(itemURL) {
                isPresented = false
            }
        }
    }

    private func openInFinder(_ itemURL: URL) {
        Task {
            if await AppleScriptService.shared.openFinderWindow(for: itemURL) {
                isPresented = false
            }
        }
    }
}

private struct FolderPopoverItemView: View {
    let url: URL

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: IconCacheService.shared.icon(forFileURL: url))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 112, height: 112)

            Text(displayName)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.001))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var displayName: String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
    }
}
