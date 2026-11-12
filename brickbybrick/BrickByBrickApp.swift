import SwiftUI
import SwiftData

@main
struct BrickByBrickApp: App {
    let container: ModelContainer

    init() {
        do { container = try ModelContainer(for: Plan.self) }
        catch { fatalError("Couldn't open saved plans: \(error)") }
        Reminders.shared.setUp(container: container)
    }

    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(container)
    }
}
