import SwiftUI
import SwiftData

struct NewPlanView: View {
    var onCreate: (Plan) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var mode = PlanMode.today
    @State private var input = ""
    @State private var days = 7
    @State private var isWorking = false
    @State private var error: String?

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    /// Now, rounded up to the next 5 minutes.
    private var start: Date {
        let step: TimeInterval = 5 * 60
        return Date(timeIntervalSinceReferenceDate: (Date.now.timeIntervalSinceReferenceDate / step).rounded(.up) * step)
    }

    private func makePlan() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let draft = try await Planner.draft(mode: mode, input: input, days: days)
            let plan = Plan(title: draft.title, mode: mode, input: input, days: days, start: start)
            context.insert(plan)
            plan.replaceTasks(with: draft)
            onCreate(plan)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func makeManual() {
        let firstLine = input.split(separator: "\n").first.map(String.init) ?? ""
        let plan = Plan(title: firstLine.isEmpty ? "My plan" : firstLine, mode: mode,
                        input: "", days: days, start: start)
        context.insert(plan)
        onCreate(plan)
    }
}

extension Plan {
    /// Swap in the model's tasks and schedule them.
    func replaceTasks(with draft: DraftPlan) {
        tasks.forEach { modelContext?.delete($0) }
        tasks = draft.tasks.enumerated().map { i, t in
            PlanTask(title: t.title, category: t.category, minutes: t.minutes,
                     day: mode == .today ? 1 : min(max(t.day, 1), days), order: i)
        }
        reflow()
    }
}
