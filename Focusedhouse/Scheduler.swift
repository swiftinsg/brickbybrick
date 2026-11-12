import Foundation

/// The student's routine, as minutes since midnight. School runs Mon–Fri.
struct Routine: Sendable {
    var wake = 7 * 60
    var bed = 22 * 60
    var schoolStart = 8 * 60
    var schoolEnd = 15 * 60
    var hasSchool = true

    static var current: Routine {
        let d = UserDefaults.standard
        var r = Routine()
        if d.object(forKey: "wake") != nil { r.wake = d.integer(forKey: "wake") }
        if d.object(forKey: "bed") != nil { r.bed = d.integer(forKey: "bed") }
        if d.object(forKey: "schoolStart") != nil { r.schoolStart = d.integer(forKey: "schoolStart") }
        if d.object(forKey: "schoolEnd") != nil { r.schoolEnd = d.integer(forKey: "schoolEnd") }
        if d.object(forKey: "hasSchool") != nil { r.hasSchool = d.bool(forKey: "hasSchool") }
        return r
    }

    /// Free time on `day`: wake → bed, minus school hours on weekdays.
    func windows(on day: Date, calendar: Calendar) -> [Range<Date>] {
        let bedEnd = bed <= wake ? bed + 24 * 60 : bed   // bedtime after midnight
        var spans = [(wake, bedEnd)]
        let weekday = calendar.component(.weekday, from: day)   // 1 = Sunday
        if hasSchool, (2...6).contains(weekday), schoolStart < schoolEnd {
            spans = [(wake, min(schoolStart, bedEnd)), (max(schoolEnd, wake), bedEnd)]
        }
        let midnight = calendar.startOfDay(for: day)
        return spans.filter { $0.0 < $0.1 }.compactMap { a, b in
            guard let s = calendar.date(byAdding: .minute, value: a, to: midnight),
                  let e = calendar.date(byAdding: .minute, value: b, to: midnight) else { return nil }
            return s..<e
        }
    }
}

enum Scheduler {
    /// Places tasks back-to-back, in order, inside the routine's free windows.
    /// `day` (1-based) is the earliest plan day a task may start on.
    /// A task that doesn't fit before bedtime moves to the next free window.
    /// `busy` (calendar events) is never scheduled over.
    /// `notBefore[i]` (a timeline drag) is the earliest task `i` may start; it can
    /// still be pushed later if earlier tasks run over.
    static func schedule(_ tasks: [(minutes: Int, day: Int)], from start: Date,
                         routine: Routine, busy: [Range<Date>] = [], notBefore: [Date?] = [],
                         calendar: Calendar = .current) -> [Date] {
        let firstDay = calendar.startOfDay(for: start)
        var cursor = start
        return tasks.enumerated().map { i, task in
            let length = TimeInterval(max(task.minutes, 1) * 60)
            if let dayStart = calendar.date(byAdding: .day, value: max(task.day, 1) - 1, to: firstDay) {
                cursor = max(cursor, dayStart)
            }
            if i < notBefore.count, let earliest = notBefore[i] { cursor = max(cursor, earliest) }
            let slot = firstFit(after: cursor, length: length, routine: routine, busy: busy, calendar: calendar)
            cursor = slot + length
            return slot
        }
    }

    private static func firstFit(after cursor: Date, length: TimeInterval, routine: Routine,
                                 busy: [Range<Date>], calendar: Calendar) -> Date {
        // Start a day early so a window running past midnight (late bedtime) is seen.
        var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: cursor)) ?? cursor
        for _ in 0..<60 {
            for w in routine.windows(on: day, calendar: calendar).flatMap({ free($0, minus: busy) }) {
                let s = max(w.lowerBound, cursor)
                if s.addingTimeInterval(length) <= w.upperBound { return s }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return cursor   // longer than any free window: place it anyway
    }

    /// The parts of `window` not covered by any busy range.
    static func free(_ window: Range<Date>, minus busy: [Range<Date>]) -> [Range<Date>] {
        var pieces: [Range<Date>] = []
        var from = window.lowerBound
        for b in busy.sorted(by: { $0.lowerBound < $1.lowerBound }) where b.overlaps(window) {
            if b.lowerBound > from { pieces.append(from..<b.lowerBound) }
            from = max(from, b.upperBound)
        }
        if from < window.upperBound { pieces.append(from..<window.upperBound) }
        return pieces
    }
}
