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
    @State private var showInside = false
    @State private var doorStep = 0        // 0 shut, 1 ajar, 2 open
    @Namespace private var door
    @AppStorage("owned") private var ownedRaw = ""
    @AppStorage("insight") private var insight = ""
    @AppStorage("seenOnboarding") private var seenOnboarding = false
    @AppStorage("homeTourDone") private var tourDone = false

    var body: some View {
        let now = Date.now
        let log = RestLog.load(restData)
        let status = self.status
        let streak = status.streak
        let restToday = log.seconds(on: now)
        let state = House.state(streak: streak, log: log, now: now)

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
                    .overlay {
                        // the door (sprite pixels 12–17 × 22–29) is a button into the house
                        GeometryReader { geo in
                            let px = geo.size.width / 32
                            Canvas { ctx, _ in Self.drawDoor(ctx, px: px, step: doorStep) }
                                .allowsHitTesting(false)
                            Button { enter() } label: { Color.clear.contentShape(Rectangle()) }
                                .frame(width: 6 * px, height: 8 * px)
                                .matchedTransitionSource(id: "door", in: door)
                                .position(x: 15 * px, y: 26 * px)
                        }
                    }
                    .sensoryFeedback(trigger: doorStep) { _, step in
                        // latch clicks, then the door swings open
                        switch step {
                        case 1: .impact(flexibility: .soft, intensity: 0.6)
                        case 2: .impact(weight: .medium)
                        default: nil
                        }
                    }
                    .pixelBox()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Your house: \(state.title)")
                    .accessibilityHint("Double-tap to go inside")
                    .accessibilityAction { enter() }
                    .tour(.house)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.title)
                            .font(.pixel(30, relativeTo: .title))
                            .foregroundStyle(state == .calm || state == .resting ? Color.grass : Color.brick)
                        Text(state.message).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .tour(.status)

                    BrickMeter(title: "Stress this week",
                               detail: streak == 0 ? "Low" : "\(streak) day\(streak == 1 ? "" : "s") in a row",
                               filled: min(10, Int((Double(streak) / 6 * 10).rounded())),
                               color: streak >= 4 ? .brick : streak >= 2 ? .orange : .grass)
                        .tour(.stress)
                    BrickMeter(title: "Rest today",
                               detail: "\(Self.duration(restToday)) / \(Self.duration(House.restGoal)) away",
                               filled: min(10, Int(restToday / House.restGoal * 10)),
                               color: .blue)
                        .tour(.rest)

                    if state != .calm && state != .resting { restCard }
                    if let next { nextCard(next, status).tour(.next) }
                    if !insight.isEmpty { insightCard }
                }
                .padding()
            }
            .background(Color.paper)
            .homeTour(isOn: Binding(get: { seenOnboarding && !tourDone }, set: { tourDone = !$0 }))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
                ToolbarItem(placement: .principal) {
                    Text("focushouse").font(.pixel(22, relativeTo: .headline).weight(.bold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    BrickCount(value: max(0, status.earned - Shop.spent(Shop.owned(ownedRaw))))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(isPresented: $showInside, onDismiss: { doorStep = 0 }) {
                InsideView(earned: status.earned)
                    .navigationTransition(.zoom(sourceID: "door", in: door))   // the whole screen grows out of the doorway
            }
            .task { await refresh() }
        }
    }

    /// Opens the door in two pixel frames, then the room zooms out of the doorway
    /// full screen (the system zoom transition, which respects Reduce Motion).
    private func enter() {
        guard doorStep == 0 else { return }
        Task { @MainActor in
            doorStep = 1
            try? await Task.sleep(for: .milliseconds(120))
            doorStep = 2
            try? await Task.sleep(for: .milliseconds(180))
            showInside = true
        }
    }

    /// The door's open frames, drawn over the sprite's door (columns 14–15, rows 24–27).
    static func drawDoor(_ ctx: GraphicsContext, px: CGFloat, step: Int) {
        guard step > 0 else { return }
        func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: Color) {
            ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: CGFloat(w) * px + 0.5, height: CGFloat(h) * px + 0.5)), with: .color(c))
        }
        let light = Color(red: 0.96, green: 0.79, blue: 0.36)     // warm room light (palette k)
        let leaf = Color(red: 0.42, green: 0.27, blue: 0.15)      // door edge (palette d)
        if step == 1 {                                            // ajar: a sliver of light
            fill(15, 24, 1, 4, light)
        } else {                                                  // open: leaf swung in, light spills out
            fill(14, 24, 1, 4, leaf)
            fill(15, 24, 1, 4, light)
            fill(14, 28, 2, 1, light.opacity(0.5))
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

    /// The AI's weekly insight from the student's check-ins.
    private var insightCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lightbulb.fill").font(.title2).foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your week").font(.pixel(20, relativeTo: .headline).weight(.bold))
                Text(insight).font(.footnote)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .pixelBox()
        .accessibilityElement(children: .combine)
    }

    private func nextCard(_ task: PlanTask, _ status: HouseStatus) -> some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.snappy) { CheckIn.shared.tick(task) }
            } label: {
                Rectangle().strokeBorder(Color.ink, lineWidth: 3).frame(width: 26, height: 26)
            }
            .accessibilityLabel("Mark \(task.title) done")
            VStack(alignment: .leading, spacing: 2) {
                Text("Next: \(task.title)").font(.subheadline.weight(.semibold))
                let earns = House.bricks(minutes: task.estimate ?? task.minutes, status.rating(task.title, priority: task.priority, category: task.category).effort)
                Text("\(task.start!.formatted(date: .omitted, time: .shortened))–\(task.end!.formatted(date: .omitted, time: .shortened))" + (earns > 0 ? " · +\(earns) bricks" : ""))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .pixelBox()
    }

    private var status: HouseStatus {
        HouseStatus(tasks: tasks, todos: todos, events: events, ratings: Ratings.load(ratingData))
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
        await Reflections.refreshInsight(tasks.filter { $0.checkIn == PlanTask.CheckInState.answered.rawValue })
    }

    private var next: PlanTask? {
        tasks.filter { !$0.done && ($0.end ?? .distantPast) > .now }
            .min { $0.start! < $1.start! }
    }

    nonisolated static func duration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        return m >= 60 ? (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m") : "\(m)m"
    }
}

/// Inside the house, through the front door: the room with the student's
/// furniture, and a way to the shop to decorate.
struct InsideView: View {
    let earned: Int
    @State private var showUpgrades = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                RoomView()
                    .frame(maxWidth: .infinity)
                Text("Hold and drag your furniture to move it around. Up to \(Shop.roomCap) things fit inside.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { showUpgrades = true } label: {
                    Label("Decorate with bricks", systemImage: "paintbrush.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .pixelBox(Color.gold)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding()
            .foregroundStyle(Color.ink)
            .background(Color.paper)
            .pixelTitle("Inside")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Leave", systemImage: "door.left.hand.open") { dismiss() }
                }
            }
            .sheet(isPresented: $showUpgrades) { UpgradesView(earned: earned) }
        }
    }
}

/// The house sprite with a little life on top, in the sprite's own 32×32 pixels:
/// chimney smoke when calm, grey smoke when stressed, rain when overloaded,
/// rain and falling bricks when crumbling, floating Z's and stars when resting.
/// Off with Reduce Motion.
struct HouseScene: View {
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
