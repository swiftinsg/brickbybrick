import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]
    @State private var path: [Plan] = []
    @State private var showNew = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(plans) { plan in
                    NavigationLink(value: plan) {
                        VStack(alignment: .leading) {
                            Text(plan.title).font(.headline)
                            Text("\(plan.mode.rawValue) · \(plan.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { $0.map { plans[$0] }.forEach(context.delete) }
            }
            .overlay {
                if plans.isEmpty {
                    ContentUnavailableView("No plans yet", systemImage: "checklist",
                                           description: Text("Tap + to plan your day or a goal."))
                }
            }
            .navigationTitle("Focusedhouse")
            .navigationDestination(for: Plan.self) { PlanView(plan: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New plan", systemImage: "plus") { showNew = true }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showNew) {
                NewPlanView { plan in
                    showNew = false
                    path.append(plan)
                }
            }
        }
    }
}

#Preview {
    ContentView().modelContainer(for: Plan.self, inMemory: true)
}
