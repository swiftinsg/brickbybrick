import Foundation
import SwiftData
import UserNotifications

/// Local notifications: a reminder when a task starts and a check-in when it
/// should end ("Done" / "+15, +30, +60 min"), handled even if the app is closed.
@MainActor final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()
    private var container: ModelContainer?

    private static let checkIn = "CHECKIN"
    private static let done = "DONE"
    private static let more = [15, 30, 60]

    func setUp(container: ModelContainer) {
        self.container = container
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let actions = [UNNotificationAction(identifier: Self.done, title: "Done ✓")]
            + Self.more.map { UNNotificationAction(identifier: "MORE\($0)", title: "Need \($0) more min") }
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.checkIn, actions: actions, intentIdentifiers: []),
        ])
    }

    static func requestAccess() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Replace this plan's pending reminders with ones matching its current times.
    // ponytail: iOS keeps only the 64 soonest pending notifications; fine for a
    // few plans, schedule a rolling window if students keep many long goal plans.
    static func sync(_ plan: Plan) {
        cancel(plan.tasks)
        let now = Date.now
        for task in plan.tasks where !task.done {
            guard let start = task.start, let end = task.end else { continue }
            if start > now {
                add(id: task.key + ".start", at: start, title: "Time for: \(task.title)",
                    body: "\(task.minutes) min, until \(end.formatted(date: .omitted, time: .shortened))",
                    task: task)
            }
            if end > now {
                add(id: task.key + ".end", at: end, title: "Done with \(task.title)?",
                    body: "Mark it done, or take a bit more time.", task: task, category: checkIn)
            }
        }
    }

    static func cancel(_ tasks: [PlanTask]) {
        let ids = tasks.flatMap { [$0.key + ".start", $0.key + ".end"] }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func add(id: String, at date: Date, title: String, body: String,
                            task: PlanTask, category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["task": task.key]
        if let category { content.categoryIdentifier = category }
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        guard let key = response.notification.request.content.userInfo["task"] as? String else { return }
        await handle(action: action, key: key)
    }

    private func handle(action: String, key: String) {
        guard let context = container?.mainContext, let uid = UUID(uuidString: key),
              let task = try? context.fetch(FetchDescriptor<PlanTask>(predicate: #Predicate { $0.uid == uid })).first,
              let plan = task.plan else { return }
        if action == Self.done {
            task.done = true
            plan.reflow()
        } else if action.hasPrefix("MORE"), let minutes = Int(action.dropFirst(4)) {
            plan.pushBack(task, by: minutes)
        }
        try? context.save()
    }
}
