import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("wake") private var wake = 420
    @AppStorage("bed") private var bed = 1320
    @AppStorage("schoolStart") private var schoolStart = 480
    @AppStorage("schoolEnd") private var schoolEnd = 900
    @AppStorage("hasSchool") private var hasSchool = true
    @AppStorage("useRoutine") private var useRoutine = true
    @AppStorage("autoAddToCalendar") private var autoAddToCalendar = false
    @AppStorage("askFreeTime") private var askFreeTime = false
    @State private var pace = Planner.pace()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Follow a routine", isOn: $useRoutine.animation())
                    if useRoutine {
                        DatePicker("Wake up", selection: minutesBinding($wake), displayedComponents: .hourAndMinute)
                        DatePicker("Bedtime", selection: minutesBinding($bed), displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("My routine")
                } footer: {
                    Text(useRoutine ? "Tasks are only scheduled between wake-up and bedtime\(hasSchool ? ", outside school hours" : "")."
                                    : "No routine (e.g. holidays): tasks can go anywhere from 8 AM to 11 PM, around your Calendar events.")
                }
                if useRoutine {
                    Section {
                        Toggle("School on weekdays", isOn: $hasSchool.animation())
                        if hasSchool {
                            DatePicker("School starts", selection: minutesBinding($schoolStart), displayedComponents: .hourAndMinute)
                            DatePicker("School ends", selection: minutesBinding($schoolEnd), displayedComponents: .hourAndMinute)
                        }
                        NavigationLink {
                            TimetableView()
                        } label: {
                            Label("Add timetable to Calendar", systemImage: "tablecells")
                        }
                    } header: {
                        Text("School")
                    } footer: {
                        Text("Turn off for school holidays. Add your timetable from a photo or PDF so plans also avoid lessons that run late, like CCAs.")
                    }
                }
                Section {
                    Toggle("Add new plans to Calendar automatically", isOn: $autoAddToCalendar)
                    Toggle("Ask when I'm free each time", isOn: $askFreeTime)
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("When \"Ask when I'm free\" is on, each new plan asks for your free time instead of using your routine. Calendar events are still avoided.")
                }
                Section {
                    ForEach(pace, id: \.category) { p in
                        LabeledContent(p.category.capitalized,
                                       value: "×\(p.ratio.formatted(.number.precision(.fractionLength(1)))) · \(p.count) tasks")
                    }
                    if !pace.isEmpty {
                        Button("Reset my pace", role: .destructive) {
                            Planner.resetPace()
                            pace = []
                        }
                    }
                } header: {
                    Text("My pace")
                } footer: {
                    Text(pace.isEmpty
                         ? "After you finish \(Planner.paceRunway) tasks of a kind, the AI learns how long they really take you."
                         : "Real time ÷ AI estimate. ×1.5 means it takes you 50% longer; new plans adjust for it.")
                }
                Section("Google Calendar") {
                    NavigationLink("How to connect Google Calendar") {
                        CalendarTipView()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(minutes.wrappedValue * 60))
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                minutes.wrappedValue = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }
        )
    }
}

#Preview { SettingsView() }
