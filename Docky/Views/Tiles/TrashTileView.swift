//
//  TrashTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct TrashTileView: View {
    @ObservedObject private var trash = TrashService.shared
    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        GeometryReader { proxy in
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(overridePadding(in: proxy.size))
        }
    }

    private func overridePadding(in size: CGSize) -> CGFloat {
        let state: TrashIconState = trash.isEmpty ? .empty : .full
        guard preferences.effectiveTrashIconOverrideURL(forState: state) != nil else {
            return 0
        }
        return preferences.trashIconOverridePadding(forState: state) * min(size.width, size.height)
    }

    private var icon: NSImage {
        let state: TrashIconState = trash.isEmpty ? .empty : .full

        if let overrideURL = preferences.effectiveTrashIconOverrideURL(forState: state),
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return NSImage(named: state.systemImageName)
            ?? NSImage(named: TrashIconState.empty.systemImageName)
            ?? NSImage()
    }
}
