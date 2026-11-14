import Foundation
import FoundationModels
import Observation
import SwiftData

/// "How did it go?" after a task is ticked: time it took, how it felt (1–5) and
/// an optional note. Bricks only come once it's answered; skipping means none,
/// ever. Ticks from anywhere (lists, notifications) queue here and Home shows
/// the sheet; ticks still waiting when the app quits are asked again next launch.
@MainActor @Observable final class CheckIn {
    static let shared = CheckIn()
    /// Tasks waiting for an answer; the sheet shows the first.
    var queue: [PlanTask] = []

    /// Ticks or unticks a task, asking how it went on the first tick.
    func toggle(_ task: PlanTask) {
        if task.done { untick(task) } else { tick(task) }
    }

    func tick(_ task: PlanTask) {
        guard !task.done else { return }
        task.setDone(true)
        guard task.category != Plan.freeTime, task.checkIn == PlanTask.CheckInState.none.rawValue else { return }
        task.checkIn = PlanTask.CheckInState.waiting.rawValue
        if !queue.contains(where: { $0 === task }) { queue.append(task) }
    }

    func untick(_ task: PlanTask) {
        task.setDone(false)
        if task.checkIn == PlanTask.CheckInState.waiting.rawValue { task.checkIn = PlanTask.CheckInState.none.rawValue }
        queue.removeAll { $0 === task }
    }

    /// Saves the answer. A corrected time replaces the guess in the student's pace.
    func save(_ task: PlanTask, minutes: Int, feeling: Int, note: String, now: Date = .now) {
        let minutes = max(1, minutes)
        if let estimate = task.estimate {
            if let old = task.actual {
                if old != minutes { Planner.correctPace(category: task.category, estimate: estimate, from: old, to: minutes) }
            } else {
                Planner.recordPace(category: task.category, estimate: estimate, actual: minutes)
            }
        }
        task.actual = minutes
        task.feeling = min(5, max(1, feeling))
        task.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        task.reflectedAt = now
        task.checkIn = PlanTask.CheckInState.answered.rawValue
        queue.removeAll { $0 === task }
    }

    /// Closed without answering: asked again next launch, no bricks until then.
    func later(_ task: PlanTask) {
        queue.removeAll { $0 === task }
    }

    /// No answer: the task stays done but never earns bricks.
    func skip(_ task: PlanTask) {
        task.checkIn = PlanTask.CheckInState.skipped.rawValue
        queue.removeAll { $0 === task }
    }

