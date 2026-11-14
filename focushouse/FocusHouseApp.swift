import SwiftUI
import SwiftData

@main
struct FocusHouseApp: App {
    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do { container = try ModelContainer(for: Plan.self, TodoItem.self) }
        catch { fatalError("Couldn't open saved plans: \(error)") }
        Reminders.shared.setUp(container: container)
        CheckIn.shared.restore(container.mainContext)
        Theme.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Home", image: "tab.home") { HomeView() }
                Tab("Schedule", image: "tab.schedule") { ContentView() }
                Tab("Tasks", image: "tab.tasks") {
                    TaskView(minimumDueDate: .distantPast, sortOrder: [])
                }
                Tab("Calendar", image: "tab.calendar") { CalendarView() }
            }
            .tint(.brick)
            .sheet(item: Binding(get: { CheckIn.shared.queue.first },
                                 set: { if $0 == nil, let t = CheckIn.shared.queue.first { CheckIn.shared.later(t) } })) {
                CheckInSheet(task: $0)
            }
        }
            .modelContainer(container)
            .onChange(of: scenePhase) { _, phase in
                // Rest for the house: Screen Time when it's on, else time away from the app.
                if ScreenTime.isOn {
                    if phase == .active { ScreenTime.schedule() }   // picks up routine changes
                } else {
                    if phase == .background { RestLog.appLeft() }
                    if phase == .active { RestLog.appOpened() }
                }
            }
    }
}
