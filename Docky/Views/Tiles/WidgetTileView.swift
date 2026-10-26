//
//  WidgetTileView.swift
//  Docky
//

import SwiftUI

struct WidgetTileView: View {
    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool
    var isExpanded: Bool = false
    var isExpandedPreviewOpen: Bool = false

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        Group {
            kindView
        }
        .environment(\.widgetTextScale, DockyPreferences.shared.widgetTextScale)
    }

    @ViewBuilder
    private var kindView: some View {
        switch tile.kind {
        case .calendar, .calendarDate:
            CalendarWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack,
                isExpanded: isExpanded,
                isExpandedPreviewOpen: isExpandedPreviewOpen
            )
        case .reminders:
            RemindersWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack,
                isExpanded: isExpanded,
                isExpandedPreviewOpen: isExpandedPreviewOpen
            )
        case .batteries:
            BatteriesWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack,
                isExpanded: isExpanded,
                isExpandedPreviewOpen: isExpandedPreviewOpen
            )
        case .systemStatus:
            SystemStatusWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack,
                isExpanded: isExpanded,
                isExpandedPreviewOpen: isExpandedPreviewOpen
            )
        case .nowPlaying:
            NowPlayingWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack,
                isExpanded: isExpanded,
                isExpandedPreviewOpen: isExpandedPreviewOpen
            )
        case .weather:
            WeatherWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack,
                isExpanded: isExpanded,
                isExpandedPreviewOpen: isExpandedPreviewOpen
            )
        case .search:
            SearchWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack,
                isExpanded: isExpanded,
                isExpandedPreviewOpen: isExpandedPreviewOpen
            )
        case .photoFrame:
            PhotoFrameWidgetTileView(
                tile: tile,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack,
                isExpanded: isExpanded,
                isExpandedPreviewOpen: isExpandedPreviewOpen
            )
        case .external(let identifier):
            ExternalWidgetTileView(
                identifier: identifier,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: isWithinStack,
                isExpanded: isExpanded,
                isExpandedPreviewOpen: isExpandedPreviewOpen,
                settings: tile.settings
            )
            .dockyGlass(.regular, in: .rect(cornerRadius: cornerRadius))
            .dockyGlassBorder(in: .rect(cornerRadius: cornerRadius))
        }
    }
}

/// Bridges an external plugin's NSView output into the SwiftUI tile
/// stack. Plugins typically wrap a SwiftUI view in NSHostingView; this
/// representable wraps their view in a flexible container that fills
/// the surrounding tile rather than collapsing to the SwiftUI ideal
/// (intrinsic) size, which would otherwise ignore the plugin's
/// .frame(maxWidth:.infinity) and padding.
private struct ExternalWidgetTileView: NSViewRepresentable {
    let identifier: String
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool
    let isExpanded: Bool
    let isExpandedPreviewOpen: Bool
    let settings: WidgetSettings

    func makeCoordinator() -> Coordinator {
        Coordinator(settings: settings)
    }

    func makeNSView(context: Context) -> NSView {
        let host = ExternalWidgetHostView()
        host.setChild(makePluginView())
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let host = nsView as? ExternalWidgetHostView else { return }
        guard context.coordinator.settings != settings else { return }
        context.coordinator.settings = settings
        host.setChild(makePluginView())
    }

    private func makePluginView() -> NSView {
        guard let registration = ExternalWidgetRegistry.shared.registration(for: identifier) else {
            return MissingExternalWidgetPlaceholderView(identifier: identifier)
        }
        return registration.view(
            cornerRadius: cornerRadius,
            renderedSpan: renderedSpan,
            isWithinStack: isWithinStack,
            isExpanded: isExpanded,
            isExpandedPreviewOpen: isExpandedPreviewOpen,
            settings: settings
        )
    }

    final class Coordinator {
        var settings: WidgetSettings
        init(settings: WidgetSettings) {
            self.settings = settings
        }
    }
}

/// Hosts a single external-widget child pinned to its edges; swappable so a settings change can rebuild it.
private final class ExternalWidgetHostView: NSView {
    func setChild(_ child: NSView) {
        subviews.forEach { $0.removeFromSuperview() }
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.trailingAnchor.constraint(equalTo: trailingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
            child.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

/// Hosts a plugin-provided NSView and pins it to the container's edges so
/// the plugin's SwiftUI .frame(maxWidth:.infinity) actually fills the tile.
/// Reports `noIntrinsicMetric` so SwiftUI lays the container out from the
/// available space, not from a measured ideal size.
private final class FlexibleSizingContainerView: NSView {
    init(child: NSView) {
        super.init(frame: .zero)
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.trailingAnchor.constraint(equalTo: trailingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
            child.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

/// Rendered when persisted dock contents reference an external widget
/// whose bundle is no longer installed. Visible but inert so the user
/// can see something is missing and remove it.
private final class MissingExternalWidgetPlaceholderView: NSView {
    init(identifier: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.secondarySystemFill.cgColor

        let label = NSTextField(labelWithString: "Missing widget: \(identifier)")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
