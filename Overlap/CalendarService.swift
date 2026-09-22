import Foundation
import SwiftUI
import EventKit

struct BusyBlock: Equatable {
    let start: Date
    let end: Date
    let title: String
    let calendarColor: Color?
}

/// Calendar access + busy-event cache for the home row's strip.
@Observable
final class CalendarService {
    @ObservationIgnored @AppStorage("overlap.calendar.enabled") var enabled = false
    private(set) var authorization: EKAuthorizationStatus
    private(set) var busy: [BusyBlock] = []

    private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?

    private var currentDate: Date = Date()
    private var currentTZ: TimeZone = .current

    init() {
        authorization = EKEventStore.authorizationStatus(for: .event)
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.refresh() }
            }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    @MainActor
    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorization = granted ? .fullAccess : .denied
        } catch {
            authorization = .denied
        }
        refresh()
    }

    /// Re-fetch busy blocks for `date`'s home-tz day (skips all-day events,
    /// `.free` availability, and events the user declined).
    func refresh(for date: Date? = nil, homeTZ: TimeZone? = nil) {
        if let date { currentDate = date }
        if let homeTZ { currentTZ = homeTZ }
        guard enabled else { busy = []; return }
        guard authorization == .fullAccess else { busy = []; return }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = currentTZ
        let start = cal.startOfDay(for: currentDate)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        busy = store.events(matching: predicate).compactMap { event in
            guard !event.isAllDay, event.availability != .free else { return nil }
            if let me = event.attendees?.first(where: { $0.isCurrentUser }),
               me.participantStatus == .declined { return nil }
            let color = event.calendar?.cgColor.map { Color(cgColor: $0) }
            return BusyBlock(start: event.startDate, end: event.endDate,
                             title: event.title ?? "Busy", calendarColor: color)
        }
    }

    /// True once the user has granted access (requests if undetermined).
    @MainActor
    func ensureAccess() async -> Bool {
        switch authorization {
        case .fullAccess:
            return true
        case .notDetermined:
            await requestAccess()
            return authorization == .fullAccess
        default:
            return false
        }
    }

    /// Save a new event in the default calendar.
    func createEvent(title: String, start: Date, end: Date, notes: String) throws {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
    }

    /// Home-hour columns where a busy block overlaps ≥ 15 minutes.
    func busyHomeHours(for date: Date, homeTZ: TimeZone) -> Set<Int> {
        var hours = Set<Int>()
        for h in 0..<24 {
            let hStart = TimeMath.instant(homeHour: h, on: date, home: homeTZ)
            let hEnd = hStart.addingTimeInterval(3600)
            for b in busy {
                let overlap = min(b.end, hEnd).timeIntervalSince(max(b.start, hStart))
                if overlap >= 15 * 60 { hours.insert(h); break }
            }
        }
        return hours
    }
}
