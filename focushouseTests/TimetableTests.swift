import Foundation
import Testing
@testable import focushouse

struct TimetableTests {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    func at(_ day: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!   // 11 Nov = Wed
    }
    func lesson(weekday: Int) -> Lesson { Lesson(subject: "Maths", weekday: weekday, start: 8 * 60 + 30, end: 9 * 60 + 30) }

    @Test func sameDayEvenIfLessonAlreadyStarted() {
        // Wednesday 10:00, Wednesday lesson: starts today (the weekly series includes today).
        #expect(Timetable.firstDate(of: lesson(weekday: 4), from: at(11, 10), calendar: cal) == at(11, 8, 30))
    }

    @Test func laterInWeekAndNextWeek() {
        #expect(Timetable.firstDate(of: lesson(weekday: 6), from: at(11, 10), calendar: cal) == at(13, 8, 30))   // Fri
        #expect(Timetable.firstDate(of: lesson(weekday: 2), from: at(11, 10), calendar: cal) == at(16, 8, 30))   // next Mon
    }

    @Test func weekAAndBAlternate() {
        var a = lesson(weekday: 6); a.week = .a   // Friday, Week A
        var b = lesson(weekday: 6); b.week = .b   // Friday, Week B
        var monA = lesson(weekday: 2); monA.week = .a
        let wed = at(11, 10)
        // This week is A: A's Friday is this Friday, B's is next Friday.
        #expect(Timetable.firstDate(of: a, from: wed, thisWeekIsA: true, calendar: cal) == at(13, 8, 30))
        #expect(Timetable.firstDate(of: b, from: wed, thisWeekIsA: true, calendar: cal) == at(20, 8, 30))
        // This week is B: swapped.
        #expect(Timetable.firstDate(of: a, from: wed, thisWeekIsA: false, calendar: cal) == at(20, 8, 30))
        // Monday has passed: next Monday is in Week B, so A's Monday is the one after.
        #expect(Timetable.firstDate(of: monA, from: wed, thisWeekIsA: true, calendar: cal) == at(23, 8, 30))
    }
}
