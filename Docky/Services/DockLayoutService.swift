//
//  DockLayoutService.swift
//  Docky
//

import Combine
import CoreGraphics
import Foundation

enum DockDividerPositionClass {
    case left
    case center
    case right
}

final class DockLayoutService: ObservableObject {
    static let shared = DockLayoutService()

    @Published private(set) var contentScale: CGFloat = 1
    @Published private(set) var compactsWidgetsForOverflow = false
    @Published private(set) var chromeSize: CGSize = .zero
    @Published private(set) var tileCanvasFrame: CGRect = .zero
    /// Extra window room before and after the dock along its axis, so
    /// magnified icons on a dock that fills its edge can spill out to the
    /// screen edge instead of being cut off by the window. The dock view
    /// pads itself by these amounts to stay at its resting position.
    @Published private(set) var alongAxisLeadingInset: CGFloat = 0
    @Published private(set) var alongAxisTrailingInset: CGFloat = 0

    private init() {}

    func setAlongAxisInsets(leading: CGFloat, trailing: CGFloat) {
        if abs(alongAxisLeadingInset - leading) > 0.0001 {
            alongAxisLeadingInset = leading
        }
        if abs(alongAxisTrailingInset - trailing) > 0.0001 {
            alongAxisTrailingInset = trailing
        }
    }

    func setContentScale(_ scale: CGFloat) {
        let clampedScale = min(max(scale, 0), 1)
        guard abs(contentScale - clampedScale) > 0.0001 else { return }
        contentScale = clampedScale
    }

    func setCompactsWidgetsForOverflow(_ compactsWidgetsForOverflow: Bool) {
        guard self.compactsWidgetsForOverflow != compactsWidgetsForOverflow else { return }
        self.compactsWidgetsForOverflow = compactsWidgetsForOverflow
    }

    func setChromeSize(_ size: CGSize) {
        guard abs(chromeSize.width - size.width) > 0.0001 || abs(chromeSize.height - size.height) > 0.0001 else {
            return
        }
        chromeSize = size
    }

    func setTileCanvasFrame(_ frame: CGRect) {
        guard abs(tileCanvasFrame.minX - frame.minX) > 0.0001
            || abs(tileCanvasFrame.minY - frame.minY) > 0.0001
            || abs(tileCanvasFrame.width - frame.width) > 0.0001
            || abs(tileCanvasFrame.height - frame.height) > 0.0001 else {
            return
        }
        tileCanvasFrame = frame
    }

    func scaled(_ value: CGFloat) -> CGFloat {
        value * contentScale
    }
}
