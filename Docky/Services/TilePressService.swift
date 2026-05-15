//
//  TilePressService.swift
//  Docky
//
//  Tracks which dock tile is currently being pressed (mouse-down before
//  release) using a single NSEvent local monitor instead of a SwiftUI
//  gesture. The previous gesture-based tracker conflicted with the parent
//  reorder gesture and prevented tile drag; observing at the AppKit event
//  layer side-steps SwiftUI's gesture-claim contest entirely — local
//  monitors return the event unchanged so normal dispatch still happens.
//
//  Press identity is resolved via the tile's own `.onHover` state, not
//  by hit-testing stored frames. SwiftUI's hover already accounts for
//  `.scaleEffect` (magnification), so we always agree with the tile the
//  user visually sees under the cursor — manual hit-testing against the
//  unscaled layout frame would otherwise pick the next tile over when
//  the hovered tile's magnified edge spills past its layout bounds.
//

import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class TilePressService: ObservableObject {
    static let shared = TilePressService()
    private static let logger = Logger(subsystem: "gt.quintero.Docky", category: "TilePress")

    @Published private(set) var pressedTileID: String?

    private var monitor: Any?
    private var hoveredTileID: String?

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Called from `TileView.onHover`. The most recently entered tile is
    /// the one that "owns" the cursor for press purposes.
    func registerHover(tileID: String, isHovering: Bool) {
        if isHovering {
            hoveredTileID = tileID
        } else if hoveredTileID == tileID {
            hoveredTileID = nil
        }
    }

    func clearHover(tileID: String) {
        if hoveredTileID == tileID {
            hoveredTileID = nil
        }
        if pressedTileID == tileID {
            pressedTileID = nil
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            Self.logger.info("leftMouseDown hovered=\(self.hoveredTileID ?? "nil", privacy: .public) clickCount=\(event.clickCount, privacy: .public) modifiers=\(event.modifierFlags.rawValue, privacy: .public)")
            pressedTileID = hoveredTileID
        case .leftMouseUp:
            Self.logger.info("leftMouseUp pressedTileID=\(self.pressedTileID ?? "nil", privacy: .public) clickCount=\(event.clickCount, privacy: .public)")
            if pressedTileID != nil {
                pressedTileID = nil
            }
        default:
            break
        }
    }
}
