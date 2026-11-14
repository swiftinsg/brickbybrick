import Foundation
import Testing
@testable import focushouse

struct MonthGridTests {
    func cal(firstWeekday: Int) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = firstWeekday
        return c
    }

    @Test func novemberStartsOnSunday() {
        // 1 Nov 2026 is a Sunday.
        let c = cal(firstWeekday: 1)
        let days = MonthGrid.days(in: c.date(from: DateComponents(year: 2026, month: 11, day: 20))!, calendar: c)
        #expect(days.count == 30)
        #expect(days.first! == c.date(from: DateComponents(year: 2026, month: 11, day: 1)))
    }

    @Test func mondayFirstWeekPadsSix() {
        let c = cal(firstWeekday: 2)
        let days = MonthGrid.days(in: c.date(from: DateComponents(year: 2026, month: 11, day: 1))!, calendar: c)
        #expect(days.prefix(6).allSatisfy { $0 == nil })
        #expect(days[6] == c.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        #expect(MonthGrid.weekdaySymbols(c).first == "M")
    }

    @Test func februaryLeapYear() {
        let c = cal(firstWeekday: 1)
        let days = MonthGrid.days(in: c.date(from: DateComponents(year: 2028, month: 2, day: 10))!, calendar: c)
        #expect(days.compactMap { $0 }.count == 29)
    }

    @Test func ringFillsWithCount() {
        #expect(MonthGrid.fill(0, full: 6) == 0)
        #expect(MonthGrid.fill(1, full: 6) < 0.01)   // a dot
        #expect(MonthGrid.fill(3, full: 6) == 0.5)
        #expect(MonthGrid.fill(9, full: 6) == 1)
    }
}
