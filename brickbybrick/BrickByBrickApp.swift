import SwiftUI
import SwiftData

@main
struct BrickByBrickApp: App {
    let container: ModelContainer

    init() {
        do { container = try ModelContainer(for: Plan.self, TodoItem.self) }
        catch { fatalError("Couldn't open saved plans: \(error)") }
        Reminders.shared.setUp(container: container)
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Plans", systemImage: "calendar") { ContentView() }
                Tab("Tasks", systemImage: "checklist") {
                    TaskView(minimumDueDate: .distantPast, sortOrder: [])
                }
            }
        }
            .modelContainer(container)
    }
}
