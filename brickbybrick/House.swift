import Foundation
import FoundationModels

/// How demanding something is, from its 1–10 score.
enum Effort: Int, Codable, CaseIterable { case easy, normal, hard, intense }

/// The AI scores each task and Calendar event once from its title (1–10). The
/// score is then scaled by the student's own pace, so ranges decide the effort:
/// 1–3 easy, 4–6 normal, 7–8 hard, 9–10 intense. Without Apple Intelligence,
/// priority stands in.
struct Rating: Codable, Equatable {
    var score: Int
    /// Can't be skipped (exams, lessons, set deadlines): counts half toward stress.
    var compulsory = false

    init(score: Int, compulsory: Bool = false) {
        self.score = min(10, max(1, score))
        self.compulsory = compulsory
    }

    /// Stand-in from priority (0 high, 1 normal, 2 low) until, or without, the AI.
    init(priority: Int) { self.init(score: priority == 0 ? 8 : priority == 2 ? 2 : 5) }

    var effort: Effort { score <= 3 ? .easy : score <= 6 ? .normal : score <= 8 ? .hard : .intense }

    /// Scaled by how long this kind of work really takes the student
    /// (actual ÷ estimate, from the adaptive estimates): slower = harder for them.
    func personal(_ pace: Double) -> Rating {
        Rating(score: Int((Double(score) * pace).rounded()), compulsory: compulsory)
    }
}

/// The house on Home. Several stressful days in a row knock it down a step at a
/// time (calm → stressed → overloaded → crumbling); real rest, time away from the
/// phone, repairs one step per rested day. Bricks (points) come from finished
/// tasks and are kept separate: they buy furniture, they never repair the house.
/// Stress and bricks are plain deterministic code; only the effort rating uses AI.
enum House {
    enum State: String, CaseIterable {
        case calm, stressed, overloaded, crumbling, resting
    }

    // ponytail: tuning knobs, first guesses until students try it.
    /// Weighted minutes in one day that make it a stressful day.
    static let stressfulMinutes = 120
    /// How much one minute of each effort adds to stress (easy adds nothing).
    static let weight: [Effort: Double] = [.easy: 0, .normal: 0.5, .hard: 1, .intense: 1.5]
    /// An item from the Tasks tab counts as this much time on its due day.
    static let todoMinutes = 30
    /// Rest in one day (waking hours) that repairs one step.
    static let restGoal: TimeInterval = 3 * 3600
    /// A shorter time away doesn't count as rest at all.
    static let minBreak: TimeInterval = 30 * 60
    static let todoBricks = 3
    static let dailyBrickCap = 100

    /// Stressful days in a row, ending today, or yesterday when today isn't
    /// stressful (yet), so the streak doesn't reset every morning.
    static func streak(_ load: [(day: Date, minutes: Int)], now: Date, calendar: Calendar = .current) -> Int {
        var perDay: [Date: Int] = [:]
        for l in load { perDay[calendar.startOfDay(for: l.day), default: 0] += l.minutes }
        let stressful = { (day: Date) in perDay[day, default: 0] >= stressfulMinutes }
        var day = calendar.startOfDay(for: now)
        if !stressful(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while stressful(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    /// Damage steps 0...3 before rest: every 2 stressful days in a row is one step.
    static func strain(streak: Int) -> Int { min(3, streak / 2) }

    /// `restedDays`: days with enough rest during the streak, today included.
    static func state(streak: Int, restedDays: Int, restedToday: Bool) -> State {
        let strain = strain(streak: streak)
        if restedToday && strain > 0 { return .resting }
        return [.calm, .stressed, .overloaded, .crumbling][max(0, strain - restedDays)]
    }

    /// Stress from doing or attending something: its minutes × effort weight,
    /// halved when it's compulsory.
    static func stress(minutes: Int, _ r: Rating) -> Int {
        Int(Double(minutes) * weight[r.effort]! * (r.compulsory ? 0.5 : 1))
    }

    /// Bricks for a finished task: 1 per 10 estimated minutes, ×1.5 hard, ×2
    /// intense, nothing for easy ones. From the estimate, so taking longer never pays more.
    static func bricks(minutes: Int, _ effort: Effort) -> Int {
        let base = max(1, minutes / 10)
        switch effort {
        case .easy: return 0
        case .normal: return base
        case .hard: return base * 3 / 2
        case .intense: return base * 2
        }
    }

    /// Total bricks, at most `dailyBrickCap` per day so making up tasks doesn't pay.
    static func total(_ earned: [(day: Date, bricks: Int)], calendar: Calendar = .current) -> Int {
        Dictionary(grouping: earned) { calendar.startOfDay(for: $0.day) }
            .values.reduce(0) { $0 + min(dailyBrickCap, $1.reduce(0) { $0 + $1.bricks }) }
    }
}

/// Time away from the app, per day. When brickbybrick goes to the background
/// the time is saved; when it's opened again the gap is added, counting only
/// waking hours (sleep isn't "rest from the phone") and only gaps of 30+ min.
// ponytail: measures time away from this app, not the whole phone. Switch to
// Screen Time (DeviceActivity, needs Apple's Family Controls approval) for real
// phone-free time.
struct RestLog: Codable, Equatable {
    var seconds: [String: TimeInterval] = [:]

    static func key(_ day: Date, _ calendar: Calendar) -> String {
        String(Int(calendar.startOfDay(for: day).timeIntervalSinceReferenceDate))
    }

    func seconds(on day: Date, calendar: Calendar = .current) -> TimeInterval {
        seconds[Self.key(day, calendar)] ?? 0
    }

    mutating func add(from: Date, to: Date, routine: Routine, calendar: Calendar = .current) {
        guard to.timeIntervalSince(from) >= House.minBreak else { return }
        var day = calendar.startOfDay(for: from)
        while day < to {
            let wake = day.addingTimeInterval(TimeInterval(routine.wake * 60))
            let bedMinutes = routine.bed <= routine.wake ? routine.bed + 24 * 60 : routine.bed   // bedtime after midnight
            let bed = day.addingTimeInterval(TimeInterval(bedMinutes * 60))
            let overlap = min(to, bed).timeIntervalSince(max(from, wake))
            if overlap > 0 { seconds[Self.key(day, calendar), default: 0] += overlap }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
    }

    // Saved in UserDefaults ("restLog"), read by Home through @AppStorage.
    static func load(_ data: Data) -> RestLog { (try? JSONDecoder().decode(RestLog.self, from: data)) ?? RestLog() }
    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    static func appLeft(at date: Date = .now) {
        UserDefaults.standard.set(date.timeIntervalSinceReferenceDate, forKey: "leftAt")
    }

    static func appOpened(at date: Date = .now) {
        let d = UserDefaults.standard
        guard d.object(forKey: "leftAt") != nil else { return }
        let left = Date(timeIntervalSinceReferenceDate: d.double(forKey: "leftAt"))
        d.removeObject(forKey: "leftAt")
        var log = load(d.data(forKey: "restLog") ?? Data())
        log.add(from: left, to: date, routine: .current)
        d.set(log.data, forKey: "restLog")
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
