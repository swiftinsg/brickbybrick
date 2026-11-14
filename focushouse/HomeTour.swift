import SwiftUI

/// First-visit tour of Home: dims the screen, spotlights one part at a time and
/// explains it. Toolbar and tab bar sit outside the overlay, so those steps
/// point at them with an arrow instead of a spotlight.
enum TourStep: Int, CaseIterable {
    case house, status, stress, rest, next, settings, bricks, tabs

    var title: String {
        switch self {
        case .house: "This house is you"
        case .status: "How you're doing"
        case .stress: "Stress this week"
        case .rest: "Rest today"
        case .next: "Your next task"
        case .settings: "Settings"
        case .bricks: "Bricks"
        case .tabs: "Schedule · Tasks · Calendar"
        }
    }

    var text: String {
        switch self {
        case .house: "It mirrors your mental health. Stressful days in a row wear it down, and rest builds it back up. Look after yourself and it stays standing."
        case .status: "Calm, Stressed, Overloaded or Crumbling, based on how many hard days you've had in a row. Resting means you rested enough today to repair a step."
        case .stress: "Fills a little for each stressful day in a row. Easy tasks don't count, and lessons and exams count half."
        case .rest: "Time with your phone down while you're awake. Reach \(HomeView.duration(House.restGoal)) in a day to repair your house one step."
        case .next: "Tick the box when you finish to earn bricks, then say how it went so future plans fit your pace."
        case .settings: "Tap the gear for your routine, school hours, daily work limit and how rest is counted."
        case .bricks: "Earned by finishing tasks. Tap the counter to buy furniture. Bricks decorate, but only rest repairs."
        case .tabs: "Schedule: tap + to turn a goal or to-do list into a timed plan.\nTasks: quick to-dos with due dates.\nCalendar: your month at a glance."
        }
    }

    /// Where the arrow points when there's nothing to spotlight.
    var arrow: (symbol: String, edge: Alignment)? {
        switch self {
        case .settings: ("arrow.up.left", .topLeading)
        case .bricks: ("arrow.up.right", .topTrailing)
        case .tabs: ("arrow.down", .bottom)
        default: nil
        }
    }
}

struct TourAnchors: PreferenceKey {
    static let defaultValue: [TourStep: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourStep: Anchor<CGRect>], nextValue: () -> [TourStep: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks this view as the spotlight for `step`.
    func tour(_ step: TourStep) -> some View {
        anchorPreference(key: TourAnchors.self, value: .bounds) { [step: $0] }
    }

    /// Runs the Home tour over this view until it's finished or skipped.
    func homeTour(isOn: Binding<Bool>) -> some View {
        overlayPreferenceValue(TourAnchors.self) { anchors in
            if isOn.wrappedValue {
                GeometryReader { proxy in
                    TourOverlay(rects: anchors.mapValues { proxy[$0] }, size: proxy.size) { isOn.wrappedValue = false }
                }
            }
        }
    }
}

private struct TourOverlay: View {
    let rects: [TourStep: CGRect]
    let size: CGSize
    let finish: () -> Void
    @State private var index = 0

    /// Spotlight steps whose view isn't on screen (e.g. no next task) are skipped.
    private var steps: [TourStep] { TourStep.allCases.filter { $0.arrow != nil || rects[$0] != nil } }

    var body: some View {
        let step = steps[min(index, steps.count - 1)]
        let hole = rects[step]?.insetBy(dx: -6, dy: -6)
        let last = index >= steps.count - 1

        ZStack {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                if let hole { p.addRect(hole) }
            }
            .fill(.black.opacity(0.65), style: FillStyle(eoFill: true))
            .contentShape(Rectangle())
            .onTapGesture(perform: advance)

            if let hole {
                Rectangle().strokeBorder(Color.gold, lineWidth: 3)
                    .frame(width: hole.width, height: hole.height)
                    .position(x: hole.midX, y: hole.midY)
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let arrow = step.arrow, arrow.edge != .bottom { arrowImage(arrow.symbol, arrow.edge) }
                VStack(alignment: .leading, spacing: 8) {
                    Text(step.title).font(.pixel(22, relativeTo: .headline).weight(.bold))
                    Text(step.text).font(.subheadline)
                    HStack {
                        Text("\(index + 1) of \(steps.count)").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        if !last { Button("Skip", action: finish).font(.subheadline) }
                        Button(last ? "Done" : "Next", action: advance)
                            .font(.pixel(18, relativeTo: .headline).weight(.bold))
                            .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 0))
                    }
                }
                .padding()
                .pixelBox()
                if let arrow = step.arrow, arrow.edge == .bottom { arrowImage(arrow.symbol, arrow.edge) }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cardAlignment(step, hole))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .animation(.easeInOut(duration: 0.25), value: index)
        .tint(.brick)
    }

    private func arrowImage(_ symbol: String, _ edge: Alignment) -> some View {
        Image(systemName: symbol).font(.largeTitle.weight(.bold)).foregroundStyle(Color.gold)
            .frame(maxWidth: .infinity, alignment: edge == .topTrailing ? .trailing : edge == .bottom ? .center : .leading)
            .accessibilityHidden(true)
    }

    /// Card goes on the other half of the screen from the spotlight.
    private func cardAlignment(_ step: TourStep, _ hole: CGRect?) -> Alignment {
        if let hole { return hole.midY > size.height / 2 ? .top : .bottom }
        return step.arrow?.edge == .bottom ? .bottom : .top
    }

    private func advance() {
        if index >= steps.count - 1 { finish() } else { index += 1 }
    }
}
