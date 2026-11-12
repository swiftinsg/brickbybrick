import Foundation
import SwiftData
import Testing
@testable import Focusedhouse

@MainActor struct PinTests {
    @Test func pinnedTaskStaysAndOthersFlowAround() throws {
        let container = try ModelContainer(for: Plan.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let cal = Calendar.current
        // Saturday 14 Nov 2026, 10:00 (no school).
        let at = { (h: Int, m: Int) in cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: h, minute: m))! }
        let plan = Plan(title: "t", mode: .today, input: "", days: 1, start: at(10, 0))
        container.mainContext.insert(plan)
        let a = PlanTask(title: "A", category: "other", minutes: 60, day: 1, order: 0)
        let b = PlanTask(title: "B", category: "other", minutes: 30, day: 1, order: 1)
        let c = PlanTask(title: "C", category: "other", minutes: 30, day: 1, order: 2)
        plan.tasks = [a, b, c]
        c.pinned = at(10, 30)   // dragged C into the middle of A's slot
        plan.reflow()

        #expect(c.start == at(10, 30))
        #expect(a.start == at(11, 0))     // A no longer fits before C, so it goes after
        #expect(b.start == at(12, 0))     // B keeps its place after A (order = priority)
        #expect(plan.ordered.map(\.title) == ["C", "A", "B"])   // list follows time
    }

    @Test func dragNeverPinsByItself() throws {
        let container = try ModelContainer(for: Plan.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let cal = Calendar.current
        let at = { (h: Int, m: Int) in cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: h, minute: m))! }
        let plan = Plan(title: "t", mode: .today, input: "", days: 1, start: at(10, 0))
        container.mainContext.insert(plan)
        let a = PlanTask(title: "A", category: "other", minutes: 60, day: 1, order: 0)
        let b = PlanTask(title: "B", category: "other", minutes: 30, day: 1, order: 1)
        let c = PlanTask(title: "C", category: "other", minutes: 30, day: 1, order: 2)
        plan.tasks = [a, b, c]
        plan.reflow()                       // A 10:00, B 11:00, C 11:30

        plan.move(c, to: at(10, 0))         // normal priority: moves, not pinned
        #expect(c.pinned == nil)
        #expect(plan.ordered.map(\.title) == ["C", "A", "B"])
        #expect(c.start == at(10, 0))
        plan.pushBack(c, by: 30)            // running over still pushes the rest
        #expect(a.start == at(11, 0))

        b.priority = 0
        plan.move(b, to: at(15, 0))         // high priority too: never pinned without asking
        #expect(b.pinned == nil)
        #expect(b.start == at(15, 0))
    }
}
