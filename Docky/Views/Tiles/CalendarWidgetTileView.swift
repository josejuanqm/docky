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
    var isExpanded: Bool = false
    var isExpandedPreviewOpen: Bool = false

    @ObservedObject private var calendar = CalendarService.shared

    private var showsDateVariant: Bool {
        tile.kind == .calendarDate
    }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        TimelineView(.periodic(from: .now, by: 60)) { context in
            GeometryReader { proxy in
                let layout = layout(in: proxy.size)
                let expandedLayout = expandedLayout(in: proxy.size)

                ZStack {
                    Color(nsColor: backgroundTintColor)
                        .dockyGlassBorder(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                    if !isWithinStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }

                    content(layout: layout, now: context.date)
                        .opacity(isExpandedPreviewOpen && isExpanded ? 0 : 1)

                    if isExpanded {
                        expandedContent(layout: expandedLayout, now: context.date)
                            .transition(
                                .opacity.animation(
                                    .easeInOut(duration: 0.22).delay(0.22)
                                ).combined(with: .scale).combined(with: .slide)
                            )
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: isExpanded)
                .animation(.easeOut(duration: 0.12), value: isExpandedPreviewOpen)
            }
        }
        .opacity(isExpandedPreviewOpen && !isExpanded ? 0.5 : 1)
        .animation(.easeOut(duration: 0.12), value: isExpandedPreviewOpen)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task {
            calendar.ensureFreshEvent()
        }
    }

    @ViewBuilder
    private func content(layout: LayoutMetrics, now: Date) -> some View {
        if showsDateVariant {
            // The date variant only renders the calendar day, which needs no
            // EventKit access, so it never shows the permission CTA.
            dateOneUp(layout: layout, now: now)
        } else if calendar.permissionStatus != .granted {
            permissionCTA(isExpanded: false)
        } else if let event = calendar.nextEvent {
            switch renderedSpan {
            case .one:
                oneUp(event: event, layout: layout, now: now)
            case .two:
                twoUp(event: event, layout: layout, now: now)
            case .three, .four:
                threeUp(event: event, layout: layout, now: now)
            }
        } else {
            emptyState(layout: layout)
        }
    }

    private func permissionCTA(isExpanded: Bool) -> some View {
        WidgetPermissionCTAView(
            permission: .calendar,
            status: calendar.permissionStatus,
            renderedSpan: renderedSpan,
            isExpanded: isExpanded
        )
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
            }

            Spacer(minLength: 0)
        }
        .padding(layout.contentPadding)
        .padding(.horizontal, (cornerRadius - layout.contentPadding) / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func expandedContent(layout: ExpandedLayoutMetrics, now: Date) -> some View {
        if calendar.permissionStatus != .granted {
            permissionCTA(isExpanded: true)
        } else if calendar.upcomingEvents.isEmpty {
            expandedEmpty(layout: layout, now: now)
        } else {
            expandedAgenda(layout: layout, now: now)
        }
    }

    private func expandedAgenda(layout: ExpandedLayoutMetrics, now: Date) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            expandedHeader(layout: layout, now: now)
            expandedEventList(layout: layout, now: now)
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func expandedHeader(layout: ExpandedLayoutMetrics, now: Date) -> some View {
        Text(headerDateText(for: now))
            .font(.system(size: layout.headerFontSize, weight: .semibold))
            .foregroundStyle(Color.red)
            .lineLimit(1)
            .tracking(0.4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func expandedEventList(layout: ExpandedLayoutMetrics, now: Date) -> some View {
        let sections = expandedSections(now: now)

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: layout.sectionGroupSpacing) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: layout.eventRowSpacing) {
                        Text(section.title)
                            .font(.system(size: layout.sectionTitleFontSize, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.55))
                            .tracking(0.5)
                            .textCase(.uppercase)

                        ForEach(Array(section.events.enumerated()), id: \.offset) { _, event in
                            ExpandedEventRow(
                                event: event,
                                scheduleText: expandedScheduleText(for: event, now: now),
                                layout: layout
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func expandedSections(now: Date) -> [ExpandedAgendaSection] {
        let calendarRef = Calendar.autoupdatingCurrent

        var orderedDayKeys: [Date] = []
        var grouped: [Date: [CalendarEventSnapshot]] = [:]

        for event in calendar.upcomingEvents {
            let dayKey = calendarRef.startOfDay(for: event.startDate)
            if grouped[dayKey] == nil {
                orderedDayKeys.append(dayKey)
            }
            grouped[dayKey, default: []].append(event)
        }

        return orderedDayKeys.map { dayKey in
            ExpandedAgendaSection(
                id: dayKey,
                title: sectionTitle(for: dayKey, now: now),
                events: grouped[dayKey] ?? []
            )
        }
    }

    private func sectionTitle(for day: Date, now: Date) -> String {
        let calendarRef = Calendar.autoupdatingCurrent
        if calendarRef.isDate(day, inSameDayAs: now) {
            return "Today"
        }
        if calendarRef.isDateInTomorrow(day) {
            return "Tomorrow"
        }
        return sectionDayFormatter.string(from: day)
    }

    private func headerDateText(for date: Date) -> String {
        headerDateFormatter.string(from: date)
    }

    private func expandedEmpty(layout: ExpandedLayoutMetrics, now: Date) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            expandedHeader(layout: layout, now: now)

            Spacer(minLength: 0)

            VStack(spacing: layout.stackSpacing) {
                Image(systemName: calendar.lastErrorDescription == nil ? "calendar.badge.clock" : "calendar.badge.exclamationmark")
                    .font(.system(size: layout.emptyIconSize, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.84))

                Text(emptyTitle)
                    .font(.system(size: layout.eventTitleFontSize, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.94))
                    .multilineTextAlignment(.center)

                if let detail = emptyDetail {
                    Text(detail)
                        .font(.system(size: layout.eventDetailFontSize))
                        .foregroundStyle(Color.primary.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func expandedScheduleText(for event: CalendarEventSnapshot, now: Date) -> String {
        if event.isAllDay {
            return "All day"
        }

        let start = timeFormatter.string(from: event.startDate)
        let end = timeFormatter.string(from: event.endDate)
        return "\(start) – \(end)"
    }

    private var headerDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        return formatter
    }

    private var sectionDayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
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

    private func expandedLayout(in size: CGSize) -> ExpandedLayoutMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let minSide = min(width, height)
        let contentPadding = min(max(minSide * 0.07, 12), 22)
        let contentGap = min(max(minSide * 0.05, 10), 18)
        let stackSpacing = min(max(minSide * 0.025, 4), 10)
        let sectionSpacing = min(max(minSide * 0.04, 10), 18)

        return ExpandedLayoutMetrics(
            contentPadding: contentPadding,
            contentGap: contentGap,
            stackSpacing: stackSpacing,
            sectionSpacing: sectionSpacing,
            sectionGroupSpacing: min(max(minSide * 0.045, 10), 18),
            sectionTitleFontSize: min(max(minSide * 0.04, 9), 12),
            headerFontSize: min(max(minSide * 0.06, 13), 18),
            eventRowSpacing: min(max(minSide * 0.018, 4), 8),
            eventRowGap: min(max(minSide * 0.022, 6), 10),
            eventRowVerticalPadding: min(max(minSide * 0.018, 5), 8),
            eventRowHorizontalPadding: min(max(minSide * 0.025, 7), 12),
            eventRowCornerRadius: min(max(minSide * 0.03, 8), 12),
            eventTitleFontSize: min(max(minSide * 0.05, 11), 14),
            eventDetailFontSize: min(max(minSide * 0.04, 9), 12),
            accentWidth: min(max(minSide * 0.012, 3), 5),
            emptyIconSize: min(max(minSide * 0.16, 22), 36)
        )
    }

    private func layout(in size: CGSize) -> LayoutMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let minSide = min(width, height)
        let contentPadding = min(minSide * 0.12, minSide * 0.18)
        let contentGap = min(minSide * 0.1, minSide * 0.18)
        let stackSpacing = min(minSide * 0.05, minSide * 0.1)

        return LayoutMetrics(
            contentPadding: contentPadding,
            contentGap: contentGap,
            stackSpacing: stackSpacing,
            accentWidth: min(minSide * 0.09, 10),
            captionFontSize: min(minSide * 0.1, 11),
            titleFontSize: min(minSide * 0.17, renderedSpan == .one ? 14 : 16),
            prominentFontSize: min(minSide * 0.27, 26),
            detailFontSize: min(minSide * 0.12, 13),
            emptyIconSize: min(minSide * 0.28, 28)
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

private struct ExpandedLayoutMetrics {
    let contentPadding: CGFloat
    let contentGap: CGFloat
    let stackSpacing: CGFloat
    let sectionSpacing: CGFloat
    let sectionGroupSpacing: CGFloat
    let sectionTitleFontSize: CGFloat
    let headerFontSize: CGFloat
    let eventRowSpacing: CGFloat
    let eventRowGap: CGFloat
    let eventRowVerticalPadding: CGFloat
    let eventRowHorizontalPadding: CGFloat
    let eventRowCornerRadius: CGFloat
    let eventTitleFontSize: CGFloat
    let eventDetailFontSize: CGFloat
    let accentWidth: CGFloat
    let emptyIconSize: CGFloat
}

private struct ExpandedAgendaSection: Identifiable {
    let id: Date
    let title: String
    let events: [CalendarEventSnapshot]
}

private struct ExpandedEventRow: View {
    let event: CalendarEventSnapshot
    let scheduleText: String
    let layout: ExpandedLayoutMetrics

    @State private var isHovered = false

    var body: some View {
        Button(action: openInCalendar) {
            HStack(alignment: .top, spacing: layout.eventRowGap) {
                RoundedRectangle(cornerRadius: layout.accentWidth / 2, style: .continuous)
                    .fill(Color(nsColor: event.color).opacity(0.95))
                    .frame(width: layout.accentWidth)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: layout.eventTitleFontSize, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.96))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(scheduleText)
                        .font(.system(size: layout.eventDetailFontSize, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.66))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, layout.eventRowVerticalPadding)
            .padding(.horizontal, layout.eventRowHorizontalPadding)
            .contentShape(RoundedRectangle(cornerRadius: layout.eventRowCornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: layout.eventRowCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.14 : 0.06))
            )
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open in Calendar") {
                openInCalendar()
            }

            if let quickJoinURL = event.quickJoinURL {
                Button("Join Meeting") {
                    NSWorkspace.shared.open(quickJoinURL)
                }
                Button("Copy Meeting Link") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(quickJoinURL.absoluteString, forType: .string)
                }
            }

            Divider()

            Button("Copy Title") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(event.title, forType: .string)
            }

            if !event.location.isEmpty {
                Button("Copy Location") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(event.location, forType: .string)
                }
            }
        }
    }

    private func openInCalendar() {
        guard let url = URL(string: "ical://ekevent/\(event.eventIdentifier)?method=show&options=more") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
