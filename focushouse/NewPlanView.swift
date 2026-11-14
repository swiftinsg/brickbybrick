import SwiftUI
import SwiftData

struct NewPlanView: View {
    var initialInput = ""
    var onCreate: (Plan) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var mode = PlanMode.today
    @State private var input = ""
    @State private var materials = ""
    @State private var start = Date.nextFiveMinutes
    @State private var due = Calendar.current.date(byAdding: .day, value: 6, to: .now)!
    @State private var isWorking = false
    @State private var error: String?
    @AppStorage("askFreeTime") private var askFreeTime = false
    @AppStorage("autoAddToCalendar") private var autoAddToCalendar = false
    @AppStorage("bed") private var bed = 22 * 60
    @State private var freeFrom = Date.now
    @State private var freeUntil = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(PlanMode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(mode == .today ? "Input your messy to-do list into a timed plan for today."
                                        : "Break one big goal into steps spread over several days.")
                }

                Section(mode == .today ? "Dump your to-do list" : "What's your goal?") {
                    TextField(mode == .today ? "maths hw, read ch 4, tidy room…" : "Revise for my biology exam",
                              text: $input, axis: .vertical)
                        .lineLimit(4...10)
                }

                Section {
                    DatePicker("Start", selection: $start, in: Date.now.addingTimeInterval(-3600)...,
                               displayedComponents: [.date, .hourAndMinute])
                    if mode == .goal {
                        DatePicker("Finish by", selection: $due,
                                   in: start...Calendar.current.date(byAdding: .day, value: 29, to: start)!,
                                   displayedComponents: .date)
                        Text("\(days) day\(days == 1 ? "" : "s")").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("When")
                } footer: {
                    Text("Plan ahead by picking a later start, and times are fitted around your routine and calendar.")
                }

                if Planner.isAvailable {
                    Section {
                        TextField("Section 1: arenes, electrophilic substitution\nSection 2: other substituents…",
                                  text: $materials, axis: .vertical)
                            .lineLimit(3...12)
                    } header: {
                        Text("Study material (optional)")
                    } footer: {
                        Text("Paste your own notes or a syllabus, and each section becomes a task with subtasks. Label priorities in your list with words like \"urgent\" or \"can wait\".")
                    }
                }

                if askFreeTime {
                    Section("When are you free?") {
                        DatePicker("From", selection: $freeFrom, displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: $freeUntil, displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    VStack(spacing: 12) {
                        if Planner.isAvailable {
                            Button {
                                Task { await makePlan() }
                            } label: {
                                HStack(spacing: 8) {
                                    if isWorking { ProgressView() } else { Image(systemName: "sparkles") }
                                    Text(isWorking ? "Planning…" : "Make my plan")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .disabled(isWorking || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Button("Enter tasks myself", action: makeManual)
                            .disabled(isWorking)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                    else if !Planner.isAvailable {
                        Text("Apple Intelligence isn't available on this device, so you'll add tasks yourself.")
                    }
                }
            }
            .navigationTitle("New plan")
            .onAppear {
                if input.isEmpty { input = initialInput }
                freeFrom = start
                freeUntil = Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(bed * 60))
            }
            .onChange(of: start) { if due < start { due = start } }
            .task {
                await CalendarSync.requestAccess()
                await Reminders.requestAccess()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    /// Plan length in days: 1 for Today, start day through "Finish by" for Goal.
    private var days: Int {
        guard mode == .goal else { return 1 }
        let cal = Calendar.current
        return max(1, (cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: due)).day ?? 0) + 1)
    }

    private func makePlan() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let plan = newPlan(title: "", input: input, insert: false)
            let draft = try await Planner.draft(for: plan)
            plan.title = draft.title.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
            context.insert(plan)
            plan.replaceTasks(with: draft)
            if autoAddToCalendar { _ = try? await CalendarSync.add(plan) }
            onCreate(plan)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func makeManual() {
        let firstLine = input.split(separator: "\n").first.map(String.init) ?? ""
        onCreate(newPlan(title: firstLine.isEmpty ? "My plan" : firstLine, input: ""))
    }

    private func newPlan(title: String, input: String, insert: Bool = true) -> Plan {
        let plan = Plan(title: title, mode: mode, input: input, days: days, start: start)
        plan.materials = input.isEmpty ? "" : materials
        if askFreeTime {
            let minutes = { (d: Date) in Calendar.current.component(.hour, from: d) * 60 + Calendar.current.component(.minute, from: d) }
            plan.freeFrom = minutes(freeFrom)
            plan.freeUntil = minutes(freeUntil)
        }
        if insert { context.insert(plan) }
        return plan
    }
}

extension Plan {
    /// Swap in the model's tasks and schedule them.
    @MainActor func replaceTasks(with draft: DraftPlan) {
        replace(tasks, with: draft)
    }

    /// Re-plan with AI: rebuild only the unfinished tasks, starting now.
    @MainActor func replaceRemaining(with draft: DraftPlan) {
        let now = Date.nextFiveMinutes
        if now > start {
            let cal = Calendar.current
            let elapsed = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: now)).day ?? 0
            days = max(1, days - elapsed)
            start = now
        }
        replace(tasks.filter { !$0.done }, with: draft)
    }

    @MainActor private func replace(_ old: [PlanTask], with draft: DraftPlan) {
        CalendarSync.remove(old)
        Reminders.cancel(old)
        old.forEach { modelContext?.delete($0) }
        let kept = tasks.filter { t in !old.contains { $0 === t } }
        // Each subtask is a normal task, grouped under its item's title.
        let made = draft.items.flatMap { item in
            let steps = item.subtasks.isEmpty ? [DraftStep(title: item.title, minutes: item.minutes)] : item.subtasks
            return steps.map { step in
                let task = PlanTask(title: step.title, category: item.category, minutes: step.minutes,
                                    day: mode == .today ? 1 : min(max(item.day, 1), days), order: 0)
                task.priority = Planner.priorities.firstIndex(of: item.priority) ?? 1
                task.estimate = step.minutes
                task.parent = item.subtasks.isEmpty ? "" : item.title
                return task
            }
        }
        // Higher priority first within each day; otherwise keep the AI's order (stable sort).
        tasks = kept.sorted { $0.order < $1.order } + made.enumerated()
            .sorted { ($0.element.day, $0.element.priority, $0.offset) < ($1.element.day, $1.element.priority, $1.offset) }
            .map(\.element)
        for (i, task) in tasks.enumerated() { task.order = i }
        reflow()
    }
}
