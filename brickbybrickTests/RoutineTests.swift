import Foundation
import Testing
@testable import brickbybrick

struct RoutineTests {
    func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "RoutineTests-\(UUID())")!
        d.set(6 * 60, forKey: "wake")
        d.set(true, forKey: "hasSchool")
        return d
    }

    @Test func routineOnByDefault() {
        let r = Routine.from(defaults())
        #expect(r.wake == 6 * 60 && r.hasSchool)
    }

    @Test func routineOffIsLooseAndSchoolFree() {
        let d = defaults()
        d.set(false, forKey: "useRoutine")
        let r = Routine.from(d)
        #expect(r.wake == 8 * 60 && r.bed == 23 * 60 && !r.hasSchool)
    }
}
