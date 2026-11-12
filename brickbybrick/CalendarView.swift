import SwiftUI
import SwiftData

/// Home: a month calendar, then everything on the picked day. That's the
/// scheduled tasks from every plan, plus inbox to-dos due that day.
struct CalendarView: View {
    @Query private var tasks: [PlanTask]
    @Query(filter: #Predicate<TodoItem> { !$0.isDone }) private var todos: [TodoItem]
    @State private var day = Date.now

    private let cal = Calendar.current

    private var tasksOnDay: [PlanTask] {
        tasks.filter { $0.start.map { cal.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { $0.start! < $1.start! }
    }
    /// Days with something still to do, for the dots.
    private var busyDays: Set<Date> {
        Set(tasks.filter { !$0.done }.compactMap { $0.start.map(cal.startOfDay) }
            + todos.map { cal.startOfDay(for: $0.dueDate) })
    }
    private var todosOnDay: [TodoItem] { todos.filter { cal.isDate($0.dueDate, inSameDayAs: day) } }

    var body: some View {
        NavigationStack {
            List {
                MonthGrid(day: $day, busy: busyDays)

                Section(day.formatted(.dateTime.weekday(.wide).day().month())) {
                    ForEach(tasksOnDay) { task in
                        HStack(spacing: 12) {
                            Button {
                                withAnimation(.snappy) { task.setDone(!task.done) }
                                task.plan?.reflow()   // re-arm reminders, as in PlanView
                            } label: {
                                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(task.done ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            .sensoryFeedback(.success, trigger: task.done) { !$0 && $1 }

                            if let plan = task.plan {
                                NavigationLink(value: plan) { row(task) }
                            } else {
                                row(task)
                            }
                        }
                    }
                    ForEach(todosOnDay) { todo in
                        HStack(spacing: 12) {
                            Button { todo.isDone = true } label: {
                                Image(systemName: "circle").font(.title2).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(todo.name)
                                Text("Due · not planned yet").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    if tasksOnDay.isEmpty && todosOnDay.isEmpty {
                        Text("Nothing on this day").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Calendar")
            .navigationDestination(for: Plan.self) { PlanView(plan: $0) }
            .toolbar {
                if !cal.isDateInToday(day) {
                    Button("Today") { day = .now }
                }
            }
        }
    }

    private func row(_ task: PlanTask) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.title).strikethrough(task.done).foregroundStyle(task.done ? .secondary : .primary)
            Text("\(task.start!.formatted(date: .omitted, time: .shortened))–\(task.end!.formatted(date: .omitted, time: .shortened)) · \(task.plan?.title ?? "")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A month of days with a dot under each day that has something to do.
struct MonthGrid: View {
    @Binding var day: Date
    var busy: Set<Date>
    @State private var month = Date.now
    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button("Previous month", systemImage: "chevron.left") { shift(-1) }
                Button("Next month", systemImage: "chevron.right") { shift(1) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(Array(Self.weekdaySymbols(cal).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(Self.days(in: month, calendar: cal).enumerated()), id: \.offset) { _, date in
                    if let date { cell(date) } else { Color.clear.frame(height: 40) }
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: day) { if !cal.isDate(day, equalTo: month, toGranularity: .month) { month = day } }
        .sensoryFeedback(.selection, trigger: day)
    }

    private func cell(_ date: Date) -> some View {
        let selected = cal.isDate(date, inSameDayAs: day)
        let today = cal.isDateInToday(date)
        return Button { day = date } label: {
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.day()))
                    .font(.callout.weight(today || selected ? .bold : .regular))
                    .foregroundStyle(selected ? Color.white : today ? Color.accentColor : .primary)
                    .frame(width: 32, height: 32)
                    .background(selected ? Color.accentColor : .clear, in: .circle)
                Circle().fill(busy.contains(date) ? Color.accentColor : .clear).frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted) + (busy.contains(date) ? ", has tasks" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func shift(_ months: Int) {
        month = cal.date(byAdding: .month, value: months, to: month)!
    }

    /// Very short weekday names, starting on the locale's first weekday.
    static func weekdaySymbols(_ cal: Calendar) -> [String] {
        let s = cal.veryShortStandaloneWeekdaySymbols
        return Array(s[(cal.firstWeekday - 1)...] + s[..<(cal.firstWeekday - 1)])
    }

    /// The month's days (at start of day), led by nils so day 1 sits under its weekday.
    static func days(in month: Date, calendar cal: Calendar) -> [Date?] {
        let first = cal.dateInterval(of: .month, for: month)!.start
        let blanks = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: first)!.count
        return Array(repeating: nil, count: blanks) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: first) }
    }
}
