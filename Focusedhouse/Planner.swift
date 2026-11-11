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
    @Guide(description: "high if the user marked it urgent, important or due soon; low if they said it can wait; otherwise normal",
           .anyOf(Planner.priorities))
    var priority: String
    @Guide(description: "Short name of the section or topic of the study material this task covers, e.g. \"Section 1: Arenes\". Empty if there is no study material or no sections.")
    var section: String
}

enum Planner {
    static let categories = ["homework", "study", "revision", "reading", "writing",
                             "project", "chores", "exercise", "other"]

    static let priorities = ["high", "normal", "low"]

    static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    static func draft(mode: PlanMode, input: String, materials: String, days: Int) async throws -> DraftPlan {
        let session = LanguageModelSession(instructions: """
            You help a student or teenager plan their work. Break the input into small, \
            concrete tasks. Each task should take 10 to 90 minutes; split anything bigger. \
            Estimate durations realistically for a typical student, not an expert. \
            If the user gives priorities (urgent, important, "!", due dates, "can wait"), \
            set each task's priority from them. \
            If study material is given, follow its sections or topics in order, make tasks \
            for each section, and set the task's section to that section's short name.
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
        // ponytail: the on-device model has a small context window; long material is cut,
        // upgrade by drafting one section at a time if students paste whole chapters.
        let material = materials.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = material.isEmpty ? prompt : prompt + "\n\nStudy material:\n" + material.prefix(6000)
        do {
            return try await session.respond(to: full, generating: DraftPlan.self).content
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw PlannerError.tooLong
        }
    }
}

enum PlannerError: LocalizedError {
    case tooLong
    var errorDescription: String? {
        "That's too much text for the on-device AI at once. Try a shorter list or fewer sections."
    }
}
