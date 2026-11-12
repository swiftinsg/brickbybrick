import Foundation
import Testing
@testable import brickbybrick

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
}
