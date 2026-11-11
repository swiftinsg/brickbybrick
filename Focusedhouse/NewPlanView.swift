import SwiftUI
import SwiftData

struct NewPlanView: View {
    var onCreate: (Plan) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var mode = PlanMode.today
    @State private var input = ""
    @State private var materials = ""
    @State private var days = 7
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
                Picker("Mode", selection: $mode) {
                    ForEach(PlanMode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                Section(mode == .today ? "Dump your to-do list" : "What's your goal?") {
                    TextField(mode == .today ? "maths hw, read ch 4, tidy room…" : "Revise for my biology exam",
                              text: $input, axis: .vertical)
                        .lineLimit(4...10)
                    if mode == .goal {
                        Stepper("Over \(days) day\(days == 1 ? "" : "s")", value: $days, in: 1...30)
                    }
                }

                if Planner.isAvailable {
                    Section {
                        TextField("Section 1: arenes, electrophilic substitution\nSection 2: other substituents…",
                                  text: $materials, axis: .vertical)
                            .lineLimit(3...12)
                    } header: {
                        Text("Study material (optional)")
                    } footer: {
                        Text("Paste notes or a syllabus. Tasks are split by its sections. Mark priorities in your list with words like \"urgent\" or \"can wait\".")
                    }
                }

                if askFreeTime {
                    Section("When are you free?") {
                        DatePicker("From", selection: $freeFrom, displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: $freeUntil, displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    if Planner.isAvailable {
                        Button {
                            Task { await makePlan() }
                        } label: {
                            HStack {
                                Text("Make my plan")
                                if isWorking { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(isWorking || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Button("Enter tasks myself", action: makeManual).disabled(isWorking)
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                    else if !Planner.isAvailable {
                        Text("Apple Intelligence isn't available on this device, so you'll add tasks yourself.")
                    }
                }
            }
            .navigationTitle("New plan")
            .onAppear {
                freeFrom = start
                freeUntil = Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(bed * 60))
            }
            .task {
                await CalendarSync.requestAccess()
                await Reminders.requestAccess()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var start: Date { .nextFiveMinutes }

    private func makePlan() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let draft = try await Planner.draft(mode: mode, input: input, materials: materials, days: days)
            let plan = newPlan(title: draft.title, input: input)
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

    private func newPlan(title: String, input: String) -> Plan {
        let plan = Plan(title: title, mode: mode, input: input, days: days, start: start)
        plan.materials = input.isEmpty ? "" : materials
        if askFreeTime {
            let minutes = { (d: Date) in Calendar.current.component(.hour, from: d) * 60 + Calendar.current.component(.minute, from: d) }
            plan.freeFrom = minutes(freeFrom)
            plan.freeUntil = minutes(freeUntil)
        }
        context.insert(plan)
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
        let made = draft.tasks.map { t in
            let task = PlanTask(title: t.title, category: t.category, minutes: t.minutes,
                                day: mode == .today ? 1 : min(max(t.day, 1), days), order: 0)
            task.priority = Planner.priorities.firstIndex(of: t.priority) ?? 1
            task.section = t.section.trimmingCharacters(in: .whitespaces)
            return task
        }
        // Higher priority first within each day; otherwise keep the AI's order (stable sort).
        tasks = kept.sorted { $0.order < $1.order } + made.enumerated()
            .sorted { ($0.element.day, $0.element.priority, $0.offset) < ($1.element.day, $1.element.priority, $1.offset) }
            .map(\.element)
        for (i, task) in tasks.enumerated() { task.order = i }
        reflow()
    }
}
