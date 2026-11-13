import DeviceActivity
import Foundation

/// Screen Time runs this in the background at the start and end of each waking
/// hour brickbybrick watches. If the phone was used less than
/// `RestHours.glanceMinutes` that hour, it counts as an hour of rest.
// ponytail: Screen Time callbacks can be late or skipped; a missed hour just
// isn't counted, which errs on the side of less rest.
final class RestMonitor: DeviceActivityMonitor {
    private func usedKey(_ activity: DeviceActivityName) -> String { "used." + activity.rawValue }

    override func intervalDidStart(for activity: DeviceActivityName) {
        RestLog.defaults.removeObject(forKey: usedKey(activity))
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        RestLog.defaults.set(true, forKey: usedKey(activity))
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        guard !RestLog.defaults.bool(forKey: usedKey(activity)) else { return }
        RestLog.update { $0.add(3600, on: Date.now.addingTimeInterval(-60)) }
    }
}
