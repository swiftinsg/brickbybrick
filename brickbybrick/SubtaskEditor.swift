import SwiftUI
import SwiftData

/// Edit or write your own subtasks for one task. Saved breakdowns teach the AI
/// to suggest similar subtasks next time.
struct SubtaskEditor: View {
    let plan: Plan
    @State var name: String          // the parent task's name
    @State var subtasks: [PlanTask]  // current subtasks (or the single plain task)
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: PersistentIdentifier?

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Task name", text: $name)
                        .font(.headline)
                }

                Section {
                    ForEach(subtasks) { task in
                        SubtaskField(task: task, focused: $focused)
                    }
                    .onDelete { offsets in
                        let gone = offsets.map { subtasks[$0] }
                        subtasks.remove(atOffsets: offsets)
                        plan.delete(gone)
                    }
                    .onMove { subtasks.move(fromOffsets: $0, toOffset: $1) }
                    .deleteDisabled(subtasks.count == 1)   // keep one, so "Add subtask" has a place

                    Button("Add subtask", systemImage: "plus.circle.fill") { add() }
                } header: {
                    Text("Subtasks")
                } footer: {
                    Text("Your subtasks are saved, so next time the AI suggests similar ones for similar tasks.")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationTitle("Subtasks")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear(perform: save)   // Done and swipe-to-close both save
    }

    private func add() {
        guard let last = subtasks.last else { return }
        let task = plan.addSubtask(after: last)
        subtasks.append(task)
        focused = task.persistentModelID
    }

    private func save() {
        // Put the subtasks back, in the editor's order, where the first of them was.
        let all = plan.ordered
        var list = all.filter { t in !subtasks.contains { $0 === t } }
        let at = all.firstIndex { t in subtasks.contains { $0 === t } } ?? list.count
        list.insert(contentsOf: subtasks, at: min(at, list.count))
        for (i, task) in list.enumerated() { task.order = i }
        plan.saveSubtasks(subtasks, name: name)
    }
}

/// One subtask row: done toggle, title field, duration picker.
private struct SubtaskField: View {
    @Bindable var task: PlanTask
    var focused: FocusState<PersistentIdentifier?>.Binding
    private static let durations = [5, 10, 15, 20, 25, 30, 40, 45, 50, 60, 75, 90, 105, 120]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.done ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            TextField("Subtask", text: $task.title)
                .focused(focused, equals: task.persistentModelID)
                .submitLabel(.next)

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
        }
    }
}
