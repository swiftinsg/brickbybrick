import Foundation

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

extension House {
    /// Today's house from the stress streak and the rest log (Home and the widgets).
    static func state(streak: Int, log: RestLog, now: Date, calendar: Calendar = .current) -> State {
        let restedDays = (0...streak).filter {
            log.seconds(on: calendar.date(byAdding: .day, value: -$0, to: now)!, calendar: calendar) >= restGoal
        }.count
        return state(streak: streak, restedDays: restedDays, restedToday: log.seconds(on: now, calendar: calendar) >= restGoal)
    }
}
