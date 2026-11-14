import AppIntents
import SwiftUI
import WidgetKit

@main struct FocusHouseWidgets: WidgetBundle {
    init() { Theme.registerFonts() }

    var body: some Widget {
        HouseWidget()
        TodayWidget()
        WeekWidget()
    }
}

// MARK: Data

struct Entry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
    let log: RestLog

    var state: House.State { House.state(streak: snap.streak, log: log, now: date) }
    var rest: TimeInterval { log.seconds(on: date) }
    var next: WidgetSnapshot.Item? { snap.next(at: date) }
    /// "Show house damage on widgets" is off and the house is hurt: lead with rest.
    var leadsWithRest: Bool { !snap.showDamage && state != .calm && state != .resting }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snap: .sample, log: RestLog()) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let entry = current(.now)
        completion(context.isPreview && entry.snap.today.isEmpty ? placeholder(in: context) : entry)
    }

    /// One entry now, then one at each task start and end today so "Next" rolls
    /// over, and one at midnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date.now
        let snap = WidgetSnapshot.load()
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        let dates = Set(snap.today.flatMap { [$0.start, $0.end] }.filter { $0 > now } + [midnight])
        let entries = ([now] + dates.sorted()).map { current($0, snap) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func current(_ date: Date, _ snap: WidgetSnapshot = .load()) -> Entry {
        Entry(date: date, snap: snap, log: RestLog.load(RestLog.defaults.data(forKey: "restLog") ?? Data()))
    }
}

extension WidgetSnapshot {
    /// The widget gallery's preview.
    static var sample: WidgetSnapshot {
        let start = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: .now)!
        var s = WidgetSnapshot()
        s.bricks = 42
        s.today = [
            Item(id: "1", title: "Maths worksheet", start: start, minutes: 30, done: true),
            Item(id: "2", title: "Free time", start: start.addingTimeInterval(1800), minutes: 30, free: true),
            Item(id: "3", title: "English essay", start: start.addingTimeInterval(3600), minutes: 45),
            Item(id: "4", title: "Revise chemistry", start: start.addingTimeInterval(6300), minutes: 40),
        ]
        return s
    }
}

// MARK: Buttons

/// "+15 min": the task runs longer and the ones after it shift later.
struct MoreTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "15 more minutes"
    @Parameter(title: "Task") var id: String
    init() {}
    init(id: String) { self.id = id }
    func perform() async throws -> some IntentResult {
        WidgetSnapshot.queue(.more, id: id)
        return .result()
    }
}

/// "Take a break": the task moves 15 min later. The break only counts as rest
/// if the phone really stays down (Screen Time).
struct BreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Take a break"
    @Parameter(title: "Task") var id: String
    init() {}
    init(id: String) { self.id = id }
    func perform() async throws -> some IntentResult {
        WidgetSnapshot.queue(.rest, id: id)
        return .result()
    }
}

// MARK: Widgets

/// A: house · C: house + next task with buttons · D: my day.
struct HouseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "house", provider: Provider()) { HouseView(entry: $0) }
            .configurationDisplayName("House")
            .description("Your house, bricks and what's next.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// B: today 3/7 · E, F, G: Lock Screen.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: Provider()) { TodayView(entry: $0) }
            .configurationDisplayName("Today")
            .description("Tasks done today and what's next.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// H: work vs rest, last 7 days.
struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "week", provider: Provider()) { WeekView(entry: $0) }
            .configurationDisplayName("Week")
            .description("Work and rest over the last 7 days.")
            .supportedFamilies([.systemMedium])
    }
}

// MARK: Views

private func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

