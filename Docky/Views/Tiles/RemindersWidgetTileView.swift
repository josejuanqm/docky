//
//  RemindersWidgetTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct RemindersWidgetTileView: View {
    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool

    @ObservedObject private var reminders = RemindersService.shared

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
            reminders.ensureFreshReminders()
        }
    }

    @ViewBuilder
    private func content(layout: LayoutMetrics, now: Date) -> some View {
        if let nextItem = reminders.snapshot?.primaryItem {
            switch renderedSpan {
            case .one:
                oneUp(item: nextItem, layout: layout, now: now)
            case .two:
                twoUp(item: nextItem, layout: layout, now: now)
            case .three:
                threeUp(item: nextItem, layout: layout, now: now)
            }
        } else {
            emptyState(layout: layout)
        }
    }

    private func oneUp(item: ReminderItemSnapshot, layout: LayoutMetrics, now: Date) -> some View {
        VStack(spacing: layout.stackSpacing) {
            Text("UP NEXT")
                .font(.system(size: layout.captionFontSize, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.72))

            Text(nextUpBadgeText(for: item, now: now))
                .font(.system(size: layout.prominentFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.98))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(item.title)
                .font(.system(size: layout.detailFontSize, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.68))
                .lineLimit(1)
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func twoUp(item: ReminderItemSnapshot, layout: LayoutMetrics, now: Date) -> some View {
        HStack(spacing: layout.contentGap) {
            accent(item: item, layout: layout, now: now)

            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                Text("UP NEXT")
                    .font(.system(size: layout.captionFontSize, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.72))

                Text(item.title)
                    .font(.system(size: layout.titleFontSize, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.98))
                    .lineLimit(2)

                Text(reminderDetailLine(for: item, now: now))
                    .font(.system(size: layout.detailFontSize, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.82))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func threeUp(item: ReminderItemSnapshot, layout: LayoutMetrics, now: Date) -> some View {
        HStack(spacing: layout.contentGap) {
            accent(item: item, layout: layout, now: now)

            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                Text("UP NEXT")
                    .font(.system(size: layout.captionFontSize, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.72))

                Text(item.title)
                    .font(.system(size: layout.titleFontSize, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.98))
                    .lineLimit(2)

                Text(detailedDueLine(for: item, now: now))
                    .font(.system(size: layout.detailFontSize, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.82))
                    .lineLimit(1)

                if !item.listTitle.isEmpty {
                    Text(item.listTitle)
                        .font(.system(size: layout.detailFontSize))
                        .foregroundStyle(Color.primary.opacity(0.64))
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
            if reminders.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.primary.opacity(0.92))
            } else {
                Image(systemName: reminders.lastErrorDescription == nil ? "checklist.checked" : "checklist.unchecked")
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

    private func accent(item: ReminderItemSnapshot, layout: LayoutMetrics, now: Date) -> some View {
        RoundedRectangle(cornerRadius: layout.accentWidth / 2, style: .continuous)
            .fill(Color(nsColor: accentColor(for: item, now: now)).opacity(0.96))
            .frame(width: layout.accentWidth)
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

    private var backgroundTintColor: NSColor {
        let tint = reminders.snapshot?.primaryItem.map { accentColor(for: $0, now: Date()) } ?? .systemYellow

        return NSColor.windowBackgroundColor.blended(withFraction: 0.18, of: tint) ?? .windowBackgroundColor
    }

    private var emptyTitle: String {
        if reminders.isLoading {
            return "Loading Reminders"
        }

        if reminders.lastErrorDescription != nil {
            return "Reminders Unavailable"
        }

        return "All Clear"
    }

    private var emptyDetail: String? {
        if let lastErrorDescription = reminders.lastErrorDescription {
            return lastErrorDescription
        }

        return "No incomplete reminders right now."
    }

    private func nextUpBadgeText(for item: ReminderItemSnapshot, now: Date) -> String {
        switch item.timingCategory(relativeTo: now) {
        case .overdue:
            return "OVERDUE"
        case .today, .upcoming:
            if let dueDate = item.dueDate {
                return compactDueLabel(for: item, dueDate: dueDate, now: now)
            }
            return "TO DO"
        case .unscheduled:
            return "TO DO"
        }
    }

    private func reminderDetailLine(for item: ReminderItemSnapshot, now: Date) -> String {
        let dueLine = detailedDueLine(for: item, now: now)
        guard !item.listTitle.isEmpty else {
            return dueLine
        }

        switch item.timingCategory(relativeTo: now) {
        case .unscheduled:
            return item.listTitle
        default:
            return "\(dueLine) • \(item.listTitle)"
        }
    }

    private func detailedDueLine(for item: ReminderItemSnapshot, now: Date) -> String {
        guard let dueDate = item.dueDate else {
            return "No due date"
        }

        switch item.timingCategory(relativeTo: now) {
        case .overdue:
            return item.hasDueTime && Calendar.autoupdatingCurrent.isDate(dueDate, inSameDayAs: now)
                ? "Overdue • \(timeFormatter.string(from: dueDate))"
                : "Overdue • \(dayLabel(for: item, dueDate: dueDate, now: now))"
        case .today:
            return item.hasDueTime ? timeFormatter.string(from: dueDate) : "Today"
        case .upcoming:
            return dayLabel(for: item, dueDate: dueDate, now: now)
        case .unscheduled:
            return "No due date"
        }
    }

    private func compactDueLabel(for item: ReminderItemSnapshot, dueDate: Date, now: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent

        if item.hasDueTime && calendar.isDate(dueDate, inSameDayAs: now) {
            return timeFormatter.string(from: dueDate).uppercased()
        }

        if calendar.isDateInToday(dueDate) {
            return "TODAY"
        }

        if calendar.isDateInTomorrow(dueDate) {
            return "TOM"
        }

        return compactDayFormatter.string(from: dueDate).uppercased()
    }

    private func dayLabel(for item: ReminderItemSnapshot, dueDate: Date, now: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent

        if calendar.isDateInToday(dueDate) {
            return item.hasDueTime ? timeFormatter.string(from: dueDate) : "Today"
        }

        if calendar.isDateInTomorrow(dueDate) {
            return item.hasDueTime ? "Tomorrow \(timeFormatter.string(from: dueDate))" : "Tomorrow"
        }

        if calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dueDate)).day ?? 0 < 7 {
            return item.hasDueTime
                ? "\(weekdayFormatter.string(from: dueDate)) \(timeFormatter.string(from: dueDate))"
                : weekdayFormatter.string(from: dueDate)
        }

        return item.hasDueTime
            ? shortDateTimeFormatter.string(from: dueDate)
            : shortDateFormatter.string(from: dueDate)
    }

    private func accentColor(for snapshot: RemindersSnapshot, now: Date) -> NSColor {
        guard let primaryItem = snapshot.primaryItem else {
            return .systemYellow
        }

        return accentColor(for: primaryItem, now: now)
    }

    private func accentColor(for item: ReminderItemSnapshot, now: Date) -> NSColor {
        switch item.timingCategory(relativeTo: now) {
        case .overdue:
            .systemRed
        case .today:
            .systemOrange
        case .upcoming:
            .systemYellow
        case .unscheduled:
            .secondaryLabelColor
        }
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }

    private var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }

    private var shortDateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d j:mm")
        return formatter
    }

    private var weekdayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }

    private var compactDayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE")
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
