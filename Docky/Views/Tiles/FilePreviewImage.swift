//
//  FilePreviewImage.swift
//  Docky
//
//  Preview image for a file shown in folder surfaces (tile pile, fan,
//  grid popover). Image files render a downsampled thumbnail decoded off
//  the main thread; everything else renders the system file icon. Until a
//  thumbnail is ready the file icon stands in, so the main thread never
//  blocks on decoding a full-size photo.
//

import AppKit
import SwiftUI

struct FilePreviewImage: View {
    let url: URL
    let maxPixelSize: Int

    @State private var loaded: LoadedThumbnail?

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .task(id: url) {
                let thumbnail = await IconCacheService.shared.loadPreviewThumbnailAsync(
                    forFileURL: url,
                    maxPixelSize: maxPixelSize
                )
                loaded = thumbnail.map { LoadedThumbnail(url: url, image: $0) }
            }
    }

    private var image: NSImage {
        // The loaded thumbnail is tagged with its URL so a view whose
        // identity is positional never shows the previous file's image.
        if let loaded, loaded.url == url {
            return loaded.image
        }

        return IconCacheService.shared.cachedPreviewThumbnail(forFileURL: url, maxPixelSize: maxPixelSize)
            ?? IconCacheService.shared.icon(forFileURL: url)
    }
}

private struct LoadedThumbnail {
    let url: URL
    let image: NSImage
}
