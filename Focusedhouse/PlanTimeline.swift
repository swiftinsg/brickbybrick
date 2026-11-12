import SwiftUI
import SwiftData

/// A day-by-day timeline of a plan. Press and hold a task, then drag it to a new
/// time (snaps to 5 minutes). It starts from there, and the student is asked
/// whether to pin it; nothing is pinned without asking.
struct PlanTimeline: View {
    @Bindable var plan: Plan
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var dragging: PersistentIdentifier?
    @State private var dragOffset: CGFloat = 0
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var askPin: PlanTask?   // just dragged: offer to lock it there
    /// Pinch to zoom; remembered between visits.
    @AppStorage("timelineHourHeight") private var savedHourHeight = 120.0
    @GestureState private var pinch: CGFloat = 1

    private var hourHeight: CGFloat { min(max(savedHourHeight * pinch, 70), 320) }
    private var perMinute: CGFloat { hourHeight / 60 }
    private let cal = Calendar.current
    private let gutter: CGFloat = 52       // hour labels column
    private let minBlock: CGFloat = 34     // shortest block that fits a line of text
    private let top: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            dayPicker
            Divider()
            ScrollView {
                let (from, to) = hourRange
                let frames = layout(from: from)
                ZStack(alignment: .topLeading) {
                    hourGrid(from: from, to: to)
                    ForEach(Array(busyToday.enumerated()), id: \.offset) { _, range in
                        busyBlock(range, from: from)
                    }
                    ForEach(tasksToday) { task in
                        if let frame = frames[task.persistentModelID] { taskBlock(task, frame: frame) }
                    }
                    nowLine(from: from)
                }
                // Pin content to the top: blocks are placed by offset from here.
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: max(CGFloat(to - from) * hourHeight, frames.values.map { $0.y + $0.height }.max() ?? 0) + top * 2,
                       alignment: .topLeading)
                .padding(.horizontal)
            }
            .scrollPosition($scroll)
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { savedHourHeight = min(max(savedHourHeight * $0.magnification, 70), 320) }
            )
        }
        .onAppear {
            day = days.contains(day) ? day : (days.first ?? day)
            jumpToFirstTask()
        }
        .onChange(of: day) { jumpToFirstTask() }
        .sensoryFeedback(.selection, trigger: dragging)
        .confirmationDialog(askPin.map { "Pin “\($0.title)” to \($0.start?.formatted(date: .omitted, time: .shortened) ?? "")?" } ?? "",
                            isPresented: Binding(get: { askPin != nil }, set: { if !$0 { askPin = nil } }),
                            titleVisibility: .visible, presenting: askPin) { task in
            Button("Pin here", systemImage: "pin") {
                task.pinned = task.start
                plan.reflow()
            }
            Button("Don't pin", role: .cancel) {}
        } message: { _ in
            Text("A pinned task never moves, even if earlier tasks run late. If you don't pin it, it starts here but can still be pushed later.")
        }
        .animation(.smooth, value: plan.ordered.map(\.start))
    }

    /// Open the day at its first unfinished task (or now, if that's later).
    private func jumpToFirstTask() {
        let first = tasksToday.first { !$0.done }?.start ?? tasksToday.first?.start
        guard var target = first else { scroll.scrollTo(edge: .top); return }
        if cal.isDateInToday(day), Date.now > target { target = .now }
        scroll.scrollTo(y: max(0, y(target, from: hourRange.0) - hourHeight / 2))
    }

    // MARK: Days

    /// The plan's days, plus any day a task overflowed onto.
    private var days: [Date] {
        let first = cal.startOfDay(for: plan.start)
        let planDays = (0..<max(plan.days, 1)).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
        let taskDays = plan.tasks.compactMap { $0.start.map(cal.startOfDay(for:)) }
        return Array(Set(planDays + taskDays)).sorted()
    }

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { d in
                    let selected = d == day
                    let count = plan.tasks.filter { $0.start.map { cal.isDate($0, inSameDayAs: d) } ?? false }.count
                    Button { withAnimation(.snappy) { day = d } } label: {
                        VStack(spacing: 2) {
                            Text(cal.isDateInToday(d) ? "Today" : d.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption.weight(.semibold))
                            Text(d.formatted(.dateTime.day())).font(.title3.weight(.bold)).monospacedDigit()
                            Text("\(count) task\(count == 1 ? "" : "s")").font(.caption2)
                                .opacity(0.8)
                        }
                        .frame(width: 64, height: 68)
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    // MARK: Layout

    private var tasksToday: [PlanTask] {
        plan.ordered.filter { $0.start.map { cal.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { $0.start! < $1.start! }
    }

    private var busyToday: [Range<Date>] {
        let own = Set(plan.tasks.compactMap(\.eventID))
        return CalendarSync.busy(from: day, days: 1, excluding: own).filter { cal.isDate($0.lowerBound, inSameDayAs: day) }
    }

    /// Hours shown: the routine's waking hours, stretched to fit any task.
    private var hourRange: (Int, Int) {
        let r = plan.routine
        let minute = { (d: Date) in Int(d.timeIntervalSince(day) / 60) }
        let starts = tasksToday.compactMap(\.start).map(minute)
        let ends = tasksToday.compactMap(\.end).map(minute)
        let lo = min(([r.wake] + starts).min()!, 24 * 60 - 60)
        let hi = max(([r.bed <= r.wake ? 24 * 60 : r.bed] + ends).max()!, lo + 60)
        return (lo / 60, min((hi + 59) / 60, 26))
    }

    private func y(_ date: Date, from hour: Int) -> CGFloat {
        CGFloat(date.timeIntervalSince(day) / 60 - Double(hour * 60)) * perMinute
    }

    /// Where each task block goes. Blocks sit at their start time, but a short
    /// block is drawn tall enough to read, and the next one moves down just
    /// enough not to cover it. Labels always show the real times.
    private func layout(from: Int) -> [PersistentIdentifier: (y: CGFloat, height: CGFloat)] {
        var out: [PersistentIdentifier: (y: CGFloat, height: CGFloat)] = [:]
        var bottom = -CGFloat.infinity
        for task in tasksToday {
            let top = max(y(task.start!, from: from), bottom + 3)
            let height = max(CGFloat(task.minutes) * perMinute - 3, minBlock)
            out[task.persistentModelID] = (top, height)
            bottom = top + height
        }
        return out
    }

    private func hourGrid(from: Int, to: Int) -> some View {
        ForEach(from...to, id: \.self) { h in
            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 8) {
                    Text(cal.date(byAdding: .hour, value: h, to: day)!.formatted(.dateTime.hour()))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: gutter - 8, alignment: .trailing)
                        .offset(y: -7)
                    Rectangle().fill(.separator).frame(height: 0.5)
                }
                // Half-hour line, only when there's room for it to help.
                if h < to, hourHeight >= 100 {
                    Rectangle().fill(.separator.opacity(0.5)).frame(height: 0.5)
                        .padding(.leading, gutter)
                        .offset(y: hourHeight / 2)
                }
            }
            .offset(y: CGFloat(h - from) * hourHeight + top)
        }
    }

    @ViewBuilder private func nowLine(from: Int) -> some View {
        if cal.isDateInToday(day) {
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Rectangle().fill(.red).frame(height: 1.5)
            }
            .padding(.leading, gutter - 4)
            .offset(y: y(.now, from: from) + top - 4)
            .accessibilityHidden(true)
        }
    }

    private func busyBlock(_ range: Range<Date>, from: Int) -> some View {
        let height = max(CGFloat(range.upperBound.timeIntervalSince(range.lowerBound) / 60) * perMinute - 3, 22)
        return Text("Busy")
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height, alignment: .topLeading)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .padding(.leading, gutter)
            .offset(y: y(range.lowerBound, from: from) + top)
    }

    // MARK: Tasks

    /// Calendar-style block: a tinted card with a solid bar on the left.
    private func taskBlock(_ task: PlanTask, frame: (y: CGFloat, height: CGFloat)) -> some View {
        let isDragging = dragging == task.persistentModelID
        let color: Color = task.done ? .gray : task.priority == 0 ? .red : .accentColor
        let roomy = frame.height >= 56
        return HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                if roomy, !task.parent.isEmpty {
                    Text(task.parent).font(.caption2.weight(.semibold)).foregroundStyle(color).lineLimit(1)
                }
                // Short blocks put the time beside the title so nothing is cut off.
                let line = roomy ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
                line {
                    HStack(spacing: 4) {
                        if task.pinned != nil { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange) }
                        if task.done { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                        Text(task.title)
                            .font(.subheadline.weight(.semibold))
                            .strikethrough(task.done)
                            .foregroundStyle(task.done ? .secondary : .primary)
                    }
                    Text(timeLabel(task, shiftedBy: isDragging ? snapped(dragOffset) : 0))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, roomy ? 6 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: roomy ? .topLeading : .leading)
        }
        .frame(height: frame.height)
        .background(color.opacity(isDragging ? 0.3 : 0.15))
        .background(.background)   // solid underneath, so hour lines don't show through
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(isDragging ? 0.2 : 0), radius: 8, y: 4)
        .scaleEffect(isDragging ? 1.02 : 1)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 10))
        .contextMenu { menu(for: task) }
        .gesture(task.done ? nil : move(task))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Press and hold, then drag to change the time")
        .padding(.leading, gutter)
        .offset(y: frame.y + top + (isDragging ? dragOffset : 0))
        .zIndex(isDragging ? 1 : 0)
    }

    /// Long-press then drag, so normal scrolling still works.
    private func move(_ task: PlanTask) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture())
            .onChanged { value in
                if case .second(true, let drag) = value {
                    dragging = task.persistentModelID
                    dragOffset = drag?.translation.height ?? 0
                }
            }
            .onEnded { _ in
                let minutes = snapped(dragOffset)
                if minutes != 0, let start = task.start {
                    plan.move(task, to: start.addingTimeInterval(TimeInterval(minutes * 60)))
                    askPin = task
                }
                dragging = nil
                dragOffset = 0
            }
    }

    private func snapped(_ offset: CGFloat) -> Int { Int((offset / perMinute / 5).rounded()) * 5 }

    private func timeLabel(_ task: PlanTask, shiftedBy minutes: Int) -> String {
        guard let start = task.start?.addingTimeInterval(TimeInterval(minutes * 60)) else { return "" }
        let end = start.addingTimeInterval(TimeInterval(task.minutes * 60))
        return "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder private func menu(for task: PlanTask) -> some View {
        if !task.done, let start = task.start {
            Menu("Move to day", systemImage: "calendar") {
                ForEach(days.filter { !cal.isDate($0, inSameDayAs: start) }, id: \.self) { d in
                    Button(d.formatted(.dateTime.weekday(.wide).day().month())) {
                        let time = start.timeIntervalSince(cal.startOfDay(for: start))
                        plan.move(task, to: d.addingTimeInterval(time))
                        day = d
                    }
                }
            }
        }
        if task.pinned == nil, !task.done, let start = task.start {
            Button("Pin to \(start.formatted(date: .omitted, time: .shortened))", systemImage: "pin") {
                task.pinned = start
                plan.reflow()
            }
        }
        if task.pinned != nil {
            Button("Unpin time", systemImage: "pin.slash") {
                task.pinned = nil
                plan.reflow()
            }
        }
    }
}
