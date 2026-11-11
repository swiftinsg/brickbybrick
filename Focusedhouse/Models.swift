import Foundation
import SwiftData

enum PlanMode: String, CaseIterable {
    case today = "Today", goal = "Goal"
}

@Model final class Plan {
    var title: String
    var modeRaw: String
    var input: String
    var materials = ""   // optional study material, split into sections by the AI
    var days: Int
    var start: Date
    var createdAt = Date.now
    /// "Ask when I'm free" answer, minutes since midnight; nil = use the routine.
    var freeFrom: Int?
    var freeUntil: Int?
    @Relationship(deleteRule: .cascade, inverse: \PlanTask.plan) var tasks: [PlanTask] = []

    init(title: String, mode: PlanMode, input: String, days: Int, start: Date) {
        self.title = title
        self.modeRaw = mode.rawValue
        self.input = input
        self.days = days
        self.start = start
    }

    var mode: PlanMode { PlanMode(rawValue: modeRaw) ?? .today }
    var ordered: [PlanTask] { tasks.sorted { $0.order < $1.order } }

    /// The routine this plan schedules into: the "ask each time" answer, or Settings.
    var routine: Routine {
        guard let freeFrom, let freeUntil else { return .current }
        return Routine(wake: freeFrom, bed: freeUntil, hasSchool: false)
    }

    /// Recompute every task's start time from the plan start, in order,
    /// around Calendar events (but not around this plan's own events).
    @MainActor func reflow() {
        let list = ordered
        let busy = CalendarSync.busy(from: start, days: days, excluding: Set(list.compactMap(\.eventID)))
        let starts = Scheduler.schedule(list.map { ($0.minutes, $0.day) }, from: start,
                                        routine: routine, busy: busy)
        for (task, s) in zip(list, starts) { task.start = s }
    }
}

@Model final class PlanTask {
    var title: String
    var category: String
    var minutes: Int
    var day: Int
    var order: Int
    var start: Date?
    var done = false
    var eventID: String?   // Calendar event, once added
    var priority = 1       // 0 high, 1 normal, 2 low
    var section = ""       // topic from the study material
    var plan: Plan?

    init(title: String, category: String, minutes: Int, day: Int, order: Int) {
        self.title = title
        self.category = category
        self.minutes = minutes
        self.day = day
        self.order = order
    }

    var end: Date? { start?.addingTimeInterval(TimeInterval(minutes * 60)) }
}
