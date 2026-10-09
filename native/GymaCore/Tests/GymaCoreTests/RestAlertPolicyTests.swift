import XCTest
@testable import GymaCore

final class RestAlertPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func snapshot() throws -> CompanionSnapshot {
        var state = GymaState()
        try state.startWorkout(Workout(id: "workout", start: now, exercises: [.init(exerciseID: "bench_press")]))
        try state.addSet(.init(kg: 50, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "workout", now: now)
        return CompanionSnapshot(state: state, now: now)
    }
    func testWorkoutHapticSurvivesWristDownWithoutNotificationAuthorization() throws {
        let snapshot = try snapshot()
        let background = RestAlertPolicy.hapticSchedule(snapshot: snapshot, pending: nil, enabled: true, isAppActive: false,
                                                       workoutRunning: true, lastAlertKey: nil, now: now)
        XCTAssertEqual(background?.delay, 120)
        XCTAssertNil(RestAlertPolicy.hapticSchedule(snapshot: snapshot, pending: nil, enabled: true, isAppActive: false,
                                                  workoutRunning: false, lastAlertKey: nil, now: now))
        XCTAssertNotNil(RestAlertPolicy.hapticSchedule(snapshot: snapshot, pending: nil, enabled: true, isAppActive: true,
                                                     workoutRunning: false, lastAlertKey: nil, now: now))
    }
    func testDeadlineDeduplicatesAndBriefLateDeliveryStillAlerts() throws {
        let snapshot = try snapshot()
        let timer = try XCTUnwrap(snapshot.restTimer)
        let key = RestAlertPolicy.key(timer: timer, storeID: snapshot.storeID)
        let ready = RestAlertPolicy.hapticSchedule(snapshot: snapshot, pending: nil, enabled: true, isAppActive: false,
                                                 workoutRunning: true, lastAlertKey: nil, now: now.addingTimeInterval(125))
        XCTAssertEqual(ready?.delay, 0)
        XCTAssertNil(RestAlertPolicy.hapticSchedule(snapshot: snapshot, pending: nil, enabled: true, isAppActive: true,
                                                  workoutRunning: true, lastAlertKey: key, now: now.addingTimeInterval(125)))
        XCTAssertNil(RestAlertPolicy.hapticSchedule(snapshot: snapshot, pending: nil, enabled: true, isAppActive: true,
                                                  workoutRunning: true, lastAlertKey: nil, now: now.addingTimeInterval(300)))
    }
    func testDismissFinishAndDisabledPreferenceSuppressHaptic() throws {
        let snapshot = try snapshot()
        let timer = try XCTUnwrap(snapshot.restTimer)
        for action in [WatchAction.skipRest(timerID: timer.id), .finishWorkout] {
            let pending = WatchCommand(storeID: snapshot.storeID, workoutID: "workout", action: action)
            XCTAssertNil(RestAlertPolicy.hapticSchedule(snapshot: snapshot, pending: pending, enabled: true, isAppActive: true,
                                                      workoutRunning: true, lastAlertKey: nil, now: now))
        }
        XCTAssertNil(RestAlertPolicy.hapticSchedule(snapshot: snapshot, pending: nil, enabled: false, isAppActive: true,
                                                  workoutRunning: true, lastAlertKey: nil, now: now))
        let stale = WatchCommand(workoutID: "old-workout", action: .finishWorkout)
        XCTAssertNotNil(RestAlertPolicy.hapticSchedule(snapshot: snapshot, pending: stale, enabled: true, isAppActive: true,
                                                     workoutRunning: true, lastAlertKey: nil, now: now))
        let oldStore = WatchCommand(storeID: "replaced-store", workoutID: "workout", action: .finishWorkout)
        XCTAssertNotNil(RestAlertPolicy.hapticSchedule(snapshot: snapshot, pending: oldStore, enabled: true, isAppActive: true,
                                                     workoutRunning: true, lastAlertKey: nil, now: now))
    }
    func testExtensionHasNewDeadlineAndFinishedWorkoutCannotAlert() throws {
        var snapshot = try snapshot()
        let timer = try XCTUnwrap(snapshot.restTimer)
        let oldKey = RestAlertPolicy.key(timer: timer, storeID: snapshot.storeID)
        snapshot.restTimer?.endsAt = timer.endsAt.addingTimeInterval(30)
        XCTAssertEqual(RestAlertPolicy.hapticSchedule(snapshot: snapshot, pending: nil, enabled: true, isAppActive: false,
                                                    workoutRunning: true, lastAlertKey: oldKey, now: now)?.delay, 150)
        snapshot.activeWorkout = nil
        XCTAssertNil(RestAlertPolicy.hapticSchedule(snapshot: snapshot, pending: nil, enabled: true, isAppActive: true,
                                                  workoutRunning: true, lastAlertKey: nil, now: now))
    }
}
