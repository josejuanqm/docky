//
//  CalendarService.swift
//  Docky
//

import AppKit
import Combine
import EventKit
import Foundation

final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var nextEvent: CalendarEventSnapshot?
    @Published private(set) var upcomingEvents: [CalendarEventSnapshot] = []
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorDescription: String?

    private let eventStore = EKEventStore()
    private var lastRefreshDate: Date?
    private var cancellables = Set<AnyCancellable>()
    private var rolloverTimer: Timer?

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)

        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: eventStore)
            .sink { [weak self] _ in
                self?.refresh(force: true)
            }
            .store(in: &cancellables)
    }

    func ensureFreshEvent() {
        refresh(force: false)
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
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
            loadNextEvent()
        case .writeOnly:
            nextEvent = nil
            upcomingEvents = []
            isLoading = false
            lastErrorDescription = "Calendar read access is needed to show upcoming events."
        case .notDetermined:
            requestAccessAndRefresh()
        case .denied, .restricted:
            nextEvent = nil
            upcomingEvents = []
            isLoading = false
            lastErrorDescription = "Enable Calendar access in Settings to show upcoming events."
        @unknown default:
            nextEvent = nil
            upcomingEvents = []
            isLoading = false
            lastErrorDescription = "Calendar is unavailable right now."
        }
    }

    private func requestAccessAndRefresh() {
        guard !isLoading else {
            return
        }

        isLoading = true

        Task { [weak self] in
            guard let self else { return }

            let granted = await self.requestCalendarPermission()
            guard granted else {
                self.nextEvent = nil
                self.upcomingEvents = []
                self.isLoading = false
                self.lastErrorDescription = "Enable Calendar access in Settings to show upcoming events."
                return
            }

            self.loadNextEvent()
        }
    }

    private func requestCalendarPermission() async -> Bool {
        refreshAuthorizationStatus()

        switch authorizationStatus {
        case .fullAccess, .authorized:
            return true
        case .writeOnly, .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToEvents { [weak self] granted, _ in
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

    private func loadNextEvent() {
        isLoading = true

        let now = Date()
        let calendarRef = Calendar.autoupdatingCurrent
        let searchEnd = calendarRef.date(byAdding: .day, value: 30, to: now) ?? now.addingTimeInterval(2_592_000)
        let predicate = eventStore.predicateForEvents(withStart: now, end: searchEnd, calendars: nil)
        let staleStartCutoff = now.addingTimeInterval(-15 * 60)
        let startOfToday = calendarRef.startOfDay(for: now)
        let upcomingEvents = eventStore.events(matching: predicate)
            .filter {
                guard $0.endDate > now, $0.startDate >= startOfToday else { return false }
                return $0.isAllDay || $0.startDate >= staleStartCutoff
            }
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.startDate < $1.startDate
            }

        let nextEvent = upcomingEvents.first(where: { !$0.isAllDay }) ?? upcomingEvents.first

        self.nextEvent = nextEvent.map(CalendarEventSnapshot.init(event:))
        self.upcomingEvents = upcomingEvents.prefix(8).map(CalendarEventSnapshot.init(event:))
        self.lastRefreshDate = now
        self.isLoading = false
        self.lastErrorDescription = nil
        scheduleRollover(after: nextEvent?.endDate)
    }

    private func scheduleRollover(after endDate: Date?) {
        rolloverTimer?.invalidate()
        rolloverTimer = nil

        guard let endDate else { return }

        let fireDate = endDate.addingTimeInterval(1)
        if fireDate <= Date() {
            DispatchQueue.main.async { [weak self] in
                self?.refresh(force: true)
            }
            return
        }

        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            self?.refresh(force: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        rolloverTimer = timer
    }

    #if DEBUG
    func seedDummyDebugSnapshot() {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let startDate = calendar.date(byAdding: .minute, value: 18, to: now) ?? now.addingTimeInterval(1_080)
        let endDate = calendar.date(byAdding: .minute, value: 63, to: now) ?? now.addingTimeInterval(3_780)

        let next = CalendarEventSnapshot(
            title: "Docky demo review",
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            location: "Studio A",
            calendarTitle: "Work",
            color: NSColor.systemBlue,
            quickJoinURL: URL(string: "https://zoom.us/j/5551234567")
        )

        let dummyTwo = CalendarEventSnapshot(
            title: "Lunch with Priya",
            startDate: calendar.date(byAdding: .hour, value: 3, to: now) ?? now.addingTimeInterval(10_800),
            endDate: calendar.date(byAdding: .hour, value: 4, to: now) ?? now.addingTimeInterval(14_400),
            isAllDay: false,
            location: "Mission",
            calendarTitle: "Personal",
            color: NSColor.systemPink,
            quickJoinURL: nil
        )

        let dummyThree = CalendarEventSnapshot(
            title: "Sprint planning",
            startDate: calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400),
            endDate: calendar.date(byAdding: .day, value: 1, to: now)?.addingTimeInterval(3_600) ?? now.addingTimeInterval(90_000),
            isAllDay: false,
            location: "",
            calendarTitle: "Work",
            color: NSColor.systemBlue,
            quickJoinURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )

        let dummyFour = CalendarEventSnapshot(
            title: "Team offsite",
            startDate: calendar.date(byAdding: .day, value: 2, to: now) ?? now.addingTimeInterval(172_800),
            endDate: calendar.date(byAdding: .day, value: 2, to: now)?.addingTimeInterval(86_400) ?? now.addingTimeInterval(259_200),
            isAllDay: true,
            location: "Sausalito",
            calendarTitle: "Work",
            color: NSColor.systemOrange,
            quickJoinURL: nil
        )

        nextEvent = next
        upcomingEvents = [next, dummyTwo, dummyThree, dummyFour]
        lastRefreshDate = now
        isLoading = false
        lastErrorDescription = nil
        scheduleRollover(after: endDate)
    }
    #endif
}

struct CalendarEventSnapshot: Equatable {
    let eventIdentifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String
    let calendarTitle: String
    let color: NSColor
    let quickJoinURL: URL?

    nonisolated init(event: EKEvent) {
        eventIdentifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let trimmedTitle = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = trimmedTitle.isEmpty ? "Untitled Event" : trimmedTitle
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        calendarTitle = event.calendar.title
        color = NSColor(cgColor: event.calendar.cgColor) ?? .white
        quickJoinURL = Self.resolveQuickJoinURL(for: event, location: location)
    }

    #if DEBUG
    init(
        eventIdentifier: String = UUID().uuidString,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        location: String,
        calendarTitle: String,
        color: NSColor,
        quickJoinURL: URL?
    ) {
        self.eventIdentifier = eventIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.calendarTitle = calendarTitle
        self.color = color
        self.quickJoinURL = quickJoinURL
    }
    #endif

    private nonisolated static func resolveQuickJoinURL(for event: EKEvent, location: String) -> URL? {
        if let directURL = normalizedJoinURL(event.url) {
            return directURL
        }

        if let notes = event.notes,
           let notesURL = firstJoinURL(in: notes) {
            return notesURL
        }

        if let locationURL = firstJoinURL(in: location) {
            return locationURL
        }

        return nil
    }

    private nonisolated static func firstJoinURL(in text: String) -> URL? {
        guard !text.isEmpty else {
            return nil
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []

        for match in matches {
            guard let range = Range(match.range, in: text) else {
                continue
            }

            let candidate = String(text[range])
            if let url = normalizedJoinURL(URL(string: candidate)) {
                return url
            }
        }

        return nil
    }

    private nonisolated static func normalizedJoinURL(_ url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "zoommtg", "msteams", "webex", "facetime"].contains(scheme) else {
            return nil
        }

        return url
    }
}
