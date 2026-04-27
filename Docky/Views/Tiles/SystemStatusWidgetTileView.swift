//
//  SystemStatusWidgetTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct SystemStatusWidgetTileView: View {
    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool

    @ObservedObject private var systemStatus = SystemStatusService.shared

    var body: some View {
        GeometryReader { proxy in
            let metrics = visibleMetrics
            let layout = layout(in: proxy.size, visibleMetricCount: max(1, metrics.count))

            ZStack {
                Color(nsColor: backgroundTintColor)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))

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

    private func indicatorStrip(metrics: [SystemStatusMetricSnapshot], layout: LayoutMetrics) -> some View {
        HStack(alignment: .center, spacing: layout.contentGap) {
            ForEach(metrics) { metric in
                metricIndicator(metric: metric, layout: layout)
            }
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func metricIndicator(metric: SystemStatusMetricSnapshot, layout: LayoutMetrics) -> some View {
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

            VStack(spacing: 0) { 
                Text(metric.primaryText)
                    .font(.system(size: layout.valueFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.98))
                    .lineLimit(1)

                Text(metric.secondaryText)
                    .font(.system(size: layout.captionFontSize, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.68))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func emptyState(layout: LayoutMetrics) -> some View {
        VStack(spacing: layout.stackSpacing) {
            if systemStatus.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.primary.opacity(0.92))
            } else {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: layout.iconSize, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.9))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .three:
            3
        }

        return Array(snapshot.metrics.prefix(limit))
    }

    private func layout(in size: CGSize, visibleMetricCount: Int) -> LayoutMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let minSide = min(width, height)
        let contentPadding = min(max(minSide * 0.12, 6), minSide * 0.18)
        let stackSpacing = min(max(minSide * 0.05, 3), minSide * 0.1)
        let contentGap = min(max(minSide * 0.08, 6), minSide * 0.14)
        let availableWidth = max(1, width - contentPadding * 2)
        let availableHeight = max(1, height - contentPadding * 2)
        let widthBasedCircle = (availableWidth - CGFloat(max(0, visibleMetricCount - 1)) * contentGap) / CGFloat(visibleMetricCount)
        let maxCircleByHeight = availableHeight * (renderedSpan == .one ? 0.6 : 0.52)
        let circleDiameter = max(30, min(widthBasedCircle, maxCircleByHeight))

        return LayoutMetrics(
            contentPadding: contentPadding,
            contentGap: contentGap,
            stackSpacing: stackSpacing,
            captionFontSize: min(max(circleDiameter * 0.18, 8), 11),
            titleFontSize: min(max(minSide * 0.17, 11), renderedSpan == .one ? 14 : 16),
            detailFontSize: min(max(minSide * 0.12, 9), 13),
            valueFontSize: min(max(circleDiameter * 0.24, 10), renderedSpan == .three ? 12 : 14),
            circleDiameter: circleDiameter,
            ringWidth: min(max(circleDiameter * 0.1, 4), 7),
            iconSize: min(max(circleDiameter * 0.28, 12), renderedSpan == .three ? 16 : 20)
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