    /// Next launch: ask again about ticks left waiting, and drop old notes.
    func restore(_ context: ModelContext) {
        let waiting = PlanTask.CheckInState.waiting.rawValue
        queue = (try? context.fetch(FetchDescriptor<PlanTask>(predicate: #Predicate { $0.checkIn == waiting && $0.done }))) ?? []
        Reflections.purgeNotes(Reflections.history(in: context))
    }
}

/// What the check-ins teach the planner. Plain code finds the patterns (best
/// time of day, draining kinds of work, a hard day); the AI gets them in the
/// prompt and writes the weekly insight.
enum Reflections {
    /// Parts of the day, in order.
    enum Slot: Int, CaseIterable, Comparable {
        case morning, afternoon, evening, night
        init(_ date: Date, calendar: Calendar = .current) {
            let h = calendar.component(.hour, from: date)
            self = h < 12 ? .morning : h < 17 ? .afternoon : h < 20 ? .evening : .night
        }
        var name: String { ["morning", "afternoon", "evening", "night"][rawValue] }
        static func < (a: Slot, b: Slot) -> Bool { a.rawValue < b.rawValue }
    }

    /// Answers needed before a pattern counts, so one bad day doesn't decide it.
    static let minAnswers = 3
    static let noteDays = 30

    /// Every answered task.
    static func history(in context: ModelContext?) -> [PlanTask] {
        let answered = PlanTask.CheckInState.answered.rawValue
        return (try? context?.fetch(FetchDescriptor<PlanTask>(predicate: #Predicate { $0.checkIn == answered }))) ?? []
    }

    private static func average(_ tasks: [PlanTask]) -> Double {
        Double(tasks.compactMap(\.feeling).reduce(0, +)) / Double(max(1, tasks.count))
    }

    /// The part of the day the student feels best and worst in, when they're at
    /// least half a point apart.
    static func bestTime(_ history: [PlanTask], calendar: Calendar = .current)
        -> (best: Slot, bestScore: Double, worst: Slot, worstScore: Double)? {
        let bySlot = Dictionary(grouping: history.filter { $0.feeling != nil && $0.start != nil }) { Slot($0.start!, calendar: calendar) }
            .filter { $0.value.count >= minAnswers }
            .mapValues(average)
        guard let best = bySlot.max(by: { $0.value < $1.value }),
              let worst = bySlot.min(by: { $0.value < $1.value }),
              best.value - worst.value >= 0.5 else { return nil }
        return (best.key, best.value, worst.key, worst.value)
    }

    /// Kinds of work that usually leave the student drained (2/5 or lower on average).
    static func draining(_ history: [PlanTask]) -> [String] {
        Dictionary(grouping: history.filter { $0.feeling != nil }, by: \.category)
            .filter { $0.value.count >= minAnswers && average($0.value) <= 2 }
            .keys.sorted()
    }

    /// Yesterday or today felt hard: 2+ answers averaging 2/5 or lower.
    static func wasHardDay(_ history: [PlanTask], now: Date = .now, calendar: Calendar = .current) -> Bool {
        let from = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let recent = history.filter { ($0.reflectedAt ?? .distantPast) >= from && $0.feeling != nil }
        return recent.count >= 2 && average(recent) <= 2
    }

    /// Minutes of break between tasks for a new plan: 10 after a hard day.
    static func breakMinutes(_ history: [PlanTask], now: Date = .now) -> Int {
        wasHardDay(history, now: now) ? 10 : 0
    }

    /// Raw notes are deleted after 30 days; feelings and times (the patterns) stay.
    static func purgeNotes(_ history: [PlanTask], now: Date = .now) {
        let cutoff = now.addingTimeInterval(-Double(noteDays) * 86_400)
        for t in history where !t.note.isEmpty && (t.reflectedAt ?? .distantPast) < cutoff { t.note = "" }
    }

    /// Prompt section from the check-ins; empty when there's nothing to say yet.
    static func promptNote(_ history: [PlanTask], now: Date = .now) -> String {
        var lines: [String] = []
        if let t = bestTime(history) {
            let order = t.best < t.worst ? "put hard or high-effort items first in each day's order"
                                         : "put light items first and hard items later in each day's order"
            lines.append("- They feel best in the \(t.best.name) (\(score(t.bestScore))/5) and worst in the \(t.worst.name) (\(score(t.worstScore))/5): \(order).")
        }
        let drain = draining(history)
        if !drain.isEmpty {
            lines.append("- These kinds of work drain them: \(drain.joined(separator: ", ")). Split them into subtasks of 30 minutes or less.")
        }
        // ponytail: last 5 notes, cut to 100 characters, to fit the small model's context.
        let notes = history.filter { !$0.note.isEmpty && ($0.reflectedAt ?? .distantPast) > now.addingTimeInterval(-14 * 86_400) }
            .sorted { $0.reflectedAt! > $1.reflectedAt! }.prefix(5)
            .map { "\"\($0.note.prefix(100))\" (after \($0.title))" }
        if !notes.isEmpty { lines.append("- Their recent notes: " + notes.joined(separator: "; ")) }
        guard !lines.isEmpty else { return "" }
        return "\n\nHow this student says their tasks have gone (from their check-ins). Use it:\n" + lines.joined(separator: "\n")
    }

    private static func score(_ x: Double) -> String { x.formatted(.number.precision(.fractionLength(1))) }

    /// One line per answered task this week, for the insight prompt.
    static func weekLines(_ history: [PlanTask], now: Date = .now) -> [String] {
        history.filter { ($0.reflectedAt ?? .distantPast) > now.addingTimeInterval(-7 * 86_400) && $0.start != nil }
            .sorted { $0.start! < $1.start! }
            .map { t in
                "- \(t.start!.formatted(.dateTime.weekday().hour().minute())), \(t.title) (\(t.category)): planned \(t.estimate ?? t.minutes) min"
                    + (t.actual.map { ", took \($0)" } ?? "") + (t.feeling.map { ", felt \($0)/5" } ?? "")
                    + (t.note.isEmpty ? "" : ". Note: \(t.note.prefix(100))")
            }
    }

    /// Weekly insight card on Home: the AI's one or two sentences about the last
    /// 7 days of check-ins, refreshed at most once a day (UserDefaults "insight").
    @MainActor static func refreshInsight(_ history: [PlanTask], now: Date = .now) async {
        let d = UserDefaults.standard
        guard Planner.isAvailable, now.timeIntervalSince1970 - d.double(forKey: "insightAt") >= 86_400 else { return }
        // ponytail: last 25 check-ins of the week, to fit the small model's context.
        let lines = weekLines(history, now: now).suffix(25)
        guard lines.count >= minAnswers else { return }
        let session = LanguageModelSession(instructions: """
            You are a kind coach for a teenage student who wants a healthy balance between \
            schoolwork and rest. From their check-ins this week, write ONE short insight: \
            a specific pattern you notice, then one gentle suggestion (when to do hard work, \
            splitting a task, or taking a break). At most 2 sentences and 40 words. Talk to \
            them as "you". Only use facts given. Never shame or pressure them.
            """)
        var prompt = "This week's check-ins (felt: 1 drained, 5 energised):\n" + lines.joined(separator: "\n")
        prompt += promptNote(history, now: now)
        guard let text = try? await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        d.set(text, forKey: "insight")
        d.set(now.timeIntervalSince1970, forKey: "insightAt")
    }
}

/// The student's daily work limit (Settings). Over it, a new plan gets a
/// free-time break and the day shows a warning. Defaults from research on teens:
/// homework stops helping at about 2 h a night, and 5 h+ of weekend study is
/// linked to more anxiety (see NOTES.md).
enum WorkLimit {
    static let schoolDefault = 180
    static let offDefault = 240
    /// Above this the Settings note warns, from the research.
    static let research = 300

    static func minutes(on day: Date, routine: Routine = .current, defaults d: UserDefaults = .standard,
                        calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: day)
        let school = routine.hasSchool && (2...6).contains(weekday)
        let key = school ? "limitSchool" : "limitOff"
        return d.object(forKey: key) == nil ? (school ? schoolDefault : offDefault) : d.integer(forKey: key)
    }
}

extension Plan {
    /// Category of the free-time blocks added when a day goes over the limit.
    static let freeTime = "free time"

    /// Minutes of work (not free time) per scheduled day.
    var workPerDay: [Date: Int] {
        tasks.filter { $0.category != Plan.freeTime && $0.start != nil }
            .reduce(into: [:]) { $0[Calendar.current.startOfDay(for: $1.start!), default: 0] += $1.minutes }
    }

    /// After a plan is made: on each day over the limit, a 30 min free-time block
    /// goes right after the task that crosses it (once per day). Warns, doesn't cap.
    @MainActor func addFreeTime(limit: (Date) -> Int = { WorkLimit.minutes(on: $0) }) {
        let cal = Calendar.current
        var list = ordered
        var total: [Date: Int] = [:]
        var added = Set(list.filter { $0.category == Plan.freeTime }.compactMap { $0.start.map(cal.startOfDay(for:)) })
        let before = list.count
        var i = 0
        while i < list.count {
            let task = list[i]
            i += 1
            guard task.category != Plan.freeTime, let start = task.start else { continue }
            let day = cal.startOfDay(for: start)
            total[day, default: 0] += task.minutes
            // Only between tasks: a break after the day's last task changes nothing.
            guard total[day]! > limit(day), !added.contains(day), i < list.count,
                  let next = list[i].start, cal.isDate(next, inSameDayAs: day) else { continue }
            added.insert(day)
            let rest = PlanTask(title: "Free time", category: Plan.freeTime, minutes: 30, day: task.day, order: 0)
            rest.priority = 2
            rest.notBefore = task.end
            tasks.append(rest)
            list.insert(rest, at: i)
            i += 1
        }
        guard list.count > before else { return }
        for (n, t) in list.enumerated() { t.order = n }
        reflow()
    }
}
