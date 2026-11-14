import SwiftUI

/// "How did it go?" after a task is ticked: time it took, how it felt (1–5) and
/// an optional note. Saving or skipping removes the task from the queue, which
/// closes the sheet, so it never dismisses itself.
struct CheckInSheet: View {
    let task: PlanTask
    @State private var minutes: Int
    @State private var feeling: Int?
    @State private var note = ""

    /// The time starts at what was recorded before, else the estimate.
    init(task: PlanTask) {
        self.task = task
        _minutes = State(initialValue: task.actual ?? task.minutes)
    }

    private static let feelings = [("😫", "Drained"), ("😕", "Tiring"), ("😐", "OK"), ("🙂", "Good"), ("😄", "Energised")]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("How did it go?")
                        .font(.pixel(26, relativeTo: .title))
                    Text(task.title).font(.headline)
                }

                Section {
                    Stepper(value: $minutes, in: 5...480, step: 5) {
                        LabeledContent("Time it took", value: hoursAndMinutes(minutes))
                    }
                } footer: {
                    Text("Planned \(hoursAndMinutes(task.estimate ?? task.minutes))")
                }

                Section("How did it feel?") {
                    HStack(spacing: 8) {
                        ForEach(Self.feelings.indices, id: \.self) { i in
                            let (emoji, caption) = Self.feelings[i]
                            let selected = feeling == i + 1
                            Button {
                                feeling = i + 1
                            } label: {
                                VStack(spacing: 4) {
                                    Text(emoji).font(.largeTitle)
                                    Text(caption).font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .overlay(Rectangle().strokeBorder(selected ? Color.ink : .clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(caption)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }

                Section {
                    TextField("Anything that helped or got in the way?", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Note (optional)")
                } footer: {
                    Text("Stays on your phone. Notes are deleted after 30 days.")
                }

                Section {
                    VStack(spacing: 12) {
                        Button {
                            CheckIn.shared.save(task, minutes: minutes, feeling: feeling!, note: note)
                        } label: {
                            Text("Save")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(feeling == nil)

                        Button("Skip (no bricks)") { CheckIn.shared.skip(task) }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Bricks are added once you answer.")
                }
            }
            .paperBackground()
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(feeling != nil)
    }
}

#Preview { CheckInSheet(task: PlanTask(title: "Maths homework", category: "school", minutes: 45, day: 0, order: 0)) }
