//
//  DockChromeMetricsService.swift
//  Docky
//
//  Live, magnification-aware totals used to size the dock chrome.
//  `TileContainerView` writes these as a byproduct of the walk it already
//  does for the anchor offset; `MainWindowView` reads them. Kept on its
//  own service so the writer (tile view) is NOT an observer — otherwise
//  every write would re-render the tile view it just measured.
//

import Combine
import CoreGraphics
import Foundation

final class DockChromeMetricsService: ObservableObject {
    static let shared = DockChromeMetricsService()

    /// Total along-axis growth from magnification, summed across every
    /// tile. Already incorporates ramp strength via the per-tile sizes.
    /// Zero when magnification is inactive.
    @Published private(set) var alongAxisGrowth: CGFloat = 0

    private init() {}

    func setAlongAxisGrowth(_ value: CGFloat) {
        guard abs(alongAxisGrowth - value) > 0.0001 else { return }
        alongAxisGrowth = value
    }
}
