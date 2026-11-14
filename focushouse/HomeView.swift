import SwiftUI
import SwiftData

/// The main page: the house, how stressed and rested this week has been, the
/// next task, and the brick counter.
struct HomeView: View {
    @Query private var tasks: [PlanTask]
    @Query private var todos: [TodoItem]
    @AppStorage("restLog", store: RestLog.defaults) private var restData = Data()
    @AppStorage("ratings") private var ratingData = Data()
    @State private var events: [(title: String, start: Date, minutes: Int)] = []
    @State private var showSettings = false
    @State private var showUpgrades = false
    @AppStorage("owned") private var ownedRaw = ""

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
                    ZStack {
                        HouseScene(state: state)
                            .background(state.sky)
                            .id(state)
                            .transition(.opacity)   // crossfade when the house changes state
                    }
                    .animation(.easeInOut(duration: 0.8), value: state)
                    .pixelBox()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Your house: \(state.title)")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.title)
                            .font(.pixel(30, relativeTo: .title))
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
                    Text("focushouse").font(.pixel(22, relativeTo: .headline).weight(.bold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showUpgrades = true } label: {
                        BrickCount(value: max(0, bricks - Shop.spent(Shop.owned(ownedRaw))))
                    }
                    .accessibilityHint("Opens Upgrades")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showUpgrades) { UpgradesView(earned: bricks) }
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

/// The house sprite with a little life on top, in the sprite's own 32×32 pixels:
/// chimney smoke when calm, grey smoke when stressed, rain when overloaded,
/// rain and falling bricks when crumbling, floating Z's and stars when resting.
/// Off with Reduce Motion.
private struct HouseScene: View {
    let state: House.State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image("house." + state.rawValue).pixelArt()
            .overlay {
                if !reduceMotion {
                    // 12 fps on purpose: smooth motion looks wrong on pixel art.
                    TimelineView(.animation(minimumInterval: 1 / 12)) { timeline in
                        Canvas { ctx, size in
                            Self.draw(state, t: timeline.date.timeIntervalSinceReferenceDate, ctx: ctx, px: size.width / 32)
                        }
                    }
                    .clipped()
                    .allowsHitTesting(false)
                }
            }
    }

    static func draw(_ state: House.State, t: Double, ctx: GraphicsContext, px: CGFloat) {
        /// One sprite pixel (or a w×h block), snapped to the grid.
        func dot(_ x: Double, _ y: Double, _ color: Color, w: Double = 1, h: Double = 1) {
            ctx.fill(Path(CGRect(x: x.rounded() * px, y: y.rounded() * px, width: w * px, height: h * px)), with: .color(color))
        }
        /// 0→1 every `period` seconds, offset per particle.
        func phase(_ period: Double, _ offset: Double) -> Double {
            (t / period + offset).truncatingRemainder(dividingBy: 1)
        }
        func smoke(_ color: Color, period: Double) {
            for i in 0..<3 {
                let p = phase(period, Double(i) / 3)
                let size: Double = p < 0.5 ? 2 : 1
                dot(16 + p * 4 + sin(p * 6), 3 - p * 5, color.opacity(1 - p), w: size, h: size)
            }
        }
        func rain(_ drops: Int) {
            for i in 0..<drops {
                // 37 is coprime with 32, so every drop gets its own column
                dot(Double((i * 37 + 5) % 32), 4 + phase(0.6, Double(i) * 0.137) * 25,
                    Color(red: 0.62, green: 0.71, blue: 0.85).opacity(0.85), h: 2)
            }
        }

        switch state {
        case .calm:
            smoke(.white, period: 3)
        case .stressed:
            smoke(Color(white: 0.55), period: 1.8)
        case .overloaded:
            rain(8)
        case .crumbling:
            rain(16)
            for (i, x) in [6.0, 23].enumerated() {   // bricks slipping off the eaves
                let p = phase(2.4, Double(i) / 2)
                if p < 0.5 { dot(x, 16 + 12 * (p * 2) * (p * 2), Color(red: 0.70, green: 0.29, blue: 0.20), w: 2) }
            }
        case .resting:
            for (i, (x, y)) in [(3.0, 3.0), (9, 1), (13, 6), (30, 9), (19, 1)].enumerated() {
                dot(x, y, Color(red: 1, green: 0.95, blue: 0.7).opacity(0.3 + 0.7 * max(0, sin(t * 2 + Double(i) * 1.7))))
            }
            for i in 0..<2 {
                let p = phase(4, Double(i) / 2)
                let (x, y, c) = (25 + p * 3, 5 - p * 6, Color.white.opacity(1 - p))
                dot(x, y, c, w: 3); dot(x + 1, y + 1, c); dot(x, y + 2, c, w: 3)   // a 3×3 z
            }
        }
    }
}
