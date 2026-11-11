import Foundation
import FoundationModels

@Generable struct DraftPlan {
    @Guide(description: "Short title for the whole plan, 2 to 5 words")
    var title: String
    @Guide(description: "Tasks in the order they should be done", .count(1...20))
    var tasks: [DraftTask]
}

@Generable struct DraftTask {
    @Guide(description: "Short, concrete action starting with a verb")
    var title: String
    @Guide(description: "Task category", .anyOf(Planner.categories))
    var category: String
    @Guide(description: "Realistic minutes a typical student needs for this task", .range(5...180))
    var minutes: Int
    @Guide(description: "Which day of the plan to do it on, starting at 1", .range(1...30))
    var day: Int
}

enum Planner {
    static let categories = ["homework", "study", "revision", "reading", "writing",
                             "project", "chores", "exercise", "other"]

    static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    static func draft(mode: PlanMode, input: String, days: Int) async throws -> DraftPlan {
        let session = LanguageModelSession(instructions: """
            You help a student or teenager plan their work. Break the input into small, \
            concrete tasks. Each task should take 10 to 90 minutes; split anything bigger. \
            Estimate durations realistically for a typical student, not an expert.
            """)
        let prompt = switch mode {
        case .today:
            """
            Tidy this messy to-do list into tasks for today. Merge duplicates and drop \
            anything that isn't a task. Set day to 1 for every task.

            \(input)
            """
        case .goal:
            """
            Goal: \(input)
            Spread the tasks over \(days) days, earlier steps first. Use days 1 to \(days).
            """
        }
        return try await session.respond(to: prompt, generating: DraftPlan.self).content
    }
}
