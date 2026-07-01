//
//  WeatherWidgetTileView.swift
//  Docky
//

import AppKit
import CoreLocation
import SwiftUI

struct WeatherWidgetTileView: View {
    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool
    var isExpanded: Bool = false
    var isExpandedPreviewOpen: Bool = false

    @ObservedObject private var weather = WeatherService.shared

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        GeometryReader { proxy in
            let layout = layout(in: proxy.size)
            let expandedLayout = expandedLayout(in: proxy.size)

            ZStack {
                LinearGradient(
                    colors: backgroundColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .dockyGlassBorder(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                if !isWithinStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }

                content(layout: layout)
                    .opacity(isExpanded || isExpandedPreviewOpen ? 0 : 1)
                    .animation(.easeOut(duration: 0.12), value: isExpanded)
                    .animation(.easeOut(duration: 0.12), value: isExpandedPreviewOpen)

                if isExpanded {
                    expandedContent(layout: expandedLayout)
                        .transition(
                            .opacity.animation(
                                .easeInOut(duration: 0.22).delay(
                                    0.22
                                )
                            ).combined(with: .scale).combined(with: .slide)
                        )
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isExpanded)
            .animation(.easeOut(duration: 0.12), value: isExpandedPreviewOpen)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task {
            weather.ensureFreshWeather()
        }
    }

    @ViewBuilder
    private func content(layout: LayoutMetrics) -> some View {
        if weather.permissionStatus != .granted {
            permissionCTA(isExpanded: false)
        } else if let snapshot = weather.snapshot {
            switch renderedSpan {
            case .one:
                oneUp(snapshot: snapshot, layout: layout)
            case .two:
                twoUp(snapshot: snapshot, layout: layout)
            case .three, .four:
                threeUp(snapshot: snapshot, layout: layout)
            }
        } else {
            placeholder(layout: layout)
        }
    }

    @ViewBuilder
    private func expandedContent(layout: ExpandedLayoutMetrics) -> some View {
        if weather.permissionStatus != .granted {
            permissionCTA(isExpanded: true)
        } else if let snapshot = weather.snapshot {
            expandedView(snapshot: snapshot, layout: layout)
        } else {
            expandedPlaceholder(layout: layout)
        }
    }

    private func permissionCTA(isExpanded: Bool) -> some View {
        WidgetPermissionCTAView(
            permission: .location,
            status: weather.permissionStatus,
            renderedSpan: renderedSpan,
            isExpanded: isExpanded,
            foreground: .white
        )
    }

    private func expandedView(snapshot: WeatherSnapshot, layout: ExpandedLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            HStack(alignment: .top, spacing: layout.contentGap) {
                VStack(alignment: .leading, spacing: layout.stackSpacing) {
                    Text(snapshot.locationName)
                        .font(.system(size: layout.locationFontSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(snapshot.roundedTemperatureText)
                        .font(.system(size: layout.temperatureFontSize, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 0)

                Image(systemName: snapshot.symbolName)
                    .font(.system(size: layout.symbolSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .symbolRenderingMode(.hierarchical)
            }

            Text(conditionLine(for: snapshot))
                .font(.system(size: layout.secondaryFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(2)

            Spacer(minLength: 0)

            forecastRow(for: snapshot.forecast, layout: layout)
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func conditionLine(for snapshot: WeatherSnapshot) -> String {
        var parts: [String] = [snapshot.conditionDescription]

        if let high = snapshot.highTemperature {
            parts.append("H: \(Int(high.rounded()))°")
        }
        if let low = snapshot.lowTemperature {
            parts.append("L: \(Int(low.rounded()))°")
        }

        return parts.joined(separator: " • ")
    }

    @ViewBuilder
    private func forecastRow(for forecast: [WeatherForecastDay], layout: ExpandedLayoutMetrics) -> some View {
        if !forecast.isEmpty {
            HStack(spacing: layout.forecastSpacing) {
                ForEach(forecast.prefix(5)) { day in
                    forecastColumn(day: day, layout: layout)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func forecastColumn(day: WeatherForecastDay, layout: ExpandedLayoutMetrics) -> some View {
        VStack(spacing: layout.forecastStackSpacing) {
            Text(day.weekdayShortText)
                .font(.system(size: layout.forecastDayFontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .textCase(.uppercase)
                .lineLimit(1)

            Image(systemName: day.symbolName)
                .font(.system(size: layout.forecastSymbolSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .symbolRenderingMode(.hierarchical)
                .frame(maxHeight: .infinity)

            VStack(spacing: 1) {
                if let high = day.highTemperature {
                    Text("\(Int(high.rounded()))°")
                        .font(.system(size: layout.forecastTempFontSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                }
                if let low = day.lowTemperature {
                    Text("\(Int(low.rounded()))°")
                        .font(.system(size: layout.forecastTempFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.66))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, layout.metricPadding)
        .padding(.horizontal, layout.metricPadding * 0.6)
        .background(
            RoundedRectangle(cornerRadius: layout.metricCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }

    private func expandedPlaceholder(layout: ExpandedLayoutMetrics) -> some View {
        VStack(spacing: layout.stackSpacing) {
            if weather.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white.opacity(0.92))
            } else {
                Image(systemName: placeholderSymbolName)
                    .font(.system(size: layout.symbolSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }

            Text(placeholderTitle)
                .font(.system(size: layout.locationFontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .multilineTextAlignment(.center)

            if let lastErrorDescription = weather.lastErrorDescription {
                Text(lastErrorDescription)
                    .font(.system(size: layout.secondaryFontSize))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func oneUp(snapshot: WeatherSnapshot, layout: LayoutMetrics) -> some View {
        VStack(spacing: layout.stackSpacing) {
            Image(systemName: snapshot.symbolName)
                .font(.system(size: layout.symbolSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
            Text(snapshot.roundedTemperatureText)
                .font(.system(size: layout.temperatureFontSize, weight: .bold))
        }
        .foregroundStyle(.white.opacity(0.96))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func twoUp(snapshot: WeatherSnapshot, layout: LayoutMetrics) -> some View {
        HStack(spacing: layout.contentGap) {
            Image(systemName: snapshot.symbolName)
                .font(.system(size: layout.symbolSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))

            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                Text(snapshot.roundedTemperatureText)
                    .font(.system(size: layout.temperatureFontSize, weight: .bold))
                if !snapshot.highLowText.isEmpty {
                    Text(snapshot.highLowText)
                        .font(.system(size: layout.secondaryFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.74))
                }
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.96))
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func threeUp(snapshot: WeatherSnapshot, layout: LayoutMetrics) -> some View {
        HStack(spacing: layout.contentGap) {
            Image(systemName: snapshot.symbolName)
                .font(.system(size: layout.symbolSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .frame(width: layout.leadingColumnWidth)

            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                Text(snapshot.locationName)
                    .font(.system(size: layout.secondaryFontSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Text(snapshot.roundedTemperatureText)
                    .font(.system(size: layout.temperatureFontSize, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                Text(snapshot.conditionDescription)
                    .font(.system(size: layout.secondaryFontSize))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if !snapshot.highLowText.isEmpty {
                Text(snapshot.highLowText)
                    .font(.system(size: layout.secondaryFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(layout.contentPadding)
        .padding(.horizontal, (cornerRadius - layout.contentPadding) / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func placeholder(layout: LayoutMetrics) -> some View {
        VStack(spacing: layout.stackSpacing) {
            if weather.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.9))
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Image(systemName: placeholderSymbolName)
                    .font(.system(size: layout.symbolSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }

            Text(placeholderTitle)
                .font(.system(size: layout.secondaryFontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)

            if renderedSpan != .one, let lastErrorDescription = weather.lastErrorDescription {
                Text(lastErrorDescription)
                    .font(.system(size: max(layout.secondaryFontSize - 1, 9)))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineLimit(renderedSpan == .two ? 2 : 1)
            }
        }
        .padding(layout.contentPadding)
        .padding(.horizontal, (cornerRadius - layout.contentPadding) / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func expandedLayout(in size: CGSize) -> ExpandedLayoutMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let minSide = min(width, height)
        let contentPadding = min(max(minSide * 0.08, 12), 22)
        let contentGap = min(max(minSide * 0.06, 10), 22)
        let stackSpacing = min(max(minSide * 0.025, 4), 10)
        let sectionSpacing = min(max(minSide * 0.05, 8), 8)

        return ExpandedLayoutMetrics(
            contentPadding: contentPadding,
            contentGap: contentGap,
            stackSpacing: stackSpacing,
            sectionSpacing: sectionSpacing,
            symbolSize: min(max(minSide * 0.26, 36), 96),
            temperatureFontSize: min(max(minSide * 0.22, 36), 78),
            locationFontSize: min(max(minSide * 0.07, 14), 22),
            secondaryFontSize: min(max(minSide * 0.05, 11), 16),
            metricLabelFontSize: min(max(minSide * 0.035, 9), 12),
            metricValueFontSize: min(max(minSide * 0.06, 14), 22),
            metricPadding: min(max(minSide * 0.022, 6), 10),
            metricCornerRadius: min(max(minSide * 0.04, 8), 14),
            forecastSpacing: min(max(minSide * 0.015, 4), 8),
            forecastStackSpacing: min(max(minSide * 0.012, 2), 6),
            forecastDayFontSize: min(max(minSide * 0.04, 9), 13),
            forecastSymbolSize: min(max(minSide * 0.07, 16), 26),
            forecastTempFontSize: min(max(minSide * 0.045, 10), 14)
        )
    }

    private func layout(in size: CGSize) -> LayoutMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let minSide = min(width, height)
        let contentPadding = min(minSide * 0.12, minSide * 0.18)
        let contentGap = min(minSide * 0.12, minSide * 0.2)
        let stackSpacing = min(minSide * 0.05, minSide * 0.09)

        return LayoutMetrics(
            contentPadding: contentPadding,
            contentGap: contentGap,
            stackSpacing: stackSpacing,
            symbolSize: min(minSide * 0.32, 34),
            temperatureFontSize: min(minSide * 0.24, renderedSpan == .one ? 26 : 24),
            secondaryFontSize: min(minSide * 0.13, 13),
            leadingColumnWidth: min(minSide * 0.36, 42)
        )
    }

    private var placeholderTitle: String {
        switch weather.authorizationStatus {
        case .denied, .restricted:
            "Enable Location"
        default:
            weather.isLoading ? "Loading Weather" : "Weather"
        }
    }

    private var placeholderSymbolName: String {
        switch weather.authorizationStatus {
        case .denied, .restricted:
            "location.slash.fill"
        default:
            "cloud.sun.fill"
        }
    }

    private var backgroundColors: [Color] {
        if let snapshot = weather.snapshot {
            switch snapshot.symbolName {
            case "sun.max.fill":
                return [Color(red: 0.52, green: 0.78, blue: 0.98), Color(red: 0.18, green: 0.48, blue: 0.88)]
            case "moon.stars.fill":
                return [Color(red: 0.40, green: 0.49, blue: 0.78), Color(red: 0.12, green: 0.15, blue: 0.38)]
            case "cloud.bolt.rain.fill":
                return [Color(red: 0.19, green: 0.24, blue: 0.41), Color(red: 0.35, green: 0.42, blue: 0.63)]
            case "cloud.rain.fill", "cloud.drizzle.fill", "cloud.snow.fill", "cloud.fog.fill":
                return [Color(red: 0.30, green: 0.39, blue: 0.56), Color(red: 0.46, green: 0.58, blue: 0.77)]
            default:
                return [Color(red: 0.28, green: 0.48, blue: 0.86), Color(red: 0.60, green: 0.76, blue: 0.96)]
            }
        }

        return [Color(red: 0.23, green: 0.38, blue: 0.67), Color(red: 0.52, green: 0.67, blue: 0.88)]
    }
}

private struct LayoutMetrics {
    let contentPadding: CGFloat
    let contentGap: CGFloat
    let stackSpacing: CGFloat
    let symbolSize: CGFloat
    let temperatureFontSize: CGFloat
    let secondaryFontSize: CGFloat
    let leadingColumnWidth: CGFloat
}

private struct ExpandedLayoutMetrics {
    let contentPadding: CGFloat
    let contentGap: CGFloat
    let stackSpacing: CGFloat
    let sectionSpacing: CGFloat
    let symbolSize: CGFloat
    let temperatureFontSize: CGFloat
    let locationFontSize: CGFloat
    let secondaryFontSize: CGFloat
    let metricLabelFontSize: CGFloat
    let metricValueFontSize: CGFloat
    let metricPadding: CGFloat
    let metricCornerRadius: CGFloat
    let forecastSpacing: CGFloat
    let forecastStackSpacing: CGFloat
    let forecastDayFontSize: CGFloat
    let forecastSymbolSize: CGFloat
    let forecastTempFontSize: CGFloat
}
