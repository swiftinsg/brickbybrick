import SwiftUI
import SwiftData

struct PlanView: View {
    @Bindable var plan: Plan
    @State private var isWorking = false
    @State private var error: String?
    @State private var calendarMessage: String?
    @AppStorage("autoAddToCalendar") private var autoAddToCalendar = false
    @AppStorage("showTimeline") private var showTimeline = false
    @State private var editing: SubtaskEdit?

    /// What the subtask editor sheet opens with.
    private struct SubtaskEdit: Identifiable {
        let id = UUID()
        var name: String
        var tasks: [PlanTask]
    }

    var body: some View {
        Group {
            if showTimeline { PlanTimeline(plan: plan) } else { list }
        }
        .overlay {
            if plan.tasks.isEmpty {
                ContentUnavailableView {
                    Label("No tasks yet", systemImage: "plus.circle")
                } actions: {
                    Button("Add task", action: addTask)
                }
            }
        }
        .navigationTitle(showTimeline ? plan.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .paperBackground()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $showTimeline) {
                    Label("List", systemImage: "list.bullet").tag(false)
                    Label("Timeline", systemImage: "calendar.day.timeline.left").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            toolbarItems
        }
        .sheet(item: $editing) { SubtaskEditor(plan: plan, name: $0.name, subtasks: $0.tasks) }
        .task { plan.reflow() }   // pick up Calendar changes made since last time
    }

