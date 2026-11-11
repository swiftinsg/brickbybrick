import SwiftUI
import SwiftData

struct PlanView: View {
    @Bindable var plan: Plan
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        List {
            TextField("List name", text: $plan.title)
                .font(.largeTitle.bold())
                .submitLabel(.done)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
                .listRowSeparator(.hidden)

            ForEach(plan.ordered) { task in
                TaskRow(task: task) { plan.reflow() }
            }
            .onDelete { offsets in
                let list = plan.ordered
                offsets.map { list[$0] }.forEach { plan.modelContext?.delete($0) }
                renumber(list.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
            }
            .onMove { from, to in
                var list = plan.ordered
                list.move(fromOffsets: from, toOffset: to)
                // A moved task joins the day of the task now above it.
                if let moved = from.first.map({ plan.ordered[$0] }),
                   let i = list.firstIndex(where: { $0 === moved }) {
                    moved.day = i == 0 ? 1 : list[i - 1].day
                }
                renumber(list)
            }

            if let error {
                Text(error).foregroundStyle(.red)
            }
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if Planner.isAvailable && !plan.input.isEmpty {
                ToolbarItem {
                    Button {
                        Task { await tryAgain() }
                    } label: {
                        if isWorking { ProgressView() } else { Label("Try again", systemImage: "arrow.clockwise") }
                    }
                    .disabled(isWorking)
                }
            }
            ToolbarItem { EditButton() }
            ToolbarItem { Button("Add task", systemImage: "plus", action: addTask) }
        }
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

    private func tryAgain() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let draft = try await Planner.draft(mode: plan.mode, input: plan.input, days: plan.days)
            plan.replaceTasks(with: draft)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct TaskRow: View {
    @Bindable var task: PlanTask
    var onChange: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Button {
                task.done.toggle()
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.done ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 4) {
                TextField("Task", text: $task.title)
                    .strikethrough(task.done)
                if let start = task.start, let end = task.end {
                    Text("\(start.formatted(.dateTime.weekday().day().month())) · \(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Stepper("\(task.minutes) min", value: $task.minutes, in: 5...240, step: 5)
                    .font(.subheadline)
                    .onChange(of: task.minutes) { onChange() }
            }
        }
    }
}
