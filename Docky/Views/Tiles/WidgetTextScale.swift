//
//  WidgetTextScale.swift
//  Docky
//

import SwiftUI

extension EnvironmentValues {
    /// Multiplier applied to text inside built-in widgets. 1 keeps each
    /// widget's tuned sizes. `WidgetTileView` sets it from
    /// `DockyPreferences.widgetTextScale`; widgets multiply their computed
    /// font sizes by it (icons, spacing and padding stay as they are).
    @Entry var widgetTextScale: CGFloat = 1
}
