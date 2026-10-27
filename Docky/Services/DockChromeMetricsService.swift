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

    /// How far the chrome's center moves along the axis so it keeps
    /// covering a tile stack that is shifted to pin the icon under the
    /// cursor. Zero for a centered stack, which grows evenly both ways.
    @Published private(set) var alongAxisOffset: CGFloat = 0

    private init() {}

    func setAlongAxis(growth: CGFloat, offset: CGFloat) {
        if abs(alongAxisGrowth - growth) > 0.0001 {
            alongAxisGrowth = growth
        }
        if abs(alongAxisOffset - offset) > 0.0001 {
            alongAxisOffset = offset
        }
    }
}
