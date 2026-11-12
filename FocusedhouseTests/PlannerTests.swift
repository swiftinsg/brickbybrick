import Testing
@testable import Focusedhouse

struct PlannerTests {
    @Test func splitsToDoDump() {
        #expect(Planner.items("maths hw, read ch 4;\n- tidy room\n\n") == ["maths hw", "read ch 4", "tidy room"])
    }

    private func item(_ title: String, _ category: String = "homework", steps: Int = 0) -> DraftItem {
        DraftItem(title: title, category: category, minutes: 30, day: 1, priority: "normal",
                  subtasks: (0..<steps).map { DraftStep(title: "Step \($0)", minutes: 10) })
    }

    @Test func restoresDroppedItemsAndPriorities() {
        var draft = DraftPlan(title: "To-dos", items: [item("Tidy room", "chores"), item("Write essay draft")])
        Planner.reconcile(["clean room", "essay draft due tmr", "maths hw!!", "maths hw", "gym maybe", "4"], in: &draft)
        #expect(draft.items.map(\.title) == ["Tidy room", "Write essay draft", "Maths hw!!", "Gym maybe"])
        #expect(draft.items.map(\.priority) == ["normal", "high", "high", "low"])
    }

    @Test func choresAndOneStepItemsHaveNoSubtasks() {
        let draft = Planner.tidied(DraftPlan(title: "x", items: [
            item("Tidy room", "chores", steps: 3), item("Maths hw", steps: 1), item("Essay", "writing", steps: 3)
        ]))
        #expect(draft.items.map(\.subtasks.count) == [0, 0, 3])
    }

    @Test func picksMatchingSubtaskExamples() {
        let saved = [Planner.Example(item: "English essay", steps: ["Find quotes (15 min)"]),
                     Planner.Example(item: "Maths problem set", steps: ["Easy ones first (20 min)"]),
                     Planner.Example(item: "Clean bike", steps: ["Wash (10 min)"])]
        let text = Planner.examples(for: "history essay, physics problem set", from: saved)
        #expect(text.contains("Maths problem set"))
        #expect(text.contains("English essay"))
        #expect(!text.contains("Clean bike"))
        #expect(Planner.examples(for: "feed cat", from: saved).isEmpty)
    }
}
