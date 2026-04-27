//
//  BatteriesWidgetTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct BatteriesWidgetTileView: View {
    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool

    @ObservedObject private var batteries = BatteriesService.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            GeometryReader { proxy in
                let layout = layout(in: proxy.size, visibleDeviceCount: currentVisibleDeviceCount)

                ZStack {
                    Color(nsColor: backgroundTintColor)
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))

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

    private func indicatorStrip(devices: [BatteryDeviceSnapshot], layout: LayoutMetrics) -> some View {
        HStack(alignment: .center, spacing: layout.contentGap) {
            ForEach(devices) { device in
                batteryIndicator(device: device, layout: layout)
                    .offset(y: 2)
            }
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func batteryIndicator(device: BatteryDeviceSnapshot, layout: LayoutMetrics) -> some View {
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

            HStack(spacing: 3) {
                if device.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: layout.boltSize, weight: .bold))
                        .foregroundStyle(Color(nsColor: accentColor(for: device)))
                }

                Text(primaryPercentageText(for: device))
                    .font(.system(size: layout.percentageFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.98))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func visibleDevices(from snapshot: BatteriesSnapshot) -> [BatteryDeviceSnapshot] {
        Array(snapshot.devices.prefix(maxVisibleDeviceCount))
    }

    private func emptyState(layout: LayoutMetrics) -> some View {
        VStack(spacing: layout.stackSpacing) {
            if batteries.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.primary.opacity(0.92))
            } else {
                Image(systemName: "battery.100percent")
                    .font(.system(size: layout.iconSize, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.9))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var maxVisibleDeviceCount: Int {
        switch renderedSpan {
        case .one:
            1
        case .two:
            2
        case .three:
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
        let contentPadding = min(max(minSide * 0.12, 6), minSide * 0.18)
        let stackSpacing = min(max(minSide * 0.05, 3), minSide * 0.1)
        let contentGap = min(max(minSide * 0.08, 6), minSide * 0.14)
        let availableWidth = max(1, width - contentPadding * 2)
        let availableHeight = max(1, height - contentPadding * 2)
        let widthBasedCircle = (availableWidth - CGFloat(max(0, visibleDeviceCount - 1)) * contentGap) / CGFloat(visibleDeviceCount)
        let maxCircleByHeight = availableHeight * (renderedSpan == .one ? 0.6 : 0.52)
        let circleDiameter = max(30, min(widthBasedCircle, maxCircleByHeight))

        return LayoutMetrics(
            contentPadding: contentPadding,
            contentGap: contentGap,
            stackSpacing: stackSpacing,
            captionFontSize: min(max(circleDiameter * 0.18, 8), 11),
            titleFontSize: min(max(minSide * 0.17, 11), renderedSpan == .one ? 14 : 16),
            detailFontSize: min(max(minSide * 0.12, 9), 13),
            percentageFontSize: min(max(circleDiameter * 0.24, 10), renderedSpan == .three ? 12 : 14),
            circleDiameter: circleDiameter,
            ringWidth: min(max(circleDiameter * 0.1, 4), 7),
            iconSize: min(max(circleDiameter * 0.28, 12), renderedSpan == .three ? 16 : 20),
            boltSize: min(max(circleDiameter * 0.16, 7), 10),
            chargeBadgeDiameter: min(max(circleDiameter * 0.24, 11), 16),
            chargeBadgeOffset: min(max(circleDiameter * 0.05, 2), 4)
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
