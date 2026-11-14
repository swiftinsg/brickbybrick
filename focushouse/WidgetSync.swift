import Foundation
import SwiftData
import WidgetKit

/// Keeps the widgets up to date: writes `WidgetSnapshot` when the app goes to
/// the background, and applies the widget's buttons when it comes back.
@MainActor enum WidgetSync {
    static func write(_ context: ModelContext, now: Date = .now) {
        let cal = Calendar.current
        let d = UserDefaults.standard
        let tasks = (try? context.fetch(FetchDescriptor<PlanTask>())) ?? []
        let todos = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        let own = Set(tasks.compactMap(\.eventID))
        let events = CalendarSync.attended(from: now.addingTimeInterval(-14 * 86_400), to: now.addingTimeInterval(2 * 86_400), excluding: own)
        let ratings = Ratings.load(d.data(forKey: "ratings") ?? Data())
        let status = HouseStatus(tasks: tasks, todos: todos, events: events, ratings: ratings, now: now)

        var snap = WidgetSnapshot()
        snap.streak = status.streak
        snap.bricks = max(0, status.earned - Shop.spent(Shop.owned(d.string(forKey: "owned") ?? "")))
        snap.today = tasks.filter { $0.start.map { cal.isDate($0, inSameDayAs: now) } ?? false }
            .sorted { $0.start! < $1.start! }
            .map { .init(id: $0.key, title: $0.title, start: $0.start!, minutes: $0.minutes, done: $0.done, free: $0.category == Plan.freeTime) }
        let weekAgo = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))!
        for t in tasks where t.category != Plan.freeTime {
            guard let start = t.start, start >= weekAgo, start < now.addingTimeInterval(86_400) else { continue }
            snap.work[RestLog.key(start, cal), default: 0] += t.minutes
        }
        // Rest doesn't count during tasks still on the schedule or during lessons
        // (Calendar events the AI rated compulsory, or not rated yet).
        let soon = now.addingTimeInterval(-86_400)...now.addingTimeInterval(2 * 86_400)
        snap.busy = tasks.filter { !$0.done && $0.category != Plan.freeTime && $0.start.map(soon.contains) == true }
            .map { DateInterval(start: $0.start!, end: $0.end!) }
            + events.filter { soon.contains($0.start) && ratings[Ratings.key($0.title)]?.compulsory != false }
            .map { DateInterval(start: $0.start, duration: TimeInterval($0.minutes * 60)) }
        snap.showDamage = d.object(forKey: "showDamage") as? Bool ?? true
        snap.insight = d.string(forKey: "insight") ?? ""
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// +15 min and Take a break, tapped on a widget while the app was closed.
    static func apply(_ context: ModelContext) {
        for action in WidgetSnapshot.takeActions() {
            guard let task = task(action.id, context), let plan = task.plan, !task.done else { continue }
            switch action.kind {
            case .more: plan.pushBack(task, by: 15)
            case .rest:
                task.pinned = nil
                task.notBefore = max(task.start ?? action.at, action.at).addingTimeInterval(15 * 60)
                plan.reflow()
            }
        }
        try? context.save()
    }

    /// Done on a widget opens `focushouse://done/<task>`; the check-in sheet
    /// asks how it went before any bricks are given.
    static func open(_ url: URL, _ context: ModelContext) {
        guard url.host() == "done", let task = task(url.lastPathComponent, context) else { return }
        CheckIn.shared.tick(task)
        task.plan?.reflow()
        try? context.save()
    }

    private static func task(_ key: String, _ context: ModelContext) -> PlanTask? {
        guard let uid = UUID(uuidString: key) else { return nil }
        return try? context.fetch(FetchDescriptor<PlanTask>(predicate: #Predicate { $0.uid == uid })).first
    }
}
