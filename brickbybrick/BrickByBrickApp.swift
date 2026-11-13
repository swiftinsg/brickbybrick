import SwiftUI
import SwiftData

@main
struct BrickByBrickApp: App {
    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do { container = try ModelContainer(for: Plan.self, TodoItem.self) }
        catch { fatalError("Couldn't open saved plans: \(error)") }
        Reminders.shared.setUp(container: container)
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
        }
            .modelContainer(container)
            .onChange(of: scenePhase) { _, phase in
                // Time away from the app counts as rest for the house.
                if phase == .background { RestLog.appLeft() }
                if phase == .active { RestLog.appOpened() }
            }
    }
}
