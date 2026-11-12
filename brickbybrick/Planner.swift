import Foundation
import FoundationModels

@Generable struct DraftPlan {
    @Guide(description: "Short title naming the work, 2 to 5 words, no full stop, e.g. \"Chemistry exam revision\" or \"Tuesday to-dos\"")
    var title: String
    @Guide(description: "One item per thing the user asked for, in the order they should be done", .count(1...15))
    var items: [DraftItem]
}

/// One thing the student asked for. Big work comes with subtasks; each subtask
/// becomes its own scheduled task in the app, grouped under the item's title.
@Generable struct DraftItem {
    @Guide(description: "Short, concrete action starting with a verb")
    var title: String
    @Guide(description: "Task category", .anyOf(Planner.categories))
    var category: String
    @Guide(description: "Realistic minutes a typical student needs for the whole item", .range(5...240))
    var minutes: Int
    @Guide(description: "Which day of the plan to do it on, starting at 1", .range(1...30))
    var day: Int
    @Guide(description: "high if the user marked it urgent, important or due soon; low if they said it can wait; otherwise normal",
           .anyOf(Planner.priorities))
    var priority: String
    @Guide(description: "Steps for a big piece of work (essay, project, revision, a long homework, a study-material section): 2 to 5 steps. Empty for a quick, simple job like paying someone back or tidying a room.",
           .count(0...5))
    var subtasks: [DraftStep]
}

@Generable struct DraftStep {
    @Guide(description: "Short, concrete action starting with a verb")
    var title: String
    @Guide(description: "Realistic minutes a typical student needs for this step", .range(5...120))
    var minutes: Int
}

enum Planner {
    static let categories = ["homework", "study", "revision", "reading", "writing",
                             "project", "chores", "exercise", "other"]

    static let priorities = ["high", "normal", "low"]

    static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    /// Splits the plan's input into tasks. `previous` is the plan the student
    /// rejected with "Start over": the AI is asked for a genuinely different one.
    @MainActor static func draft(for plan: Plan, previous: [PlanTask] = []) async throws -> DraftPlan {
        let session = LanguageModelSession(instructions: """
            You help a student or teenager plan their work. Turn each thing the user asked for \
            into one item. Quick, simple jobs (pay mum back, tidy room, reply to a message, feed \
            the cat) take 5 to 20 minutes and have no subtasks. Big pieces of work (an essay, a \
            project, exam revision, a long homework) get 2 to 5 subtasks of 20 to 90 minutes \
            that a student can tick off one by one. \
            Estimate durations realistically for a typical student, not an expert. \
            Never leave out anything the user asked for, even if it doesn't fit the free time. \
            When spreading over several days, keep each day within its free time and spread \
            the work evenly. \
            If the user gives priorities (urgent, important, "!", due dates, "can wait"), \
            set each item's priority from them. Otherwise use normal priority. \
            If study material is given, make one item per section or topic, in order, titled \
            with the section's short name (e.g. "Section 1: Arenes"), with its tasks as subtasks.
            """)
        var prompt = switch plan.mode {
        case .today:
            """
            Tidy this messy to-do list into items for day 1. Every line must become an item. \
            Only merge exact duplicates. Set day to 1 for every item.

            \(items(plan.input).map { "- " + $0 }.joined(separator: "\n"))
            """
        case .goal:
            """
            Goal: \(plan.input)
            Spread the items over days 1 to \(plan.days), earlier steps first. \
            The goal must be done by the end of day \(plan.days).
            """
        }
        prompt += "\n\nFree time:\n" + freeTime(for: plan)
        // ponytail: the on-device model has a small context window; long material is cut,
        // upgrade by drafting one section at a time if students paste whole chapters.
        let material = plan.materials.trimmingCharacters(in: .whitespacesAndNewlines)
        if !material.isEmpty { prompt += "\n\nStudy material:\n" + material.prefix(6000) }
        prompt += examples(for: plan.input + " " + material.prefix(2000))
        prompt += paceNote()

        var options = GenerationOptions()
        if !previous.isEmpty {
            let old = previous.map { "- \($0.parent.isEmpty ? "" : $0.parent + ": ")\($0.title) (\($0.minutes) min, day \($0.day))" }.joined(separator: "\n")
            prompt += """


                The student didn't like this plan and wants a different one:
                \(old)
                Make a genuinely different alternative that still covers everything: break \
                the work down differently (bigger or smaller chunks, a different study method \
                such as practice questions, flashcards or summaries), group or order it \
                differently, and use different task names. Don't repeat the plan above.
                """
            options = GenerationOptions(samplingMode: .random(probabilityThreshold: 0.9), temperature: 1.0)
        }
        do {
            var draft = try await session.respond(to: prompt, generating: DraftPlan.self, options: options).content
            if plan.mode == .today { reconcile(items(plan.input), in: &draft) }
            return tidied(draft)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw PlannerError.tooLong
        }
    }

