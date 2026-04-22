//
//  TrashTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct TrashTileView: View {
    @ObservedObject private var trash = TrashService.shared

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    private var icon: NSImage {
        let imageName = trash.isEmpty ? "NSTrashEmpty" : "NSTrashFull"
        return NSImage(named: imageName) ?? NSImage(named: "NSTrashEmpty") ?? NSImage()
    }
}
