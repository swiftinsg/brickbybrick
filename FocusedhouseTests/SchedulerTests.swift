import Foundation
import Testing
@testable import Focusedhouse

struct SchedulerTests {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let routine = Routine()   // wake 7:00, bed 22:00, school 8:00–15:00 Mon–Fri

    func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        // November 2026: the 11th is a Wednesday, the 14th a Saturday.
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    @Test func backToBack() {
        let s = Scheduler.schedule([(30, 1), (45, 1)], from: at(14, 10), routine: routine, calendar: cal)
        #expect(s == [at(14, 10), at(14, 10, 30)])
    }

    @Test func skipsSchoolHours() {
        // Wednesday 7:30: 60 min doesn't fit before school at 8:00, so it waits until 15:00.
        let s = Scheduler.schedule([(60, 1)], from: at(11, 7, 30), routine: routine, calendar: cal)
        #expect(s == [at(11, 15)])
    }

    @Test func overflowsToNextMorning() {
        // Saturday 21:30: 60 min runs past bedtime, so it moves to Sunday 7:00.
        let s = Scheduler.schedule([(60, 1)], from: at(14, 21, 30), routine: routine, calendar: cal)
        #expect(s == [at(15, 7)])
    }

    @Test func goalDayPushesLater() {
        // Day 3 of a plan starting Saturday is Monday: before school at 7:00.
        let s = Scheduler.schedule([(30, 1), (30, 3)], from: at(14, 10), routine: routine, calendar: cal)
        #expect(s == [at(14, 10), at(16, 7)])
    }
}
