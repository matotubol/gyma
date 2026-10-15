import Foundation
@testable import GymaCore

/// Shared fixture for command replay, state persistence, and rest timer integration tests.
enum WorkoutTestFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func activeState() throws -> GymaState {
        var state = GymaState()
        try state.startWorkout(Workout(id: "workout-1", start: now, exercises: [.init(exerciseID: "bench_press")]))
        return state
    }
    static func command(_ state: GymaState, id: String = UUID().uuidString, action: WatchAction) -> WatchCommand {
        WatchCommand(id: id, storeID: state.storeID, workoutID: "workout-1", basedOnRevision: state.revision, createdAt: now, action: action)
    }
}