private func duration(_ seconds: TimeInterval) -> String {
    let m = Int(seconds / 60)
    return m >= 60 ? (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m") : "\(m)m"
}

/// The house sprite on its sky, or the rest card when damage is hidden.
private struct HouseTile: View {
    let entry: Entry
    var body: some View {
        if entry.leadsWithRest {
            VStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill").font(.title).foregroundStyle(.yellow)
                Text("Rest \(duration(entry.rest)) of \(duration(House.restGoal))")
                    .font(.pixel(14).weight(.bold)).multilineTextAlignment(.center)
                Text("Take a break").font(.caption2)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(House.State.resting.sky)
        } else {
            Image("house." + entry.state.rawValue).pixelArt()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(entry.state.sky)
        }
    }
}

private struct Bricks: View {
    let value: Int
    var body: some View {
        HStack(spacing: 3) {
            Image("icon.brick").pixelArt().frame(height: 12)
            Text("\(value)").font(.pixel(14).weight(.bold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) bricks")
    }
}

struct HouseView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            case .systemLarge: large
            default: small
            }
        }
        .foregroundStyle(Color.ink)
        .containerBackground(Color.paper, for: .widget)
    }

    private var title: some View {
        Text(entry.leadsWithRest ? "Rest" : entry.state.title)
            .font(.pixel(16).weight(.bold))
            .foregroundStyle(entry.state == .calm || entry.state == .resting ? Color.grass : Color.brick)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HouseTile(entry: entry).pixelBox()
            HStack {
                title
                Spacer(minLength: 0)
                Bricks(value: entry.snap.bricks)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HouseTile(entry: entry).pixelBox()
                HStack { title; Spacer(minLength: 0); Bricks(value: entry.snap.bricks) }
            }
            .frame(maxWidth: 130)
            VStack(alignment: .leading, spacing: 6) {
                if let next = entry.next {
                    Text(next.start <= entry.date ? "NOW" : "NEXT").font(.pixel(12).weight(.bold)).foregroundStyle(.secondary)
                    Text(next.title).font(.subheadline.weight(.semibold)).lineLimit(2).privacySensitive()
                    Text("\(time(next.start))–\(time(next.end))").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        // Opens the app: bricks only come once "How did it go?" is answered.
                        Link(destination: URL(string: "focushouse://done/\(next.id)")!) { chip("Done", "checkmark") }
                        Button(intent: MoreTimeIntent(id: next.id)) { chip("+15", "clock") }
                        Button(intent: BreakIntent(id: next.id)) { chip("Break", "moon.zzz") }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("All done").font(.pixel(18).weight(.bold))
                    Text("Nothing else planned today.").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chip(_ label: String, _ icon: String) -> some View {
        Label(label, systemImage: icon).labelStyle(.titleOnly)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .pixelBox()
            .accessibilityLabel(label == "+15" ? "15 more minutes" : label)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                HouseTile(entry: entry).pixelBox().frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 6) {
                    HStack { title; Spacer(); Bricks(value: entry.snap.bricks) }
                    BrickMeter(title: "Rest", detail: "\(duration(entry.rest)) / \(duration(House.restGoal))",
                               filled: min(10, Int(entry.rest / House.restGoal * 10)), color: .blue)
                }
            }
            Text("MY DAY · \(entry.snap.doneCount)/\(entry.snap.tasks.count)").font(.pixel(14).weight(.bold))
            if entry.snap.today.isEmpty {
                Text("Nothing planned today.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(entry.snap.today.prefix(6), id: \.self) { item in
                HStack(spacing: 8) {
                    if item.free {
                        Image(systemName: "sun.max.fill").foregroundStyle(.orange).frame(width: 16)
                    } else {
                        Image(systemName: item.done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.done ? Color.grass : Color.ink).frame(width: 16)
                    }
                    Text(time(item.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(item.title).font(.caption.weight(.semibold)).strikethrough(item.done).lineLimit(1).privacySensitive()
                    Spacer(minLength: 0)
                }
                .padding(.vertical, item.free ? 3 : 0).padding(.horizontal, item.free ? 4 : 0)
                .background(item.free ? Color.gold : .clear)
            }
            Spacer(minLength: 0)
        }
    }
}

struct TodayView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    private var count: String { "\(entry.snap.doneCount)/\(entry.snap.tasks.count)" }
    private var nextTime: String? { entry.next.map { time($0.start) } }

    var body: some View {
        content.containerBackground(Color.paper, for: .widget)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.snap.doneCount), in: 0...Double(max(1, entry.snap.tasks.count))) {
                Text("Today")
            } currentValueLabel: {
                Text(count)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("\(count) done" + (nextTime.map { " · next \($0)" } ?? "")).font(.headline)
                if let next = entry.next {
                    Text(next.title).privacySensitive()   // counts only while locked
                } else {
                    Text("All done today")
                }
            }
        case .accessoryInline:
            Text("\(count) done" + (nextTime.map { " · next \($0)" } ?? ""))
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY").font(.pixel(14).weight(.bold)).foregroundStyle(.secondary)
                Text(count).font(.pixel(40).weight(.bold))
                Spacer(minLength: 0)
                if let next = entry.next {
                    Text("Next \(time(next.start))").font(.caption.weight(.bold))
                    Text(next.title).font(.caption).lineLimit(2).privacySensitive()
                } else {
                    Text("All done").font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WeekView: View {
    let entry: Entry

    var body: some View {
        let cal = Calendar.current
        let days = (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: entry.date))! }
        let work = days.map { Double(entry.snap.work[RestLog.key($0, cal)] ?? 0) * 60 }
        let rest = days.map { entry.log.seconds(on: $0, calendar: cal) }
        let top = max(House.restGoal, (work + rest).max() ?? 0)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("WEEK").font(.pixel(14).weight(.bold))
                Spacer()
                Label("Work", systemImage: "square.fill").foregroundStyle(Color.brick)
                Label("Rest", systemImage: "square.fill").foregroundStyle(.blue)
            }
            .font(.caption2)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days.indices, id: \.self) { i in
                    VStack(spacing: 3) {
                        HStack(alignment: .bottom, spacing: 2) {
                            bar(work[i] / top, .brick)
                            bar(rest[i] / top, .blue)
                        }
                        Text(days[i].formatted(.dateTime.weekday(.narrow))).font(.pixel(11))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(days[i].formatted(.dateTime.weekday(.wide))): \(duration(work[i])) work, \(duration(rest[i])) rest")
                }
            }
            if !entry.snap.insight.isEmpty {
                Text(entry.snap.insight).font(.caption2).lineLimit(2).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(Color.ink)
        .containerBackground(Color.paper, for: .widget)
    }

    private func bar(_ fraction: Double, _ color: Color) -> some View {
        Rectangle().fill(color).frame(maxWidth: .infinity)
            .frame(height: max(2, 70 * fraction))
            .frame(maxHeight: 70, alignment: .bottom)
    }
}
