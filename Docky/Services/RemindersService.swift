//
//  RemindersService.swift
//  Docky
//

import Combine
import EventKit
import Foundation

final class RemindersService: ObservableObject {
    static let shared = RemindersService()

    @Published private(set) var snapshot: RemindersSnapshot?
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorDescription: String?

    private let eventStore = EKEventStore()
    private var lastRefreshDate: Date?
    private var pendingRefreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)

        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: eventStore)
            .sink { [weak self] _ in
                self?.refresh(force: true)
            }
            .store(in: &cancellables)
    }

    deinit {
        pendingRefreshTask?.cancel()
    }

    func ensureFreshReminders() {
        refresh(force: false)
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    /// Docky's tri-state view of reminders access. `.writeOnly` counts as
    /// not-granted because the widget needs read access to show tasks.
    var permissionStatus: PermissionStatus {
        switch authorizationStatus {
        case .fullAccess, .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func refresh(force: Bool) {
        if !force,
           let lastRefreshDate,
           Date().timeIntervalSince(lastRefreshDate) < 300 {
            return
        }

        refreshAuthorizationStatus()
        lastErrorDescription = nil

        switch authorizationStatus {
        case .fullAccess, .authorized:
            loadReminders()
        case .writeOnly:
            snapshot = nil
            isLoading = false
            lastErrorDescription = "Reminders read access is needed to show your open tasks."
        case .notDetermined:
            // Permission is requested lazily from the widget's Enable button,
            // never automatically on render. Leave the widget in its
            // call-to-action state until the user opts in.
            snapshot = nil
            isLoading = false
        case .denied, .restricted:
            snapshot = nil
            isLoading = false
            lastErrorDescription = "Enable Reminders access in Settings to show your open tasks."
        @unknown default:
            snapshot = nil
            isLoading = false
            lastErrorDescription = "Reminders are unavailable right now."
        }
    }

    func completeReminder(identifier: String) async -> Bool {
        #if DEBUG
        if completeDummyReminder(identifier: identifier) {
            return true
        }
        #endif

        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return false
        }

        reminder.isCompleted = true
        reminder.completionDate = Date()

        do {
            try eventStore.save(reminder, commit: true)
            refresh(force: true)
            return true
        } catch {
            lastErrorDescription = "Couldn’t update reminder."
            return false
        }
    }

    /// Requests reminders access in response to an explicit user action
    /// (the widget's Enable button). Loads reminders immediately on grant.
    func requestAccess() async -> Bool {
        let granted = await requestRemindersPermission()
        if granted {
            loadReminders()
        }
        return granted
    }

    private func requestRemindersPermission() async -> Bool {
        refreshAuthorizationStatus()

        switch authorizationStatus {
        case .fullAccess, .authorized:
            return true
        case .writeOnly, .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToReminders { [weak self] granted, _ in
                    guard let self else {
                        continuation.resume(returning: granted)
                        return
                    }

                    Task { @MainActor in
                        self.refreshAuthorizationStatus()
                        continuation.resume(returning: granted)
                    }
                }
            }
        @unknown default:
            return false
        }
    }

    private func loadReminders() {
        pendingRefreshTask?.cancel()
        isLoading = true

        pendingRefreshTask = Task { [weak self] in
            guard let self else { return }

            let now = Date()
            let reminders = await self.fetchCandidateReminders(now: now)
            guard !Task.isCancelled else { return }

            self.snapshot = Self.makeSnapshot(from: reminders, now: now)
            self.lastRefreshDate = now
            self.isLoading = false
            self.lastErrorDescription = nil
            self.pendingRefreshTask = nil
        }
    }

    private func fetchCandidateReminders(now: Date) async -> [EKReminder] {
        let searchEnd = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 14, to: now)
            ?? now.addingTimeInterval(1_209_600)
        let scheduledPredicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: searchEnd,
            calendars: nil
        )
        let scheduledReminders = await fetchReminders(matching: scheduledPredicate)
        if !scheduledReminders.isEmpty {
            return scheduledReminders
        }

        let allPredicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        return await fetchReminders(matching: allPredicate)
    }

    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private static func makeSnapshot(from reminders: [EKReminder], now: Date) -> RemindersSnapshot {
        let items = reminders
            .map(ReminderItemSnapshot.init(reminder:))
            .sorted { lhs, rhs in
                comesBefore(lhs, rhs, now: now)
            }

        return makeSnapshot(from: items, now: now)
    }

    private static func makeSnapshot(from items: [ReminderItemSnapshot], now: Date) -> RemindersSnapshot {
        let sortedItems = items.sorted { lhs, rhs in
            comesBefore(lhs, rhs, now: now)
        }

        var overdueCount = 0
        var dueTodayCount = 0
        var upcomingCount = 0
        var unscheduledCount = 0

        for item in sortedItems {
            switch item.timingCategory(relativeTo: now) {
            case .overdue:
                overdueCount += 1
            case .today:
                dueTodayCount += 1
            case .upcoming:
                upcomingCount += 1
            case .unscheduled:
                unscheduledCount += 1
            }
        }

        return RemindersSnapshot(
            items: sortedItems,
            overdueCount: overdueCount,
            dueTodayCount: dueTodayCount,
            upcomingCount: upcomingCount,
            unscheduledCount: unscheduledCount
        )
    }

    #if DEBUG
    func seedDummyDebugSnapshot() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil

        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let items = [
            ReminderItemSnapshot(
                identifier: "\(Self.debugReminderIdentifierPrefix)1",
                title: "Send the demo cut to the team",
                dueDate: calendar.date(byAdding: .minute, value: -45, to: now),
                hasDueTime: true,
                listTitle: "Work",
                priority: 1
            ),
            ReminderItemSnapshot(
                identifier: "\(Self.debugReminderIdentifierPrefix)2",
                title: "Finalize voiceover notes",
                dueDate: calendar.date(byAdding: .minute, value: 90, to: now),
                hasDueTime: true,
                listTitle: "Production",
                priority: 5
            ),
            ReminderItemSnapshot(
                identifier: "\(Self.debugReminderIdentifierPrefix)3",
                title: "Book customer teaser post",
                dueDate: calendar.date(byAdding: .day, value: 1, to: now),
                hasDueTime: false,
                listTitle: "Launch",
                priority: 0
            )
        ]

        snapshot = Self.makeSnapshot(from: items, now: now)
        lastRefreshDate = now
        isLoading = false
        lastErrorDescription = nil
    }

    private func completeDummyReminder(identifier: String) -> Bool {
        guard identifier.hasPrefix(Self.debugReminderIdentifierPrefix),
              let snapshot,
              snapshot.items.contains(where: { $0.identifier == identifier }) else {
            return false
        }

        self.snapshot = Self.makeSnapshot(
            from: snapshot.items.filter { $0.identifier != identifier },
            now: Date()
        )
        lastRefreshDate = Date()
        isLoading = false
        lastErrorDescription = nil
        return true
    }

    private static let debugReminderIdentifierPrefix = "debug-reminder-"
    #endif

    private static func comesBefore(
        _ lhs: ReminderItemSnapshot,
        _ rhs: ReminderItemSnapshot,
        now: Date
    ) -> Bool {
        let calendar = Calendar.autoupdatingCurrent
        let lhsCategory = lhs.timingCategory(relativeTo: now, calendar: calendar)
        let rhsCategory = rhs.timingCategory(relativeTo: now, calendar: calendar)
        if lhsCategory != rhsCategory {
            return lhsCategory.rawValue < rhsCategory.rawValue
        }

        switch (lhs.dueDate, rhs.dueDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate < rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        let lhsPriority = lhs.prioritySortRank
        let rhsPriority = rhs.prioritySortRank
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        if lhs.listTitle != rhs.listTitle {
            return lhs.listTitle.localizedCaseInsensitiveCompare(rhs.listTitle) == .orderedAscending
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

struct RemindersSnapshot: Equatable {
    let items: [ReminderItemSnapshot]
    let overdueCount: Int
    let dueTodayCount: Int
    let upcomingCount: Int
    let unscheduledCount: Int

    var totalCount: Int {
        items.count
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    var primaryItem: ReminderItemSnapshot? {
        items.first
    }

    var displayItems: [ReminderItemSnapshot] {
        Array(items.prefix(3))
    }

    var completionCandidates: [ReminderItemSnapshot] {
        Array(items.prefix(5))
    }
}

struct ReminderItemSnapshot: Identifiable, Equatable {
    let identifier: String
    let title: String
    let dueDate: Date?
    let hasDueTime: Bool
    let listTitle: String
    let priority: Int

    var id: String {
        identifier
    }

    fileprivate var prioritySortRank: Int {
        switch priority {
        case 1 ... 4:
            0
        case 5:
            1
        case 6 ... 9:
            2
        default:
            3
        }
    }

    nonisolated init(reminder: EKReminder) {
        let trimmedTitle = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let dueDateComponents = reminder.dueDateComponents

        identifier = reminder.calendarItemIdentifier
        title = trimmedTitle.isEmpty ? "Untitled Reminder" : trimmedTitle
        dueDate = dueDateComponents?.date
        hasDueTime = dueDateComponents?.hour != nil || dueDateComponents?.minute != nil
        listTitle = reminder.calendar.title
        priority = reminder.priority
    }

    #if DEBUG
    init(
        identifier: String,
        title: String,
        dueDate: Date?,
        hasDueTime: Bool,
        listTitle: String,
        priority: Int
    ) {
        self.identifier = identifier
        self.title = title
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.listTitle = listTitle
        self.priority = priority
    }
    #endif

    func timingCategory(
        relativeTo now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ReminderTimingCategory {
        guard let dueDate else {
            return .unscheduled
        }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDueDay = calendar.startOfDay(for: dueDate)

        if startOfDueDay < startOfToday {
            return .overdue
        }

        if startOfDueDay == startOfToday {
            return hasDueTime && dueDate < now ? .overdue : .today
        }

        return dueDate < now ? .overdue : .upcoming
    }
}

enum ReminderTimingCategory: Int {
    case overdue = 0
    case today = 1
    case upcoming = 2
    case unscheduled = 3
}
