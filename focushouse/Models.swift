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
        // Keep school hours: a multi-day plan must still avoid lessons on school days.
        var r = Routine.current
        r.wake = freeFrom
        r.bed = freeUntil
        return r
    }

    /// Recompute start times of unfinished tasks from the plan start, in order,
    /// around Calendar events (not this plan's own), finished tasks (which keep
    /// their times) and tasks the student pinned. A dragged task starts no earlier
    /// than where it was dropped.
    /// Then list order follows time, and reminders are re-armed.
    @MainActor func reflow() {
        let list = ordered
        for task in list where task.pinned != nil && !task.done { task.start = task.pinned }
        let fixed = list.filter { $0.done || $0.pinned != nil }.compactMap { t in t.start.map { $0..<t.end! } }
        let flowing = list.filter { !$0.done && $0.pinned == nil }
        let busy = CalendarSync.busy(from: start, days: days, excluding: Set(list.compactMap(\.eventID)))
        let starts = Scheduler.schedule(flowing.map { ($0.minutes, $0.day) }, from: start,
                                        routine: routine, busy: busy + fixed,
                                        notBefore: flowing.map(\.notBefore))
        for (task, s) in zip(flowing, starts) { task.start = s }
        for (i, task) in list.enumerated().sorted(by: {
            ($0.element.start ?? .distantFuture, $0.offset) < ($1.element.start ?? .distantFuture, $1.offset)
        }).map(\.element).enumerated() { task.order = i }
        Reminders.sync(self)
    }

    /// "Need more time": the task runs longer and everything after it shifts later
    /// (past bedtime it moves to the next free morning).
    /// Timeline drag: the task moves to `date`, among the other tasks by time.
    /// It isn't pinned (the timeline asks first), so it can still be pushed
    /// later if earlier tasks run over.
    @MainActor func move(_ task: PlanTask, to date: Date) {
        let cal = Calendar.current
        task.day = max(1, (cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: date)).day ?? 0) + 1)
        task.pinned = nil
        task.notBefore = date
        // Slot it in among the other tasks by time, so it flows from there.
        var list = ordered.filter { $0 !== task }
        let index = list.firstIndex { ($0.start ?? .distantFuture) >= date } ?? list.count
        list.insert(task, at: index)
        for (i, t) in list.enumerated() { t.order = i }
        reflow()
    }

    @MainActor func pushBack(_ task: PlanTask, by minutes: Int) {
        task.minutes += minutes
        reflow()
    }
}

extension Plan {
    /// Deletes tasks with their Calendar events and reminders, then reflows.
    @MainActor func delete(_ gone: [PlanTask]) {
        CalendarSync.remove(gone)
        Reminders.cancel(gone)
        tasks.removeAll { t in gone.contains { $0 === t } }
        gone.forEach { modelContext?.delete($0) }
        for (i, task) in ordered.enumerated() { task.order = i }
        reflow()
    }

    /// A new, empty subtask right after `last`, on the same day with the same
    /// category, priority and parent.
    @MainActor func addSubtask(after last: PlanTask) -> PlanTask {
        let task = PlanTask(title: "", category: last.category, minutes: 20, day: last.day, order: 0)
        task.priority = last.priority
        task.parent = last.parent
        var list = ordered
        list.insert(task, at: (list.firstIndex { $0 === last } ?? list.count - 1) + 1)
        tasks.append(task)
        for (i, t) in list.enumerated() { t.order = i }
        reflow()
        return task
    }

    /// Groups `subtasks` under `name`. Blank subtasks are dropped, and a single
    /// subtask with the item's own name stays a plain task. A breakdown of 2+
    /// subtasks is remembered so the AI suggests similar ones next time.
    @MainActor func saveSubtasks(_ subtasks: [PlanTask], name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        let blank = subtasks.filter { $0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        let kept = subtasks.filter { t in !blank.contains { $0 === t } }
        let standalone = name.isEmpty || kept.count == 1 && kept[0].title == name
        kept.forEach { $0.parent = standalone ? "" : name }
        if !standalone, kept.count >= 2 {
            Planner.remember(item: name, steps: kept.map { ($0.title, $0.minutes) })
        }
        if blank.isEmpty { reflow() } else { delete(blank) }
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
    /// The bigger item this is a subtask of ("English essay"), or empty for a standalone task.
    @Attribute(originalName: "section") var parent = ""
    var uid: UUID?         // stable id for reminders; set on first use
    var pinned: Date?      // fixed time, set only by the student ("Pin time")
    var notBefore: Date?   // dropped here on the timeline; may still be pushed later
    var estimate: Int?     // the AI's minutes, kept to learn the student's pace
    var actual: Int?       // minutes it really took, once recorded
    var plan: Plan?

    init(title: String, category: String, minutes: Int, day: Int, order: Int) {
        self.title = title
        self.category = category
        self.minutes = minutes
        self.day = day
        self.order = order
    }

    var end: Date? { start?.addingTimeInterval(TimeInterval(minutes * 60)) }

    /// Ticks or unticks the task. The first time an AI-estimated task is done,
    /// its real duration is recorded: time so far if ticked mid-task, its
    /// (pushed-back) length if ticked after it ended. Ticked before it started
    /// = unknown, not recorded.
    func setDone(_ value: Bool, now: Date = .now) {
        done = value
        guard value, actual == nil, let estimate, let start, let end = self.end, start <= now else { return }
        let real = now < end ? max(5, Int(now.timeIntervalSince(start) / 60)) : minutes
        actual = real
        Planner.recordPace(category: category, estimate: estimate, actual: real)
    }

    var key: String {
        if uid == nil { uid = UUID() }
        return uid!.uuidString
    }
}
