//
//  DockEditModeService.swift
//  Docky
//

import Combine
import Foundation
import CoreGraphics

struct DockEditPaletteDrag: Equatable {
    let kind: PinnedTileItemKind
    let location: CGPoint
}

final class DockEditModeService: ObservableObject {
    static let shared = DockEditModeService()

    @Published private(set) var isActive = false
    @Published private(set) var paletteDrag: DockEditPaletteDrag?
    @Published var paletteDropDestinationIndex: Int?

    private init() {}

    func enter() {
        isActive = true
    }

    func exit() {
        isActive = false
        endPaletteDrag()
    }

    func toggle() {
        isActive ? exit() : enter()
    }

    func updatePaletteDrag(kind: PinnedTileItemKind, location: CGPoint) {
        isActive = true
        paletteDrag = DockEditPaletteDrag(kind: kind, location: location)
    }

    func beginPaletteDrag(kind: PinnedTileItemKind) {
        isActive = true
        paletteDrag = DockEditPaletteDrag(kind: kind, location: .zero)
    }

    func endPaletteDrag() {
        paletteDrag = nil
        paletteDropDestinationIndex = nil
    }
}
