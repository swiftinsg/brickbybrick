import EventKit

/// Reads busy time from, and writes plan tasks to, the iPhone Calendar
/// (which includes Google calendars synced through iOS).
@MainActor enum CalendarSync {
    static let store = EKEventStore()

    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Asks once; later calls return the saved answer without a prompt.
    @discardableResult static func requestAccess() async -> Bool {
        if hasAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Timed events that block time, skipping all-day events, "free" events
    /// and the events this plan wrote itself.
    static func busy(from start: Date, days: Int, excluding own: Set<String>) -> [Range<Date>] {
        guard hasAccess else { return [] }
        let from = start.addingTimeInterval(-86_400)
        let to = start.addingTimeInterval(TimeInterval(max(days, 1) + 60) * 86_400)
        return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
            .filter { !$0.isAllDay && $0.availability != .free && !own.contains($0.eventIdentifier ?? "") }
            .compactMap { $0.startDate < $0.endDate ? $0.startDate..<$0.endDate : nil }
    }

    /// Timed events the student attends between `from` and `to` (not "free" ones,
    /// not the ones focushouse wrote for tasks), for stress on Home.
    static func attended(from: Date, to: Date, excluding own: Set<String>) -> [(title: String, start: Date, minutes: Int)] {
        guard hasAccess else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
            .filter { !$0.isAllDay && $0.availability != .free && !own.contains($0.eventIdentifier ?? "") }
            .map { ($0.title ?? "", $0.startDate, Int($0.endDate.timeIntervalSince($0.startDate) / 60)) }
    }

    /// Creates or updates one event per scheduled task. Returns how many were written.
    static func add(_ plan: Plan) async throws -> Int {
        guard await requestAccess() else { throw CalendarError.noAccess }
        guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarError.noCalendar }
        var count = 0
        for task in plan.ordered {
            guard let start = task.start, let end = task.end else { continue }
            let event = task.eventID.flatMap(store.event(withIdentifier:)) ?? EKEvent(eventStore: store)
            if event.calendar == nil { event.calendar = calendar }
            event.title = task.title
            event.startDate = start
            event.endDate = end
            event.notes = "From focushouse · \(plan.title)"
            try store.save(event, span: .thisEvent, commit: false)
            task.eventID = event.eventIdentifier
            count += 1
        }
        try store.commit()
        return count
    }

    /// True when every scheduled task already has a matching Calendar event,
    /// so "Update Calendar" would change nothing.
    static func isUpToDate(_ plan: Plan) -> Bool {
        guard hasAccess else { return false }
        return plan.tasks.allSatisfy { t in
            guard let start = t.start, let end = t.end else { return true }
            guard let event = t.eventID.flatMap(store.event(withIdentifier:)) else { return false }
            return event.startDate == start && event.endDate == end && event.title == t.title
        }
    }

    /// Removes the Calendar events of tasks that are being deleted.
    static func remove(_ tasks: [PlanTask]) {
        guard hasAccess else { return }
        for id in tasks.compactMap(\.eventID) {
            if let event = store.event(withIdentifier: id) {
                try? store.remove(event, span: .thisEvent, commit: false)
            }
        }
        try? store.commit()
    }
}

enum CalendarError: LocalizedError {
    case noAccess, noCalendar
    var errorDescription: String? {
        switch self {
        case .noAccess: "focushouse needs Calendar access. Turn it on in Settings → Apps → focushouse."
        case .noCalendar: "There's no calendar to add events to."
        }
    }
}
