//
//  DockLayoutService.swift
//  Docky
//

import Combine
import CoreGraphics
import Foundation

final class DockLayoutService: ObservableObject {
    static let shared = DockLayoutService()

    @Published private(set) var contentScale: CGFloat = 1
    @Published private(set) var compactsWidgetsForOverflow = false
    @Published private(set) var chromeSize: CGSize = .zero

    private init() {}

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

    func scaled(_ value: CGFloat) -> CGFloat {
        value * contentScale
    }
}
