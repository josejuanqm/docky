//
//  BatteriesWidgetTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct BatteriesWidgetTileView: View {
    @Environment(\.widgetTextScale) private var textScale

    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool
    var isExpanded: Bool = false
    var isExpandedPreviewOpen: Bool = false

    @ObservedObject private var batteries = BatteriesService.shared

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        TimelineView(.periodic(from: .now, by: 60)) { _ in
            GeometryReader { proxy in
                let layout = layout(in: proxy.size, visibleDeviceCount: currentVisibleDeviceCount)

                ZStack {
                    Color(nsColor: backgroundTintColor)
                        .dockyGlassBorder(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                    if !isWithinStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }

                    content(layout: layout)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task {
            batteries.ensureFreshBatteries()
        }
    }

    @ViewBuilder
    private func content(layout: LayoutMetrics) -> some View {
        if let snapshot = batteries.snapshot, !snapshot.isEmpty {
            indicatorStrip(devices: visibleDevices(from: snapshot), layout: layout)
        } else {
            emptyState(layout: layout)
        }
    }

    /// Rings with their labels when there's room; when larger widget text
    /// no longer fits, the labels go and the rings alone show the levels.
    private func indicatorStrip(devices: [BatteryDeviceSnapshot], layout: LayoutMetrics) -> some View {
        ViewThatFits(in: .vertical) {
            indicatorRow(devices: devices, layout: layout, showsLabels: true)
            indicatorRow(devices: devices, layout: layout, showsLabels: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func indicatorRow(devices: [BatteryDeviceSnapshot], layout: LayoutMetrics, showsLabels: Bool) -> some View {
        HStack(alignment: .center, spacing: layout.contentGap) {
            ForEach(devices) { device in
                batteryIndicator(device: device, layout: layout, showsLabel: showsLabels)
                    .offset(y: 2)
            }
        }
        .padding(layout.contentPadding)
    }

    private func batteryIndicator(device: BatteryDeviceSnapshot, layout: LayoutMetrics, showsLabel: Bool) -> some View {
        VStack(spacing: layout.stackSpacing) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.14), lineWidth: layout.ringWidth)

                Circle()
                    .trim(from: 0, to: indicatorProgress(for: device))
                    .stroke(
                        Color(nsColor: accentColor(for: device)),
                        style: StrokeStyle(lineWidth: layout.ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .padding(layout.ringWidth + 1)

                Image(systemName: centerSymbolName(for: device))
                    .font(.system(size: layout.iconSize, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.9))
            }
            .overlay(alignment: .topTrailing) {
                if device.isCharging {
                    ZStack {
                        Circle()
                            .fill(Color(nsColor: accentColor(for: device)).opacity(0.96))

                        Image(systemName: "bolt.fill")
                            .font(.system(size: layout.boltSize, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: layout.chargeBadgeDiameter, height: layout.chargeBadgeDiameter)
                    .offset(x: layout.chargeBadgeOffset, y: -layout.chargeBadgeOffset)
                }
            }
            .frame(width: layout.circleDiameter, height: layout.circleDiameter)

            if showsLabel {
                HStack(spacing: 3) {
                    if device.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: layout.boltSize * textScale, weight: .bold))
                            .foregroundStyle(Color(nsColor: accentColor(for: device)))
                    }

                    Text(primaryPercentageText(for: device))
                        .font(.system(size: layout.percentageFontSize, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.98))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func visibleDevices(from snapshot: BatteriesSnapshot) -> [BatteryDeviceSnapshot] {
        Array(snapshot.devices.prefix(maxVisibleDeviceCount))
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
                if batteries.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.primary.opacity(0.92))
                } else {
                    Image(systemName: "battery.100percent")
                        .font(.system(size: layout.iconSize, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.9))
                }
            }

            Text(batteries.isLoading ? "Loading Batteries" : "No Battery Data")
                .font(.system(size: layout.titleFontSize, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.96))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if !batteries.isLoading, renderedSpan != .one {
                Text("Connect a battery-powered Mac or accessory to show charge levels here.")
                    .font(.system(size: layout.detailFontSize))
                    .foregroundStyle(Color.primary.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineLimit(renderedSpan == .two ? 2 : 3)
            }
        }
        .padding(layout.contentPadding)
    }

    private var maxVisibleDeviceCount: Int {
        switch renderedSpan {
        case .one:
            1
        case .two:
            2
        case .three, .four:
            4
        }
    }

    private var currentVisibleDeviceCount: Int {
        max(1, min(maxVisibleDeviceCount, batteries.snapshot?.devices.count ?? 1))
    }

    private func indicatorProgress(for device: BatteryDeviceSnapshot) -> CGFloat {
        CGFloat(max(0, min(100, device.primaryPercentage ?? 0))) / 100
    }

    private func primaryPercentageText(for device: BatteryDeviceSnapshot) -> String {
        guard let percentage = device.primaryPercentage else {
            return "--"
        }

        return "\(percentage)%"
    }

    private func centerSymbolName(for device: BatteryDeviceSnapshot) -> String {
        switch device.kind {
        case .mac:
            return "laptopcomputer"
        case .keyboard:
            return "keyboard"
        case .trackpad:
            return "rectangle.filled.and.hand.point.up.left"
        case .mouse:
            return "computermouse"
        case .headphones:
            return "headphones"
        case .accessory:
            return "battery.100percent"
        }
    }

    private func layout(in size: CGSize, visibleDeviceCount: Int) -> LayoutMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let minSide = min(width, height)
        let contentPadding = min(minSide * 0.12, minSide * 0.18)
        let stackSpacing = min(minSide * 0.05, minSide * 0.1)
        let contentGap = min(minSide * 0.08, minSide * 0.14)
        let availableWidth = max(0, width - contentPadding * 2)
        let availableHeight = max(0, height - contentPadding * 2)
        let widthBasedCircle = (availableWidth - CGFloat(max(0, visibleDeviceCount - 1)) * contentGap) / CGFloat(max(1, visibleDeviceCount))
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
            percentageFontSize: min(circleDiameter * 0.336, renderedSpan == .three ? 16.8 : 19.6) * textScale,
            circleDiameter: circleDiameter,
            ringWidth: min(circleDiameter * 0.1, 7),
            // Follows the text size, capped so the symbol stays inside the ring.
            iconSize: min(min(circleDiameter * 0.28, renderedSpan == .three ? 16 : 20) * textScale, circleDiameter * 0.5),
            boltSize: min(circleDiameter * 0.16, 10),
            chargeBadgeDiameter: min(circleDiameter * 0.24, 16),
            chargeBadgeOffset: min(circleDiameter * 0.05, 4)
        )
    }

    private var backgroundTintColor: NSColor {
        .windowBackgroundColor
    }

    private func accentColor(for device: BatteryDeviceSnapshot) -> NSColor {
        guard let percentage = device.minimumPercentage else {
            return .secondaryLabelColor
        }

        if percentage <= 10 {
            return .systemRed
        }

        if device.isCharging {
            return .systemGreen
        }

        if percentage <= 20 {
            return .systemOrange
        }

        return .systemGreen
    }
}

private struct LayoutMetrics {
    let contentPadding: CGFloat
    let contentGap: CGFloat
    let stackSpacing: CGFloat
    let captionFontSize: CGFloat
    let titleFontSize: CGFloat
    let detailFontSize: CGFloat
    let percentageFontSize: CGFloat
    let circleDiameter: CGFloat
    let ringWidth: CGFloat
    let iconSize: CGFloat
    let boltSize: CGFloat
    let chargeBadgeDiameter: CGFloat
    let chargeBadgeOffset: CGFloat
}
