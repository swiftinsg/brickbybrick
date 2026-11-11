import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("wake") private var wake = 420
    @AppStorage("bed") private var bed = 1320
    @AppStorage("schoolStart") private var schoolStart = 480
    @AppStorage("schoolEnd") private var schoolEnd = 900
    @AppStorage("hasSchool") private var hasSchool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("My routine") {
                    DatePicker("Wake up", selection: minutesBinding($wake), displayedComponents: .hourAndMinute)
                    DatePicker("Bedtime", selection: minutesBinding($bed), displayedComponents: .hourAndMinute)
                }
                Section("School") {
                    Toggle("School on weekdays", isOn: $hasSchool)
                    if hasSchool {
                        DatePicker("School starts", selection: minutesBinding($schoolStart), displayedComponents: .hourAndMinute)
                        DatePicker("School ends", selection: minutesBinding($schoolEnd), displayedComponents: .hourAndMinute)
                    }
                }
                Section {
                } footer: {
                    Text("Tasks are only scheduled between wake-up and bedtime, outside school hours.")
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
