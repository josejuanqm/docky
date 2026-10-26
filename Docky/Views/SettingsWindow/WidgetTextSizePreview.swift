//
//  WidgetTextSizePreview.swift
//  Docky
//
//  Live preview of the widgets inside the Settings window, so the widget
//  text size can be judged even while the dock is hidden. Renders a real
//  smart stack holding every widget (live data) at a fixed 80 pt base
//  tile, using the same span width, content padding and corner radius
//  math as the dock.
//

import SwiftUI

struct WidgetTextSizePreview: View {
    static let baseTileSize: CGFloat = 80

    private var preferences = DockyPreferences.shared
    @State private var span: TileSpan = .three

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 14) {
                Picker("Widget Size", selection: $span) {
                    Text("1x").tag(TileSpan.one)
                    Text("2x").tag(TileSpan.two)
                    Text("3x").tag(TileSpan.three)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                SmartStackTileView(
                    tile: previewStack,
                    cornerRadius: cornerRadius,
                    renderedSpan: span
                )
                .id(span)
                .frame(
                    width: max(0, tileWidth - contentPadding * 2),
                    height: max(0, Self.baseTileSize - contentPadding * 2)
                )
                .frame(width: tileWidth, height: Self.baseTileSize)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            Text("Scroll over the stack to flip through every widget.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// A smart stack holding every widget that renders at the chosen
    /// span, external ones included. Search is left out: focusing its
    /// field makes the dock window key, which doesn't belong in Settings.
    private var previewStack: SmartStackTile {
        let widgets = WidgetCatalog.staticRegistrations
            .filter { $0.kind != .search && $0.kind.supportedSpans.contains(span) }
            .map { $0.makeTile(span: span) }
        return SmartStackTile(
            identifier: "settings.widgetTextSizePreview",
            title: "Smart Stack",
            widgets: widgets,
            span: span
        )
    }

    // MARK: - Dock tile metrics (mirrors TileView / TileContainerView)

    private var tileWidth: CGFloat {
        let spanCount = CGFloat(span.rawValue)
        return Self.baseTileSize * spanCount + preferences.effectiveTileSpacing * max(0, spanCount - 1)
    }

    private var contentPadding: CGFloat {
        preferences.effectiveWidgetContentPadding(for: span) ?? floor(Self.baseTileSize * 3 / 32)
    }

    private var cornerRadius: CGFloat {
        let maximumCornerRadius = max(0, (Self.baseTileSize - contentPadding * 2) / 2)
        if let override = preferences.effectiveWidgetCornerRadius(for: span) {
            return min(override, maximumCornerRadius)
        }
        return preferences.effectiveTileClipShape.resolvedCornerRadius(
            base: Self.baseTileSize * 0.225,
            maximum: maximumCornerRadius
        )
    }
}