    /// The to-do dump as separate items. The model skips items in long comma lists,
    /// but keeps them reliably one per line.
    static func items(_ input: String) -> [String] {
        input.split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-•*"))) }
            .filter { !$0.isEmpty }
    }

    /// Fixes what the small model gets wrong with to-do lists: it drops items and
    /// ignores "urgent". Each line's priority words win; a dropped line comes back
    /// as its own 30-minute task.
    // ponytail: word-overlap match; a dropped item sharing a word with another task
    // ("clean room" vs "tidy room") counts as merged. Fine for to-do lists.
    static func reconcile(_ lines: [String], in draft: inout DraftPlan) {
        for line in lines where !words(line).isEmpty {
            let lower = line.lowercased()
            let marked: String? = line.contains("!") || ["urgent", "asap", "due", "important"].contains(where: lower.contains) ? "high"
                : ["can wait", "later", "maybe", "if time"].contains(where: lower.contains) ? "low" : nil
            if let i = draft.items.firstIndex(where: { !words($0.title).isDisjoint(with: words(line)) }) {
                if let marked { draft.items[i].priority = marked }
            } else {
                draft.items.append(DraftItem(title: line.prefix(1).uppercased() + line.dropFirst(),
                                             category: "other", minutes: 30, day: 1,
                                             priority: marked ?? "normal", subtasks: []))
            }
        }
    }

    /// Lowercased words of 3+ letters, minus filler, for loose matching.
    static func words(_ s: String) -> Set<String> {
        Set(s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            .filter { $0.count >= 3 && !["the", "and", "for", "with", "due", "tmr"].contains($0) })
    }

    /// Chores and one-step items stay as a single task: no subtasks.
    static func tidied(_ draft: DraftPlan) -> DraftPlan {
        var draft = draft
        for i in draft.items.indices where draft.items[i].category == "chores" || draft.items[i].subtasks.count < 2 {
            draft.items[i].subtasks = []
        }
        return draft
    }

    /// "Day 1 (Wed 11 Nov, from 4:30 PM): about 3 h 15 min free", from the routine
    /// and Calendar, so estimates and spreading fit the student's real days.
    @MainActor static func freeTime(for plan: Plan) -> String {
        let cal = Calendar.current
        let first = cal.startOfDay(for: plan.start)
        let busy = CalendarSync.busy(from: plan.start, days: plan.days, excluding: Set(plan.tasks.compactMap(\.eventID)))
        // ponytail: lists at most 14 days to save context; later days follow the same pattern.
        return (0..<min(max(plan.days, 1), 14)).compactMap { i -> String? in
            guard let day = cal.date(byAdding: .day, value: i, to: first) else { return nil }
            let free = plan.routine.windows(on: day, calendar: cal)
                .flatMap { Scheduler.free($0, minus: busy) }
                .compactMap { w -> Range<Date>? in
                    let s = max(w.lowerBound, plan.start)
                    return s < w.upperBound ? s..<w.upperBound : nil
                }
            let minutes = Int(free.reduce(0) { $0 + $1.upperBound.timeIntervalSince($1.lowerBound) } / 60)
            let from = i == 0 ? ", from \(plan.start.formatted(date: .omitted, time: .shortened))" : ""
            return "Day \(i + 1) (\(day.formatted(.dateTime.weekday().day().month()))\(from)): about \(minutes / 60) h \(minutes % 60) min free"
        }.joined(separator: "\n")
    }
}

extension Planner {
    /// Re-plan with AI: the student is behind, so rebuild what's left.
    @MainActor static func replan(_ plan: Plan) async throws -> DraftPlan {
        let left = plan.ordered.filter { !$0.done }.map { t in
            "- \(t.title) (\(t.minutes) min, \(priorities[min(max(t.priority, 0), 2)]) priority"
                + (t.parent.isEmpty ? ")" : ", part of: \(t.parent))")
        }
        let cal = Calendar.current
        let elapsed = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: plan.start), to: cal.startOfDay(for: .now)).day ?? 0)
        let daysLeft = max(1, plan.days - elapsed)
        let when = plan.mode == .today || daysLeft == 1
            ? "Fit them into the rest of today; set day to 1 for every task."
            : "Spread them over the next \(daysLeft) days, starting today as day 1."
        let session = LanguageModelSession(instructions: """
            You help a student who is running behind on their plan. Rebuild a realistic plan \
            for their remaining tasks. Keep every high-priority task. You may merge small \
            tasks, shorten or split long ones, and reorder them, but don't invent new work. \
            Keep each task's priority. Tasks that are part of the same thing go back together \
            as the subtasks of one item titled with that name; other tasks are items with no subtasks.
            """)
        let prompt = """
            It is now \(Date.now.formatted(date: .omitted, time: .shortened)). Remaining tasks:
            \(left.joined(separator: "\n"))

            \(when)
            """
        do {
            return tidied(try await session.respond(to: prompt, generating: DraftPlan.self).content)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw PlannerError.tooLong
        }
    }
}