    private var list: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Plan name", text: $plan.title)
                        .font(.largeTitle.bold())
                        .submitLabel(.done)
                    if !plan.tasks.isEmpty {
                        Text(summary)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                        ProgressView(value: Double(doneCount), total: Double(plan.tasks.count))
                            .tint(.green)
                            .accessibilityLabel("Progress")
                    }
                    DatePicker("Starts", selection: $plan.start, displayedComponents: [.date, .hourAndMinute])
                        .font(.subheadline)
                        .onChange(of: plan.start) { plan.reflow() }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
            }

            ForEach(groups, id: \.day) { group in
                Section {
                    ForEach(blocks(group.tasks), id: \.tasks.first!.persistentModelID) { block in
                        if !block.parent.isEmpty {
                            // Counts every subtask of this parent, even ones on other days.
                            let subtasks = plan.ordered.filter { $0.parent == block.parent }
                            ParentRow(title: block.parent, tasks: subtasks,
                                      onChange: { plan.reflow() },
                                      onEdit: { editing = SubtaskEdit(name: block.parent, tasks: subtasks) },
                                      onDelete: { plan.delete(subtasks) })
                        }
                        ForEach(block.tasks) { task in
                            TaskRow(task: task, onChange: { plan.reflow() }, onPushBack: { plan.pushBack(task, by: $0) },
                                    onEdit: { editSubtasks(of: task) }, onDelete: { plan.delete([task]) })
                                .padding(.leading, block.parent.isEmpty ? 0 : 28)
                        }
                        .onDelete { plan.delete($0.map { block.tasks[$0] }) }
                        .onMove { from, to in
                            // Reorder within the block; moved tasks lose their drop time and pin,
                            // so the list order decides.
                            var day = block.tasks
                            day.move(fromOffsets: from, toOffset: to)
                            from.forEach { block.tasks[$0].notBefore = nil; block.tasks[$0].pinned = nil }
                            var list = plan.ordered
                            let first = list.firstIndex { $0 === block.tasks[0] } ?? 0
                            list.removeAll { t in block.tasks.contains { $0 === t } }
                            list.insert(contentsOf: day, at: first)
                            renumber(list)
                        }
                    }
                } header: {
                    HStack {
                        Text(dayTitle(group.day))
                        Spacer()
                        Text(hoursAndMinutes(group.tasks.reduce(0) { $0 + $1.minutes }))
                            .monospacedDigit()
                    }
                }
            }

            if let error {
                Text(error).foregroundStyle(.red)
            }

            calendarSection
        }
        .animation(.smooth, value: plan.ordered.map(\.start))
    }

    /// End of the plan: once the student is happy with it, add it to Calendar.
    /// It can also be done later from the plan's long-press menu on the home list.
    @ViewBuilder private var calendarSection: some View {
        if !plan.tasks.isEmpty {
            let upToDate = CalendarSync.isUpToDate(plan)
            Section {
                if upToDate {
                    Label("In Calendar", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                } else {
                    Button(isInCalendar ? "Update Calendar" : "Add to Calendar", systemImage: "calendar.badge.plus") {
                        Task { await addToCalendar() }
                    }
                }
            } footer: {
                if let calendarMessage {
                    Text(calendarMessage).foregroundStyle(.red)
                } else if !upToDate {
                    Text(isInCalendar ? "You changed the plan since adding it."
                                      : "Happy with your plan? Add it now, or later by long-pressing it on the Plans screen.")
                }
            }
        }
    }

    /// Tasks by the day they're scheduled on. `ordered` follows start time, so days are contiguous.
    private var groups: [(day: Date?, tasks: [PlanTask])] {
        var out: [(day: Date?, tasks: [PlanTask])] = []
        for task in plan.ordered {
            let day = task.start.map(Calendar.current.startOfDay(for:))
            if !out.isEmpty, out[out.count - 1].day == day {
                out[out.count - 1].tasks.append(task)
            } else {
                out.append((day, [task]))
            }
        }
        return out
    }

    /// Consecutive tasks with the same parent ("" = standalone tasks).
    private func blocks(_ tasks: [PlanTask]) -> [(parent: String, tasks: [PlanTask])] {
        var out: [(parent: String, tasks: [PlanTask])] = []
        for task in tasks {
            if !out.isEmpty, out[out.count - 1].parent == task.parent {
                out[out.count - 1].tasks.append(task)
            } else {
                out.append((task.parent, [task]))
            }
        }
        return out
    }

    private func dayTitle(_ day: Date?) -> String {
        guard let day else { return "Not scheduled" }
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }

    private var doneCount: Int { plan.tasks.filter(\.done).count }

    /// "2 of 5 done · 1 h 45 min left", or "All done".
    private var summary: String {
        let left = plan.tasks.filter { !$0.done }.reduce(0) { $0 + $1.minutes }
        if left == 0 { return "All done" }
        return "\(doneCount) of \(plan.tasks.count) done · \(hoursAndMinutes(left)) left"
    }

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        if Planner.isAvailable && (!plan.input.isEmpty || hasPending) {
            ToolbarItem {
                Menu {
                    if hasPending {
                        Button("Re-plan the rest with AI", systemImage: "sparkles") {
                            Task { await run { plan.replaceRemaining(with: try await Planner.replan(plan)) } }
                        }
                    }
                    if !plan.input.isEmpty {
                        Button("Try a different plan", systemImage: "arrow.clockwise") {
                            Task {
                                await run {
                                    // Show the AI the current plan so it makes a different one.
                                    plan.replaceTasks(with: try await Planner.draft(for: plan, previous: plan.ordered))
                                }
                            }
                        }
                    }
                } label: {
                    if isWorking { ProgressView() } else { Label("Re-plan", systemImage: "arrow.clockwise") }
                }
                .disabled(isWorking)
            }
        }
        if !showTimeline { ToolbarItem { EditButton() } }
        ToolbarItem { Button("Add task", systemImage: "plus", action: addTask) }
    }

    private var isInCalendar: Bool { plan.tasks.contains { $0.eventID != nil } }

    private func addToCalendar() async {
        do {
            _ = try await CalendarSync.add(plan)
            calendarMessage = nil   // the bar switches to "In Calendar"
        } catch {
            calendarMessage = error.localizedDescription
        }
    }

    /// Opens the subtask editor for a task's parent, or for a plain task on its own.
    private func editSubtasks(of task: PlanTask) {
        editing = task.parent.isEmpty
            ? SubtaskEdit(name: task.title, tasks: [task])
            : SubtaskEdit(name: task.parent, tasks: plan.ordered.filter { $0.parent == task.parent })
    }

    private func renumber(_ list: [PlanTask]) {
        for (i, task) in list.enumerated() { task.order = i }
        plan.reflow()
    }

    private func addTask() {
        let last = plan.ordered.last
        plan.tasks.append(PlanTask(title: "New task", category: "other", minutes: 30,
                                   day: last?.day ?? 1, order: (last?.order ?? -1) + 1))
        plan.reflow()
    }

    private var hasPending: Bool { plan.tasks.contains { !$0.done } }

    /// Runs an AI re-plan with a spinner, then re-adds to Calendar if auto-add is on.
    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await work()
            if autoAddToCalendar { await addToCalendar() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ParentRow: View {
    let title: String
    let tasks: [PlanTask]
    var onChange: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var allDone: Bool { tasks.allSatisfy(\.done) }
    private var doneCount: Int { tasks.filter(\.done).count }
    private var total: Int { tasks.reduce(0) { $0 + $1.minutes } }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                withAnimation(.snappy) {
                    let newValue = !allDone
                    tasks.forEach { $0.setDone(newValue) }
                }
                onChange()   // re-arm reminders
            } label: {
                Image(systemName: allDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(allDone ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: allDone) { _, done in done }
            .accessibilityLabel(allDone ? "Mark all not done" : "Mark all done")

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .strikethrough(allDone)
                    .foregroundStyle(allDone ? .secondary : .primary)
                Text("\(doneCount) of \(tasks.count) subtasks · \(hoursAndMinutes(total))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Edit subtasks", systemImage: "list.bullet.indent", action: onEdit)
            Button("Delete with subtasks", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .moveDisabled(true)
        .accessibilityAction(named: "Edit subtasks", onEdit)
    }
}

private struct TaskRow: View {
    @Bindable var task: PlanTask
    var onChange: () -> Void
    var onPushBack: (Int) -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    private static let durations = [5, 10, 15, 20, 25, 30, 40, 45, 50, 60, 75, 90, 105, 120, 150, 180, 210, 240]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                withAnimation(.snappy) { task.setDone(!task.done) }
                onChange()   // re-arm reminders; a finished task keeps its time
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.done ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: task.done) { _, done in done }
            .accessibilityLabel(task.done ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if task.priority == 0 {
                        Image(systemName: "exclamationmark")
                            .font(.subheadline.weight(.heavy)).foregroundStyle(.red)
                            .accessibilityLabel("High priority")
                    } else if task.priority == 2 {
                        Image(systemName: "arrow.down")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .accessibilityLabel("Low priority")
                    }
                    TextField("Task", text: $task.title)
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? .secondary : .primary)
                    if task.pinned != nil {
                        Image(systemName: "pin.fill")
                            .font(.caption).foregroundStyle(.orange)
                            .accessibilityLabel("Fixed time")
                    }
                }
                if let start = task.start, let end = task.end {
                    Text((start..<end).formatted(.interval.hour().minute()))
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
            }

            Menu {
                Picker("Duration", selection: $task.minutes) {
                    ForEach(Set(Self.durations + [task.minutes]).sorted(), id: \.self) {
                        Text(hoursAndMinutes($0)).tag($0)
                    }
                }
            } label: {
                Text(hoursAndMinutes(task.minutes))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.fill.tertiary, in: .capsule)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Duration, \(hoursAndMinutes(task.minutes))")
            .onChange(of: task.minutes) { onChange() }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(task.parent.isEmpty ? "Add subtasks" : "Edit subtasks", systemImage: "list.bullet.indent", action: onEdit)
            Picker("Priority", selection: $task.priority) {
                Label("High", systemImage: "exclamationmark").tag(0)
                Label("Normal", systemImage: "minus").tag(1)
                Label("Low", systemImage: "arrow.down").tag(2)
            }
            .pickerStyle(.menu)
            if !task.done {
                Section("Need more time?") {
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button("+\(minutes) min", systemImage: "clock.arrow.circlepath") { onPushBack(minutes) }
                    }
                }
            }
            if task.pinned == nil, !task.done, let start = task.start {
                Button("Pin to \(start.formatted(date: .omitted, time: .shortened))", systemImage: "pin") {
                    task.pinned = start
                    onChange()
                }
            }
            if task.pinned != nil {
                Button("Unpin time", systemImage: "pin.slash") {
                    task.pinned = nil
                    onChange()
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        // A custom swipe turns off .onDelete's swipe, so Delete is added back explicitly.
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .swipeActions(edge: .leading) {
            if !task.done {
                Button("+15 min", systemImage: "clock.arrow.circlepath") { onPushBack(15) }
                    .tint(.orange)
            }
        }
    }
}

/// "45 min", "1 h", "1 h 30 min".
func hoursAndMinutes(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) min" }
    return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
}
