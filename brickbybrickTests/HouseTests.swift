import Foundation
import Testing
@testable import brickbybrick

struct HouseTests {
    let cal = Calendar.current
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 18))!
    func daysAgo(_ n: Int, hour: Int = 16) -> Date {
        cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -n, to: now)!)!
    }

    @Test func streakCountsStressfulDaysInARow() {
        let load = [(daysAgo(0), 120), (daysAgo(1), 60), (daysAgo(1), 60), (daysAgo(2), 150), (daysAgo(4), 300)]
        #expect(House.streak(load, now: now) == 3)   // day 3 is light, so day 4 doesn't count
    }

    @Test func streakSurvivesALightMorning() {
        #expect(House.streak([(daysAgo(1), 200), (daysAgo(2), 200), (daysAgo(0), 30)], now: now) == 2)
        #expect(House.streak([(daysAgo(0), 30)], now: now) == 0)
    }

    @Test func damageStepsAndRestRepairs() {
        #expect(House.state(streak: 1, restedDays: 0, restedToday: false) == .calm)
        #expect(House.state(streak: 2, restedDays: 0, restedToday: false) == .stressed)
        #expect(House.state(streak: 9, restedDays: 0, restedToday: false) == .crumbling)
        #expect(House.state(streak: 6, restedDays: 1, restedToday: false) == .overloaded)
        #expect(House.state(streak: 6, restedDays: 1, restedToday: true) == .resting)
        #expect(House.state(streak: 0, restedDays: 0, restedToday: true) == .calm)   // nothing to repair
        #expect(House.state(streak: 2, restedDays: 3, restedToday: false) == .calm)
    }

    @Test func stressWeightsEffortAndHalvesCompulsory() {
        #expect(House.stress(minutes: 60, Rating(score: 2)) == 0)
        #expect(House.stress(minutes: 60, Rating(score: 5)) == 30)
        #expect(House.stress(minutes: 120, Rating(score: 10)) == 180)
        #expect(House.stress(minutes: 120, Rating(score: 10, compulsory: true)) == 90)   // exam
        #expect(Rating(priority: 0).effort == .hard && Rating(priority: 2).effort == .easy)
    }

    @Test func scoreRangesAndPersonalPace() {
        #expect([1, 3, 4, 6, 7, 8, 9, 10].map { Rating(score: $0).effort }
                == [.easy, .easy, .normal, .normal, .hard, .hard, .intense, .intense])
        #expect(Rating(score: 5).personal(1.5).effort == .hard)     // takes this student 1.5× longer
        #expect(Rating(score: 5).personal(0.6).effort == .easy)     // they're quick at it
        #expect(Rating(score: 9).personal(2).score == 10)           // capped
    }

    @Test func bricksFromEstimateByEffortAndDailyCap() {
        #expect(House.bricks(minutes: 45, .normal) == 4)
        #expect(House.bricks(minutes: 40, .hard) == 6)
        #expect(House.bricks(minutes: 40, .intense) == 8)
        #expect(House.bricks(minutes: 5, .normal) == 1)
        #expect(House.bricks(minutes: 90, .easy) == 0)
        let earned = Array(repeating: (daysAgo(0), 30), count: 5) + [(daysAgo(1), 7)]
        #expect(House.total(earned) == 107)   // today's 150 capped at 100
    }

    @Test func restCountsWakingHoursOnlyAndIgnoresShortBreaks() {
        var r = Routine()
        r.wake = 7 * 60
        r.bed = 22 * 60
        var log = RestLog()
        log.add(from: daysAgo(0, hour: 13), to: daysAgo(0, hour: 13).addingTimeInterval(5 * 60), routine: r)
        #expect(log.seconds(on: now) == 0)   // 5 min isn't rest
        log.add(from: daysAgo(1, hour: 20), to: daysAgo(0, hour: 9), routine: r)   // overnight
        #expect(log.seconds(on: daysAgo(1)) == 2 * 3600)   // 8 PM–10 PM
        #expect(log.seconds(on: now) == 2 * 3600)          // 7 AM–9 AM, sleep skipped
        #expect(RestLog.load(log.data) == log)
    }

    @Test func restHoursAreHourlyBlocksCappedAtTwenty() {
        let b = RestHours.blocks(wake: 7 * 60, bed: 22 * 60)
        #expect(b.count == 15 && b.first?.start == 420 && b.last?.end == 1320)
        #expect(RestHours.blocks(wake: 6 * 60, bed: 2 * 60).count == 20)   // bedtime after midnight
    }

    @Test func shopNeedsLevelOneAndEnoughBricks() {
        let desk = Furniture(name: "Desk", tag: "Work", description: "", hobby: "desk", level: 1, cost: 40, grid: [])
        let deluxe = Furniture(name: "Deluxe", tag: "Work", description: "", hobby: "desk", level: 2, cost: 120, grid: [])
        let all = [desk, deluxe]
        #expect(Shop.state(desk, owned: [], balance: 39, in: all) == .short(1))
        #expect(Shop.state(desk, owned: [], balance: 40, in: all) == .buy)
        #expect(Shop.state(deluxe, owned: [], balance: 500, in: all) == .needs("Desk"))
        #expect(Shop.state(deluxe, owned: ["Desk"], balance: 120, in: all) == .buy)
        #expect(Shop.state(desk, owned: ["Desk"], balance: 0, in: all) == .owned)
        #expect(Shop.spent(["Desk", "Deluxe"], in: all) == 160)
        #expect(Shop.items.count == 34)   // both JSON files bundled
    }
}
