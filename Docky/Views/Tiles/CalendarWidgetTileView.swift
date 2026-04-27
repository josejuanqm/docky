//
//  CalendarWidgetTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct CalendarWidgetTileView: View {
    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool

    @ObservedObject private var calendar = CalendarService.shared

    private var showsDateVariant: Bool {
        tile.kind == .calendarDate
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            GeometryReader { proxy in
                let layout = layout(in: proxy.size)

                ZStack {
                    Color(nsColor: backgroundTintColor)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))

                    if !isWithinStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }

                    content(layout: layout, now: context.date)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task {
            guard !showsDateVariant else {
                return
            }

            calendar.ensureFreshEvent()
        }
    }

    @ViewBuilder
    private func content(layout: LayoutMetrics, now: Date) -> some View {
        if showsDateVariant {
            dateOneUp(layout: layout, now: now)
        } else if let event = calendar.nextEvent {
            switch renderedSpan {
            case .one:
                oneUp(event: event, layout: layout, now: now)
            case .two:
                twoUp(event: event, layout: layout, now: now)
            case .three:
                threeUp(event: event, layout: layout, now: now)
            }
        } else {
            emptyState(layout: layout)
        }
    }

    private func dateOneUp(layout: LayoutMetrics, now: Date) -> some View {
        VStack(spacing: layout.stackSpacing * 0) {
            Text(shortWeekdayText(for: now))
                .font(.system(size: layout.captionFontSize * 1.25, weight: .semibold))
                .foregroundStyle(Color.red)
                .tracking(0.6)
                .offset(y: 2)

            Text(dayNumberText(for: now))
                .font(.system(size: layout.prominentFontSize * 2.5, weight: .medium, design: .default))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .offset(y: -1)
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(fullDateText(for: now))
    }

    private func oneUp(event: CalendarEventSnapshot, layout: LayoutMetrics, now: Date) -> some View {
        VStack(spacing: layout.stackSpacing) {
            Text("UP NEXT")
                .font(.system(size: layout.captionFontSize, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.72))

            Text(shortTimeText(for: event, now: now))
                .font(.system(size: layout.prominentFontSize * 0.75, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.98))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Circle()
                .fill(Color(nsColor: event.color).opacity(0.92))
                .frame(width: 6, height: 6)
        }
        .padding(layout.contentPadding / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func twoUp(event: CalendarEventSnapshot, layout: LayoutMetrics, now: Date) -> some View {
        HStack(spacing: layout.contentGap) {
            eventAccent(event: event, layout: layout)

            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                Text("UP NEXT")
                    .font(.system(size: layout.captionFontSize, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.72))

                Text(event.title)
                    .font(.system(size: layout.titleFontSize, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.98))
                    .lineLimit(2)

                scheduleRow(for: event, layout: layout, now: now, opacity: 0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func threeUp(event: CalendarEventSnapshot, layout: LayoutMetrics, now: Date) -> some View {
        HStack(spacing: layout.contentGap) {
            eventAccent(event: event, layout: layout)

            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                HStack(spacing: 6) {
                    Text("UP NEXT")
                        .font(.system(size: layout.captionFontSize, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.72))

                    Text(event.calendarTitle)
                        .font(.system(size: layout.captionFontSize, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.58))
                        .lineLimit(1)
                }

                Text(event.title)
                    .font(.system(size: layout.titleFontSize, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.98))
                    .lineLimit(2)

                scheduleRow(for: event, layout: layout, now: now, opacity: 0.84)

                if shouldShowLocation(for: event) {
                    Text(event.location)
                        .font(.system(size: layout.detailFontSize))
                        .foregroundStyle(Color.primary.opacity(0.66))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(layout.contentPadding)
        .padding(.horizontal, (cornerRadius - layout.contentPadding) / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func emptyState(layout: LayoutMetrics) -> some View {
        VStack(alignment: .center, spacing: layout.stackSpacing) {
            if calendar.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.primary.opacity(0.92))
            } else {
                Image(systemName: calendar.lastErrorDescription == nil ? "calendar.badge.clock" : "calendar.badge.exclamationmark")
                    .font(.system(size: layout.emptyIconSize, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.9))
            }

            Text(emptyTitle)
                .font(.system(size: layout.titleFontSize, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.96))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if renderedSpan != .one, let detail = emptyDetail {
                Text(detail)
                    .font(.system(size: layout.detailFontSize))
                    .foregroundStyle(Color.primary.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineLimit(renderedSpan == .two ? 2 : 3)
            }
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func eventAccent(event: CalendarEventSnapshot, layout: LayoutMetrics) -> some View {
        RoundedRectangle(cornerRadius: layout.accentWidth / 2, style: .continuous)
            .fill(Color(nsColor: event.color).opacity(0.96))
            .frame(width: layout.accentWidth)
    }

    private func scheduleRow(for event: CalendarEventSnapshot, layout: LayoutMetrics, now: Date, opacity: Double) -> some View {
        HStack(spacing: 4) {
            Text(scheduleLine(for: event, now: now))
                .lineLimit(1)

            if let quickJoinURL = event.quickJoinURL {
                Text("•")
                Button(joinLabel(for: quickJoinURL)) {
                    NSWorkspace.shared.open(quickJoinURL)
                }
                .buttonStyle(.plain)
                .underline()
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: layout.detailFontSize, weight: .medium))
        .foregroundStyle(Color.primary.opacity(opacity))
    }

    private var backgroundTintColor: NSColor {
        NSColor.windowBackgroundColor
    }

    private func shouldShowLocation(for event: CalendarEventSnapshot) -> Bool {
        guard !event.location.isEmpty else {
            return false
        }

        guard let quickJoinURL = event.quickJoinURL else {
            return true
        }

        let normalizedLocation = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedLocation != quickJoinURL.absoluteString
    }

    private func joinLabel(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host.replacingOccurrences(of: "www.", with: "")
        }

        return url.absoluteString
    }

    private func layout(in size: CGSize) -> LayoutMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let minSide = min(width, height)
        let contentPadding = min(max(minSide * 0.12, 6), minSide * 0.18)
        let contentGap = min(max(minSide * 0.1, 6), minSide * 0.18)
        let stackSpacing = min(max(minSide * 0.05, 3), minSide * 0.1)

        return LayoutMetrics(
            contentPadding: contentPadding,
            contentGap: contentGap,
            stackSpacing: stackSpacing,
            accentWidth: min(max(minSide * 0.09, 6), 10),
            captionFontSize: min(max(minSide * 0.1, 8), 11),
            titleFontSize: min(max(minSide * 0.17, 11), renderedSpan == .one ? 14 : 16),
            prominentFontSize: min(max(minSide * 0.27, 16), 26),
            detailFontSize: min(max(minSide * 0.12, 9), 13),
            emptyIconSize: min(max(minSide * 0.28, 18), 28)
        )
    }

    private var emptyTitle: String {
        if calendar.isLoading {
            return "Loading Calendar"
        }

        if calendar.lastErrorDescription != nil {
            return "Calendar Unavailable"
        }

        return "No Upcoming Events"
    }

    private var emptyDetail: String? {
        if let lastErrorDescription = calendar.lastErrorDescription {
            return lastErrorDescription
        }

        return "You’re clear for now."
    }

    private func shortTimeText(for event: CalendarEventSnapshot, now: Date) -> String {
        if event.isAllDay {
            return "ALL DAY"
        }

        if Calendar.autoupdatingCurrent.isDate(event.startDate, inSameDayAs: now) {
            return timeFormatter.string(from: event.startDate)
        }

        return shortDateTimeFormatter.string(from: event.startDate)
    }

    private func scheduleLine(for event: CalendarEventSnapshot, now: Date) -> String {
        let relative = relativeTimeText(for: event.startDate, now: now)

        if event.isAllDay {
            return Calendar.autoupdatingCurrent.isDate(event.startDate, inSameDayAs: now)
                ? "Today, all day"
                : "\(dayFormatter.string(from: event.startDate)), all day"
        }

        let startTime = timeFormatter.string(from: event.startDate)
        if relative.isEmpty {
            return startTime
        }

        return "\(startTime) • \(relative)"
    }

    private func relativeTimeText(for date: Date, now: Date) -> String {
        let interval = Int(date.timeIntervalSince(now))
        if interval <= 0 {
            return "now"
        }

        let minutes = interval / 60
        if minutes < 60 {
            return "in \(minutes)m"
        }

        let hours = minutes / 60
        if hours < 24 {
            let remainingMinutes = minutes % 60
            return remainingMinutes == 0 ? "in \(hours)h" : "in \(hours)h \(remainingMinutes)m"
        }

        let days = hours / 24
        return days == 1 ? "tomorrow" : "in \(days)d"
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }

    private var shortDateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d j:mm")
        return formatter
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }

    private func shortWeekdayText(for date: Date) -> String {
        shortWeekdayFormatter.string(from: date).localizedUppercase
    }

    private func dayNumberText(for date: Date) -> String {
        dayNumberFormatter.string(from: date)
    }

    private func shortMonthText(for date: Date) -> String {
        shortMonthFormatter.string(from: date).localizedUppercase
    }

    private func fullDateText(for date: Date) -> String {
        fullDateFormatter.string(from: date)
    }

    private var shortWeekdayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }

    private var dayNumberFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }

    private var shortMonthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }

    private var fullDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }
}

private struct LayoutMetrics {
    let contentPadding: CGFloat
    let contentGap: CGFloat
    let stackSpacing: CGFloat
    let accentWidth: CGFloat
    let captionFontSize: CGFloat
    let titleFontSize: CGFloat
    let prominentFontSize: CGFloat
    let detailFontSize: CGFloat
    let emptyIconSize: CGFloat
}
