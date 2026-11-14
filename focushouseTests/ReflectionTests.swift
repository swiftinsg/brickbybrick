import Foundation
import SwiftData
import Testing
@testable import focushouse

@MainActor struct ReflectionTests {
    let cal = Calendar.current
    /// Saturday 14 Nov 2026 (no school) at h:m.
    func at(_ h: Int, _ m: Int = 0, day: Int = 14) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    func answered(_ category: String = "study", at start: Date, felt: Int, note: String = "", reflected: Date? = nil) -> PlanTask {
        let t = PlanTask(title: "T", category: category, minutes: 30, day: 1, order: 0)
        t.start = start
        t.feeling = felt
        t.note = note
        t.reflectedAt = reflected ?? start
        t.checkIn = PlanTask.CheckInState.answered.rawValue
        return t
    }

    @Test func bestTimeNeedsThreeAnswersAndAGap() {
        var h = (0..<3).map { _ in answered(at: at(15), felt: 4) } + (0..<3).map { _ in answered(at: at(21), felt: 2) }
        let t = Reflections.bestTime(h)
        #expect(t?.best == .afternoon && t?.worst == .night)
        #expect(Reflections.promptNote(h, now: at(22)).contains("put hard or high-effort items first"))
        h.removeLast()   // night has only 2 answers now
        #expect(Reflections.bestTime(h) == nil)
    }

    @Test func drainingCategoriesAndHardDay() {
        let h = (0..<3).map { _ in answered("writing", at: at(16), felt: 1) } + (0..<3).map { _ in answered("reading", at: at(16), felt: 4) }
        #expect(Reflections.draining(h) == ["writing"])
        #expect(Reflections.wasHardDay(h.prefix(3).map { $0 }, now: at(20)))
        #expect(!Reflections.wasHardDay(h, now: at(20)))                         // average 2.5
        #expect(!Reflections.wasHardDay(h.prefix(3).map { $0 }, now: at(20, day: 17)))   // too long ago
        #expect(Reflections.breakMinutes(h.prefix(3).map { $0 }, now: at(20)) == 10)
    }

    @Test func notesDeletedAfter30DaysFeelingsKept() {
        let old = answered(at: at(15), felt: 2, note: "tired after CCA")
        let new = answered(at: at(15), felt: 3, note: "ok", reflected: at(15, day: 30))
        Reflections.purgeNotes([old, new], now: at(16, day: 30).addingTimeInterval(16 * 86_400))
        #expect(old.note.isEmpty && old.feeling == 2)
        #expect(new.note == "ok")
    }

    @Test func bricksOnlyOnceAnswered() {
        let t = PlanTask(title: "Essay", category: "writing", minutes: 30, day: 1, order: 0)
        CheckIn.shared.tick(t)
        #expect(t.done && !t.earnsBricks)                    // waiting for an answer
        CheckIn.shared.save(t, minutes: 40, feeling: 3, note: " fine ")
        #expect(t.earnsBricks && t.note == "fine" && t.actual == 40)
        let s = PlanTask(title: "Maths", category: "homework", minutes: 30, day: 1, order: 0)
        CheckIn.shared.tick(s)
        CheckIn.shared.skip(s)
        #expect(s.done && !s.earnsBricks)
        CheckIn.shared.untick(s); CheckIn.shared.tick(s)   // skipped stays skipped: no new ask
        #expect(!CheckIn.shared.queue.contains { $0 === s } && !s.earnsBricks)
        let legacy = PlanTask(title: "Old", category: "study", minutes: 30, day: 1, order: 0)
        legacy.done = true                                  // done before check-ins existed
        #expect(legacy.earnsBricks)
        let free = PlanTask(title: "Free time", category: Plan.freeTime, minutes: 30, day: 1, order: 0)
        CheckIn.shared.tick(free)
        #expect(!CheckIn.shared.queue.contains { $0 === free } && !free.earnsBricks)
    }

    @Test func correctedTimeReplacesPace() {
        let category = "test-\(UUID())"
        Planner.recordPace(category: category, estimate: 30, actual: 30)
        Planner.correctPace(category: category, estimate: 30, from: 30, to: 45)
        #expect(Planner.savedPace()[category] == [1.5])
    }

    @Test func gapBetweenTasks() {
        let starts = Scheduler.schedule([(30, 1), (30, 1)], from: at(10), routine: .loose, gap: 10)
        #expect(starts == [at(10), at(10, 40)])
    }

    @Test func freeTimeAddedOnceWhenOverLimit() throws {
        let container = try ModelContainer(for: Plan.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let plan = Plan(title: "t", mode: .today, input: "", days: 1, start: at(9))
        container.mainContext.insert(plan)
        plan.freeFrom = 9 * 60; plan.freeUntil = 23 * 60
        plan.tasks = (0..<4).map { PlanTask(title: "W\($0)", category: "study", minutes: 60, day: 1, order: $0) }
        plan.reflow()
        plan.addFreeTime { _ in 120 }    // 2 h limit: crossed by W2
        #expect(plan.ordered.map(\.title) == ["W0", "W1", "W2", "Free time", "W3"])
        #expect(plan.ordered[3].start == at(12))
        plan.addFreeTime { _ in 120 }    // already has one that day
        #expect(plan.tasks.count == 5)
    }
}
