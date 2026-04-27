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
            isLoading = false
            lastErrorDescription = "Calendar read access is needed to show upcoming events."
        case .notDetermined:
            requestAccessAndRefresh()
        case .denied, .restricted:
            nextEvent = nil
            isLoading = false
            lastErrorDescription = "Enable Calendar access in Settings to show upcoming events."
        @unknown default:
            nextEvent = nil
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
        let searchEnd = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 30, to: now) ?? now.addingTimeInterval(2_592_000)
        let predicate = eventStore.predicateForEvents(withStart: now, end: searchEnd, calendars: nil)
        let upcomingEvents = eventStore.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.startDate < $1.startDate
            }

        let nextEvent = upcomingEvents.first(where: { !$0.isAllDay }) ?? upcomingEvents.first

        self.nextEvent = nextEvent.map(CalendarEventSnapshot.init(event:))
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
}

struct CalendarEventSnapshot: Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String
    let calendarTitle: String
    let color: NSColor
    let quickJoinURL: URL?

    nonisolated init(event: EKEvent) {
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
