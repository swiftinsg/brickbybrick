import Foundation
import FoundationModels

/// Fallback rest when Screen Time is off: time away from this app. When
/// focushouse goes to the background the time is saved; when it's opened again
/// the gap is added (waking hours only, 30+ min).
extension RestLog {
    mutating func add(from: Date, to: Date, routine: Routine, calendar: Calendar = .current) {
        add(from: from, to: to, wake: routine.wake, bed: routine.bed, calendar: calendar)
    }

    static func appLeft(at date: Date = .now) {
        UserDefaults.standard.set(date.timeIntervalSinceReferenceDate, forKey: "leftAt")
    }

    static func appOpened(at date: Date = .now) {
        let d = UserDefaults.standard
        guard d.object(forKey: "leftAt") != nil else { return }
        let left = Date(timeIntervalSinceReferenceDate: d.double(forKey: "leftAt"))
        d.removeObject(forKey: "leftAt")
        update { $0.add(from: left, to: date, routine: .current) }
    }
}

/// Effort ratings by title, saved in UserDefaults ("ratings") so each task or
/// event is only rated once. Home reads it through @AppStorage.
enum Ratings {
    static func key(_ title: String) -> String { title.trimmingCharacters(in: .whitespaces).lowercased() }
    static func load(_ data: Data) -> [String: Rating] { (try? JSONDecoder().decode([String: Rating].self, from: data)) ?? [:] }

    /// Asks the on-device model to rate `titles` and saves the answers.
    // ponytail: ratings are never pruned; drop old titles if the store ever gets big.
    @MainActor static func rate(_ titles: [String]) async {
        guard Planner.isAvailable, !titles.isEmpty else { return }
        let d = UserDefaults.standard
        var saved = load(d.data(forKey: "ratings") ?? Data())
        for chunk in stride(from: 0, to: titles.count, by: 15).map({ Array(titles[$0..<min($0 + 15, titles.count)]) }) {
            let session = LanguageModelSession(instructions: """
                You score how demanding things in a student's day are, from 1 to 10, from their titles. \
                1-3: quick, light or fun (reply to a message, tidy desk, lunch with friends). \
                4-6: ordinary homework, chores, practice, a regular club. \
                7-8: long or difficult work, big assignments, revision, presentations, competitions. \
                9-10: exams, major tests, deadlines due very soon, high-stakes performances. \
                compulsory is true for things the student can't skip: exams, tests, school lessons, \
                assignments or deadlines set by a teacher.
                """)
            let prompt = "Rate each of these:\n" + chunk.map { "- \($0)" }.joined(separator: "\n")
            guard let reply = try? await session.respond(to: prompt, generating: DraftRatings.self).content else { continue }
            for r in reply.ratings { saved[key(r.title)] = Rating(score: r.score, compulsory: r.compulsory) }
        }
        d.set((try? JSONEncoder().encode(saved)) ?? Data(), forKey: "ratings")
    }
}

@Generable struct DraftRatings {
    @Guide(description: "One rating per title, in the same order", .count(1...15))
    var ratings: [DraftRating]
}

@Generable struct DraftRating {
    @Guide(description: "The title exactly as given")
    var title: String
    @Guide(description: "How demanding it is for a typical student, 1 (very light) to 10 (exam-level)", .range(1...10))
    var score: Int
    @Guide(description: "true if the student can't skip it: exams, tests, school lessons, teacher-set assignments or deadlines")
    var compulsory: Bool
}

/// Home's stress streak and earned bricks from the saved tasks, Tasks-tab items
/// and Calendar events. The widgets get the same numbers through `WidgetSync`.
// ponytail: scans every task each time; fine for a student's few hundred.
@MainActor struct HouseStatus {
    private(set) var streak = 0
    private(set) var earned = 0
    private let ratings: [String: Rating]
    private let pace: [String: Double]

    init(tasks: [PlanTask], todos: [TodoItem], events: [(title: String, start: Date, minutes: Int)],
         ratings: [String: Rating], now: Date = .now) {
        self.ratings = ratings
        pace = Dictionary(Planner.pace().map { ($0.category, $0.ratio) }, uniquingKeysWith: { a, _ in a })
        var load: [(day: Date, minutes: Int)] = []
        var bricks: [(day: Date, bricks: Int)] = []
        // Stress per day from what the student does and attends: plan tasks at their
        // time, Tasks-tab items on their due day, Calendar events.
        for t in tasks {
            let r = rating(t.title, priority: t.priority, category: t.category)
            if let start = t.start { load.append((start, House.stress(minutes: t.minutes, r))) }
            if t.earnsBricks, let day = t.start ?? t.plan?.start {
                bricks.append((day, House.bricks(minutes: t.estimate ?? t.minutes, r.effort)))
            }
        }
        for t in todos {
            let r = rating(t.name, priority: t.priority.level)
            load.append((t.dueDate, House.stress(minutes: House.todoMinutes, r)))
            if t.isDone { bricks.append((t.dueDate, r.effort == .easy ? 0 : House.todoBricks)) }
        }
        load += events.map { ($0.start, House.stress(minutes: $0.minutes, rating($0.title, priority: 1))) }
        streak = House.streak(load, now: now)
        earned = House.total(bricks)
    }

    /// The AI's rating for a title, or one from priority until it's rated;
    /// for plan tasks, scaled by the student's pace in that category.
    func rating(_ title: String, priority: Int, category: String? = nil) -> Rating {
        let r = ratings[Ratings.key(title)] ?? Rating(priority: priority)
        guard let category, let p = pace[category] else { return r }
        return r.personal(p)
    }
}

extension Priority {
    /// The plan tasks' scale: 0 high, 1 normal, 2 low.
    var level: Int { self == .high ? 0 : self == .low ? 2 : 1 }
}
