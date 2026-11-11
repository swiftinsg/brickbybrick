import SwiftUI
import SwiftData

@main
struct FocusedhouseApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(for: Plan.self)
    }
}
