//
//  SystemStatusWidgetTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct SystemStatusWidgetTileView: View {
    @Environment(\.widgetTextScale) private var textScale

    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool
    var isExpanded: Bool = false
    var isExpandedPreviewOpen: Bool = false

    @ObservedObject private var systemStatus = SystemStatusService.shared

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        GeometryReader { proxy in
            let metrics = visibleMetrics
            let layout = layout(in: proxy.size, visibleMetricCount: max(1, metrics.count))

            ZStack {
                Color(nsColor: backgroundTintColor)
                    .dockyGlassBorder(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                if !isWithinStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }

                content(metrics: metrics, layout: layout)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task {
            systemStatus.ensureFreshStatus()
        }
    }

    @ViewBuilder
    private func content(metrics: [SystemStatusMetricSnapshot], layout: LayoutMetrics) -> some View {
        if !metrics.isEmpty {
            indicatorStrip(metrics: metrics, layout: layout)
        } else {
            emptyState(layout: layout)
        }
    }

    /// Rings with their labels when there's room; when larger widget text
    /// no longer fits, the labels go and the rings alone show the levels.
    private func indicatorStrip(metrics: [SystemStatusMetricSnapshot], layout: LayoutMetrics) -> some View {
        ViewThatFits(in: .vertical) {
            indicatorRow(metrics: metrics, layout: layout, showsLabels: true)
            indicatorRow(metrics: metrics, layout: layout, showsLabels: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func indicatorRow(metrics: [SystemStatusMetricSnapshot], layout: LayoutMetrics, showsLabels: Bool) -> some View {
        HStack(alignment: .center, spacing: layout.contentGap) {
            ForEach(metrics) { metric in
                metricIndicator(metric: metric, layout: layout, showsLabel: showsLabels)
            }
        }
        .padding(layout.contentPadding)
    }

    private func metricIndicator(metric: SystemStatusMetricSnapshot, layout: LayoutMetrics, showsLabel: Bool) -> some View {
        VStack(spacing: layout.stackSpacing) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.14), lineWidth: layout.ringWidth)

                Circle()
                    .trim(from: 0, to: metric.progress)
                    .stroke(
                        Color(nsColor: accentColor(for: metric)),
                        style: StrokeStyle(lineWidth: layout.ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .padding(layout.ringWidth + 1)

                Image(systemName: metric.kind.symbolName)
                    .font(.system(size: layout.iconSize, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.9))
            }
            .frame(width: layout.circleDiameter, height: layout.circleDiameter)

            if showsLabel {
                VStack(spacing: 0) {
                    Text(metric.primaryText)
                        .font(.system(size: layout.valueFontSize, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.98))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(y: 2)
    }

    /// Drops the icon (or spinner) when larger widget text no longer
    /// leaves room for it, so the message itself stays readable.
    private func emptyState(layout: LayoutMetrics) -> some View {
        ViewThatFits(in: .vertical) {
            emptyStateStack(layout: layout, showsIcon: true)
            emptyStateStack(layout: layout, showsIcon: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyStateStack(layout: LayoutMetrics, showsIcon: Bool) -> some View {
        VStack(spacing: layout.stackSpacing) {
            if showsIcon {
                if systemStatus.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.primary.opacity(0.92))
                } else {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: layout.iconSize, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.9))
                }
            }

            Text(systemStatus.isLoading ? "Loading Status" : "No Status Data")
                .font(.system(size: layout.titleFontSize, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.96))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if !systemStatus.isLoading, renderedSpan != .one {
                Text("System metrics are temporarily unavailable.")
                    .font(.system(size: layout.detailFontSize))
                    .foregroundStyle(Color.primary.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(layout.contentPadding)
    }

    private var visibleMetrics: [SystemStatusMetricSnapshot] {
        guard let snapshot = systemStatus.snapshot else {
            return []
        }

        let limit = switch renderedSpan {
        case .one:
            1
        case .two:
            2
        case .three, .four:
            3
        }

        return Array(snapshot.metrics.prefix(limit))
    }

    private func layout(in size: CGSize, visibleMetricCount: Int) -> LayoutMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let minSide = min(width, height)
        let contentPadding = min(minSide * 0.12, minSide * 0.18)
        let stackSpacing = min(minSide * 0.05, minSide * 0.1)
        let contentGap = min(minSide * 0.08, minSide * 0.14)
        let availableWidth = max(0, width - contentPadding * 2)
        let availableHeight = max(0, height - contentPadding * 2)
        let widthBasedCircle = (availableWidth - CGFloat(max(0, visibleMetricCount - 1)) * contentGap) / CGFloat(max(1, visibleMetricCount))
        let maxCircleByHeight = availableHeight * (renderedSpan == .one ? 0.6 : 0.52)
        let circleDiameter = max(0, min(widthBasedCircle, maxCircleByHeight))

        return LayoutMetrics(
            contentPadding: contentPadding,
            contentGap: contentGap,
            stackSpacing: stackSpacing,
            // Text runs ~40% larger than the other widgets: the ring labels
            // were hard to read at their original size.
            captionFontSize: min(circleDiameter * 0.252, 15.4) * textScale,
            titleFontSize: min(minSide * 0.238, renderedSpan == .one ? 19.6 : 22.4) * textScale,
            detailFontSize: min(minSide * 0.168, 18.2) * textScale,
            valueFontSize: min(circleDiameter * 0.336, renderedSpan == .three ? 16.8 : 19.6) * textScale,
            circleDiameter: circleDiameter,
            ringWidth: min(circleDiameter * 0.1, 7),
            // Follows the text size, capped so the symbol stays inside the ring.
            iconSize: min(min(circleDiameter * 0.28, renderedSpan == .three ? 16 : 20) * textScale, circleDiameter * 0.5)
        )
    }

    private var backgroundTintColor: NSColor {
        .windowBackgroundColor
    }

    private func accentColor(for metric: SystemStatusMetricSnapshot) -> NSColor {
        switch metric.kind {
        case .cpu:
            if metric.progress >= 0.85 {
                return .systemRed
            }

            if metric.progress >= 0.65 {
                return .systemOrange
            }

            return .systemYellow
        case .memory:
            if metric.progress >= 0.85 {
                return .systemRed
            }

            if metric.progress >= 0.7 {
                return .systemOrange
            }

            return .systemPurple
        case .network:
            if metric.progress >= 0.75 {
                return .systemBlue
            }

            if metric.progress > 0.15 {
                return .systemTeal
            }

            return .systemGreen
        }
    }
}

private struct LayoutMetrics {
    let contentPadding: CGFloat
    let contentGap: CGFloat
    let stackSpacing: CGFloat
    let captionFontSize: CGFloat
    let titleFontSize: CGFloat
    let detailFontSize: CGFloat
    let valueFontSize: CGFloat
    let circleDiameter: CGFloat
    let ringWidth: CGFloat
    let iconSize: CGFloat
}
