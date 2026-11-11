import Foundation
import SwiftData

enum PlanMode: String, CaseIterable {
    case today = "Today", goal = "Goal"
}

@Model final class Plan {
    var title: String
    var modeRaw: String
    var input: String
    var days: Int
    var start: Date
    var createdAt = Date.now
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

    /// Recompute every task's start time from the plan start, in order.
    func reflow(routine: Routine = .current) {
        let list = ordered
        let starts = Scheduler.schedule(list.map { ($0.minutes, $0.day) }, from: start, routine: routine)
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
