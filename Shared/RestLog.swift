import Foundation

/// Rest per day, in seconds, shared between the app and the Screen Time monitor
/// extension through the app group. Home reads it through @AppStorage.
struct RestLog: Codable, Equatable {
    static let group = "group.sg.swiftin.2am"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
    /// A shorter time away doesn't count as rest at all.
    static let minBreak: TimeInterval = 30 * 60

    var seconds: [String: TimeInterval] = [:]

    static func key(_ day: Date, _ calendar: Calendar) -> String {
        String(Int(calendar.startOfDay(for: day).timeIntervalSinceReferenceDate))
    }

    func seconds(on day: Date, calendar: Calendar = .current) -> TimeInterval {
        seconds[Self.key(day, calendar)] ?? 0
    }

    mutating func add(_ rest: TimeInterval, on day: Date, calendar: Calendar = .current) {
        seconds[Self.key(day, calendar), default: 0] += rest
    }

    /// A gap away from the phone, counting only waking hours (`wake`/`bed` in
    /// minutes since midnight), so sleep isn't rest from the phone.
    mutating func add(from: Date, to: Date, wake: Int, bed: Int, calendar: Calendar = .current) {
        guard to.timeIntervalSince(from) >= Self.minBreak else { return }
        let bedMinutes = bed <= wake ? bed + 24 * 60 : bed   // bedtime after midnight
        var day = calendar.startOfDay(for: from)
        while day < to {
            let start = day.addingTimeInterval(TimeInterval(wake * 60))
            let end = day.addingTimeInterval(TimeInterval(bedMinutes * 60))
            let overlap = min(to, end).timeIntervalSince(max(from, start))
            if overlap > 0 { add(overlap, on: day, calendar: calendar) }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
    }

    static func load(_ data: Data) -> RestLog { (try? JSONDecoder().decode(RestLog.self, from: data)) ?? RestLog() }
    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    static func update(_ change: (inout RestLog) -> Void) {
        var log = load(defaults.data(forKey: "restLog") ?? Data())
        change(&log)
        defaults.set(log.data, forKey: "restLog")
    }
}

/// The waking hours Screen Time watches. An hour with less than `glanceMinutes`
/// of phone use counts as an hour of rest.
enum RestHours {
    // ponytail: tuning knob; a quick look at a notification shouldn't break rest.
    static let glanceMinutes = 2
    /// Screen Time monitors at most 20 activities per app.
    static let maxBlocks = 20

    /// Start and end in minutes since midnight; `end` may pass 24:00 for late bedtimes.
    struct Block: Equatable { var start: Int; var end: Int }

    static func blocks(wake: Int, bed: Int) -> [Block] {
        let end = bed <= wake ? bed + 24 * 60 : bed
        guard end - wake >= 60 else { return [] }
        return stride(from: wake, through: end - 60, by: 60).prefix(maxBlocks).map { Block(start: $0, end: $0 + 60) }
    }

    static func name(_ block: Block) -> String { "rest.\(block.start)" }
}
