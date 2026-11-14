import Foundation

/// What the widgets show, written by the app to the App Group whenever it goes
/// to the background. The widgets never open SwiftData. Rest is read live from
/// `RestLog`, so the house repairs on the widget without opening the app.
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Hashable {
        var id: String
        var title: String
        var start: Date
        var minutes: Int
        var done = false
        var free = false
        var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }
    }

    var streak = 0
    var bricks = 0
    /// Today's plan tasks, by start time.
    var today: [Item] = []
    /// Planned work minutes per day (`RestLog.key`), last 7 days.
    var work: [String: Int] = [:]
    /// Scheduled tasks and lessons: phone-down time during them isn't rest.
    var busy: [DateInterval] = []
    var showDamage = true
    var insight = ""

    var tasks: [Item] { today.filter { !$0.free } }
    var doneCount: Int { tasks.filter(\.done).count }
    /// The task on now or next.
    func next(at now: Date) -> Item? { tasks.first { !$0.done && $0.end > now } }

    /// An hour of rest from `from` to `to` overlaps something scheduled.
    func blocksRest(from: Date, to: Date) -> Bool {
        busy.contains { $0.start < to && $0.end > from }
    }

    static func load() -> WidgetSnapshot {
        RestLog.defaults.data(forKey: "widget").flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? WidgetSnapshot()
    }

    func save() { RestLog.defaults.set(try? JSONEncoder().encode(self), forKey: "widget") }

    /// Widget buttons the app applies the next time it opens (the widget can't
    /// reach SwiftData). Done isn't here: it opens the app to ask how it went.
    struct Action: Codable, Equatable {
        enum Kind: String, Codable { case more, rest }
        var kind: Kind
        var id: String
        var at: Date
    }

    /// Queues a button tap and moves the task on the widget right away;
    /// the app's reflow sets the real times later.
    static func queue(_ kind: Action.Kind, id: String, at now: Date = .now) {
        var actions = takeActions()
        actions.append(Action(kind: kind, id: id, at: now))
        RestLog.defaults.set(try? JSONEncoder().encode(actions), forKey: "widgetActions")
        var snap = load()
        snap.apply(kind, id: id, at: now)
        snap.save()
    }

    /// +15 min: the task runs longer. Take a break: it starts 15 min from now.
    /// Either way the tasks after it shift by the same amount.
    mutating func apply(_ kind: Action.Kind, id: String, at now: Date) {
        guard let i = today.firstIndex(where: { $0.id == id }) else { return }
        let oldEnd = today[i].end
        switch kind {
        case .more: today[i].minutes += 15
        case .rest: today[i].start = max(today[i].start, now).addingTimeInterval(15 * 60)
        }
        let shift = today[i].end.timeIntervalSince(oldEnd)
        for j in today.indices where j != i && !today[j].done && today[j].start >= oldEnd.addingTimeInterval(-60) {
            today[j].start += shift
        }
    }

    /// Reads and clears the queued taps.
    static func takeActions() -> [Action] {
        let d = RestLog.defaults
        let actions = d.data(forKey: "widgetActions").flatMap { try? JSONDecoder().decode([Action].self, from: $0) } ?? []
        d.removeObject(forKey: "widgetActions")
        return actions
    }
}
