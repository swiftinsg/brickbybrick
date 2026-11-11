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

    /// Recompute start times of unfinished tasks from the plan start, in order,
    /// around Calendar events (not this plan's own) and around finished tasks,
    /// which keep their times. Then re-arm the reminders.
    @MainActor func reflow() {
        let list = ordered
        let pending = list.filter { !$0.done }
        let finished = list.filter(\.done).compactMap { t in t.start.map { $0..<t.end! } }
        let busy = CalendarSync.busy(from: start, days: days, excluding: Set(list.compactMap(\.eventID)))
        let starts = Scheduler.schedule(pending.map { ($0.minutes, $0.day) }, from: start,
                                        routine: routine, busy: busy + finished)
        for (task, s) in zip(pending, starts) { task.start = s }
        Reminders.sync(self)
    }

    /// "Need more time": the task runs longer and everything after it shifts later
    /// (past bedtime it moves to the next free morning).
    @MainActor func pushBack(_ task: PlanTask, by minutes: Int) {
        task.minutes += minutes
        reflow()
    }
}

extension Date {
    /// Now, rounded up to the next 5 minutes.
    static var nextFiveMinutes: Date {
        let step: TimeInterval = 5 * 60
        return Date(timeIntervalSinceReferenceDate: (Date.now.timeIntervalSinceReferenceDate / step).rounded(.up) * step)
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
    var uid: UUID?         // stable id for reminders; set on first use
    var plan: Plan?

    init(title: String, category: String, minutes: Int, day: Int, order: Int) {
        self.title = title
        self.category = category
        self.minutes = minutes
        self.day = day
        self.order = order
    }

    var end: Date? { start?.addingTimeInterval(TimeInterval(minutes * 60)) }

    var key: String {
        if uid == nil { uid = UUID() }
        return uid!.uuidString
    }
}
