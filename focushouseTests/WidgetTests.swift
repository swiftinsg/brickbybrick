import Foundation
import Testing
@testable import focushouse

struct WidgetTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func at(_ min: Double) -> Date { t0.addingTimeInterval(min * 60) }

    var snap: WidgetSnapshot {
        var s = WidgetSnapshot()
        s.today = [.init(id: "a", title: "A", start: at(0), minutes: 30),
                   .init(id: "b", title: "B", start: at(30), minutes: 30),
                   .init(id: "c", title: "C", start: at(-60), minutes: 30, done: true)]
        return s
    }

    @Test func moreTimeShiftsLaterTasks() {
        var s = snap
        s.apply(.more, id: "a", at: at(10))
        #expect(s.today[0].minutes == 45)
        #expect(s.today[1].start == at(45))
        #expect(s.today[2].start == at(-60))   // done, earlier: untouched
    }

    @Test func breakStartsFifteenFromNow() {
        var s = snap
        s.apply(.rest, id: "a", at: at(10))   // mid-task: restarts after the break
        #expect(s.today[0].start == at(25))
        #expect(s.today[1].start == at(55))
    }

    @Test func nextAndCounts() {
        #expect(snap.next(at: at(10))?.id == "a")
        #expect(snap.next(at: at(40))?.id == "b")
        #expect(snap.doneCount == 1)
    }

    @Test func busyBlocksOverlappingRestOnly() {
        var s = WidgetSnapshot()
        s.busy = [DateInterval(start: at(60), duration: 1800)]
        #expect(s.blocksRest(from: at(30), to: at(90)))
        #expect(!s.blocksRest(from: at(0), to: at(60)))    // ends as the task starts
        #expect(!s.blocksRest(from: at(90), to: at(150)))  // starts as the task ends
    }

    @Test func restRepairsFromLog() {
        let cal = Calendar.current
        var log = RestLog()
        #expect(House.state(streak: 4, log: log, now: t0) == .overloaded)
        log.add(House.restGoal, on: t0, calendar: cal)
        #expect(House.state(streak: 4, log: log, now: t0) == .resting)
    }
}