/// Adaptive subtasks: the breakdowns the student writes themselves are saved and
/// shown to the AI as examples next time a similar item comes up.
extension Planner {
    struct Example: Codable, Equatable {
        var item: String
        var steps: [String]   // "Outline essay (20 min)"
    }

    private static let examplesKey = "subtaskExamples"

    // ponytail: last 40 breakdowns as JSON in UserDefaults; move to SwiftData if it needs to grow.
    static func remember(item: String, steps: [(title: String, minutes: Int)]) {
        var all = savedExamples().filter { $0.item.lowercased() != item.lowercased() }
        all.append(Example(item: item, steps: steps.map { "\($0.title) (\($0.minutes) min)" }))
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(all.suffix(40))), forKey: examplesKey)
    }

    static func savedExamples() -> [Example] {
        UserDefaults.standard.data(forKey: examplesKey)
            .flatMap { try? JSONDecoder().decode([Example].self, from: $0) } ?? []
    }

    /// Up to 3 saved breakdowns sharing words with `text` (most overlap, then newest),
    /// as a prompt section; empty when none match.
    static func examples(for text: String, from saved: [Example] = savedExamples()) -> String {
        let wanted = words(text)
        let matches = saved.reversed().enumerated()
            .map { (rank: words($0.element.item).intersection(wanted).count, age: $0.offset, example: $0.element) }
            .filter { $0.rank > 0 }
            .sorted { ($0.rank, -$0.age) > ($1.rank, -$1.age) }
            .prefix(3)
        guard !matches.isEmpty else { return "" }
        return "\n\nThis student has broken down similar work like this before. For matching items, use the same kind of steps and durations:\n"
            + matches.map { "- \($0.example.item): " + $0.example.steps.joined(separator: "; ") }.joined(separator: "\n")
    }
}

/// Adaptive estimates: each finished AI-estimated task saves actual ÷ estimate
/// for its category, and the typical ratio goes into the prompt.
extension Planner {
    private static let paceKey = "paceRatios"

    // ponytail: last 20 ratios per category as JSON in UserDefaults; enough to track a pace.
    static func recordPace(category: String, estimate: Int, actual: Int) {
        guard estimate > 0 else { return }
        var all = savedPace()
        all[category, default: []].append(Double(actual) / Double(estimate))
        all[category] = Array(all[category]!.suffix(20))
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: paceKey)
    }

    static func savedPace() -> [String: [Double]] {
        UserDefaults.standard.data(forKey: paceKey)
            .flatMap { try? JSONDecoder().decode([String: [Double]].self, from: $0) } ?? [:]
    }

    static func resetPace() { UserDefaults.standard.removeObject(forKey: paceKey) }

    /// Finished tasks a category needs before its pace counts: a longer runway,
    /// so a couple of odd tasks (or students tweaking times) don't skew it.
    static let paceRunway = 5

    /// Median actual ÷ estimate per category with `paceRunway`+ finished tasks.
    static func pace(from saved: [String: [Double]] = savedPace()) -> [(category: String, ratio: Double, count: Int)] {
        saved.filter { $0.value.count >= paceRunway }.map { category, ratios in
            let sorted = ratios.sorted()
            let mid = sorted.count / 2
            let median = sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
            return (category, median, ratios.count)
        }.sorted { $0.category < $1.category }
    }

    /// Prompt section for categories where the student is 10%+ off the estimates;
    /// empty when they match. Spells out an example so the small model can scale.
    static func paceNote(from saved: [String: [Double]] = savedPace()) -> String {
        let off = pace(from: saved).filter { abs($0.ratio - 1) >= 0.1 }
        guard !off.isEmpty else { return "" }
        return "\n\nThis student's real pace from past tasks. Scale your estimates for these categories:\n"
            + off.map { p in
                let example = Int((30 * p.ratio / 5).rounded()) * 5
                return "- \(p.category): takes \(p.ratio > 1 ? "longer" : "less time") than typical, ×\(p.ratio.formatted(.number.precision(.fractionLength(1)))) (a typical 30 min \(p.category) task takes them about \(max(5, example)) min)"
            }.joined(separator: "\n")
    }
}

enum PlannerError: LocalizedError {
    case tooLong
    var errorDescription: String? {
        "That's too much text for the on-device AI at once. Try a shorter list or fewer sections."
    }
}
