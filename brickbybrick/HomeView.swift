import SwiftUI
import SwiftData

/// The main page: the house, how stressed and rested this week has been, the
/// next task, and the brick counter.
struct HomeView: View {
    @Query private var tasks: [PlanTask]
    @Query private var todos: [TodoItem]
    @AppStorage("restLog") private var restData = Data()
    @AppStorage("ratings") private var ratingData = Data()
    @State private var events: [(title: String, start: Date, minutes: Int)] = []
    @State private var showSettings = false

    var body: some View {
        let now = Date.now
        let cal = Calendar.current
        let log = RestLog.load(restData)
        let streak = House.streak(load, now: now)
        let restToday = log.seconds(on: now)
        let restedDays = (0...streak).filter {
            log.seconds(on: cal.date(byAdding: .day, value: -$0, to: now)!) >= House.restGoal
        }.count
        let state = House.state(streak: streak, restedDays: restedDays, restedToday: restToday >= House.restGoal)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image("house." + state.rawValue).pixelArt()
                        .background(state.sky)
                        .pixelBox()
                        .accessibilityLabel("Your house: \(state.title)")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.title.uppercased())
                            .font(.pixel(30, relativeTo: .title).weight(.bold))
                            .foregroundStyle(state == .calm || state == .resting ? Color.grass : Color.brick)
                        Text(state.message).font(.subheadline).foregroundStyle(.secondary)
                    }

                    BrickMeter(title: "Stress this week",
                               detail: streak == 0 ? "Low" : "\(streak) day\(streak == 1 ? "" : "s") in a row",
                               filled: min(10, Int((Double(streak) / 6 * 10).rounded())),
                               color: streak >= 4 ? .brick : streak >= 2 ? .orange : .grass)
                    BrickMeter(title: "Rest today",
                               detail: "\(Self.duration(restToday)) / \(Self.duration(House.restGoal)) away",
                               filled: min(10, Int(restToday / House.restGoal * 10)),
                               color: .blue)

                    if state != .calm && state != .resting { restCard }
                    if let next { nextCard(next) }
                }
                .padding()
            }
            .background(Color.paper)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "line.3.horizontal") { showSettings = true }
                }
                ToolbarItem(placement: .principal) {
                    Text("brickbybrick").font(.pixel(22, relativeTo: .headline).weight(.bold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // ponytail: just shows the count; opens Upgrades once the furniture shop exists.
                    HStack(spacing: 6) {
                        Image("icon.brick").pixelArt().frame(width: 22)
                        Text("\(bricks)").font(.pixel(20, relativeTo: .headline).weight(.bold))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(bricks) bricks")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task { await refresh() }
        }
    }

    private var restCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill").font(.title2).foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest to repair").font(.pixel(20, relativeTo: .headline).weight(.bold))
                Text("Put your phone down for \(Self.duration(House.restGoal)) today to rebuild a step.")
                    .font(.footnote)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .pixelBox(Color(red: 0.18, green: 0.21, blue: 0.35))
        .accessibilityElement(children: .combine)
    }

    private func nextCard(_ task: PlanTask) -> some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.snappy) { task.setDone(true) }
            } label: {
                Rectangle().strokeBorder(Color.ink, lineWidth: 3).frame(width: 26, height: 26)
            }
            .accessibilityLabel("Mark \(task.title) done")
            VStack(alignment: .leading, spacing: 2) {
                Text("Next: \(task.title)").font(.subheadline.weight(.semibold))
                let earns = House.bricks(minutes: task.estimate ?? task.minutes, rating(task.title, priority: task.priority, category: task.category).effort)
                Text("\(task.start!.formatted(date: .omitted, time: .shortened))–\(task.end!.formatted(date: .omitted, time: .shortened))" + (earns > 0 ? " · +\(earns) bricks" : ""))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .pixelBox()
    }

    /// The AI's rating for a title, or one from priority until it's rated;
    /// for plan tasks, scaled by the student's pace in that category.
    private func rating(_ title: String, priority: Int, category: String? = nil) -> Rating {
        let r = Ratings.load(ratingData)[Ratings.key(title)] ?? Rating(priority: priority)
        guard let category, let pace = Planner.pace().first(where: { $0.category == category }) else { return r }
        return r.personal(pace.ratio)
    }

    /// Stress per day from what the student does and attends: plan tasks at their
    /// time, Tasks-tab items on their due day, Calendar events.
    // ponytail: scans every task each render; fine for a student's few hundred.
    private var load: [(day: Date, minutes: Int)] {
        tasks.compactMap { t in t.start.map { ($0, House.stress(minutes: t.minutes, rating(t.title, priority: t.priority, category: t.category))) } }
            + todos.map { ($0.dueDate, House.stress(minutes: House.todoMinutes, rating($0.name, priority: $0.priority.level))) }
            + events.map { ($0.start, House.stress(minutes: $0.minutes, rating($0.title, priority: 1))) }
    }

    private var bricks: Int {
        House.total(
            tasks.filter(\.done).compactMap { t in
                (t.start ?? t.plan?.start).map { ($0, House.bricks(minutes: t.estimate ?? t.minutes, rating(t.title, priority: t.priority, category: t.category).effort)) }
            }
            + todos.filter(\.isDone).map { ($0.dueDate, rating($0.name, priority: $0.priority.level).effort == .easy ? 0 : House.todoBricks) })
    }

    /// Loads this fortnight's Calendar events, then has the AI rate anything new.
    private func refresh() async {
        let now = Date.now
        events = CalendarSync.attended(from: now.addingTimeInterval(-14 * 86_400), to: now.addingTimeInterval(86_400),
                                       excluding: Set(tasks.compactMap(\.eventID)))
        let rated = Ratings.load(ratingData)
        let titles = Set(tasks.map(\.title) + todos.map(\.name) + events.map(\.title))
            .filter { !$0.isEmpty && rated[Ratings.key($0)] == nil }
        await Ratings.rate(Array(titles))
    }

    private var next: PlanTask? {
        tasks.filter { !$0.done && ($0.end ?? .distantPast) > .now }
            .min { $0.start! < $1.start! }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        return m >= 60 ? (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m") : "\(m)m"
    }
}

private extension House.State {
    var title: String { rawValue.capitalized }

    var message: String {
        switch self {
        case .calm: "Stress is low. Keep it steady."
        case .stressed: "A few busy days in a row. Plan some rest."
        case .overloaded: "Carrying too much for too long. Take a real break."
        case .crumbling: "Too many high-stress days. Rest to repair."
        case .resting: "You rested today. Rebuilding one step."
        }
    }

    /// Sky behind the sprite, darker as stress builds.
    var sky: Color {
        switch self {
        case .calm: Color(red: 0.80, green: 0.91, blue: 1.0)
        case .stressed: Color(red: 0.89, green: 0.91, blue: 0.93)
        case .overloaded: Color(red: 0.73, green: 0.76, blue: 0.81)
        case .crumbling: Color(red: 0.60, green: 0.64, blue: 0.70)
        case .resting: Color(red: 0.18, green: 0.21, blue: 0.35)
        }
    }
}

private extension Priority {
    /// The plan tasks' scale: 0 high, 1 normal, 2 low.
    var level: Int { self == .high ? 0 : self == .low ? 2 : 1 }
}
