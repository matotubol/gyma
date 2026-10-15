import XCTest
@testable import GymaCore

final class RestTimerTests: XCTestCase {
    private let now = WorkoutTestFixture.now

    func testTimerRemainingIsSafeFor32BitWatchIntegerConversion() {
        let distant = Date(timeIntervalSince1970: 4_102_444_800)
        let timer = RestTimer(workoutID: "future", exerciseID: "bench_press", startedAt: distant.addingTimeInterval(-120), endsAt: distant, sourceSetID: "set")
        XCTAssertEqual(timer.remaining(at: now), 86400)
        XCTAssertNotNil(Int32(exactly: ceil(timer.remaining(at: now))))
        XCTAssertEqual(timer.remaining(at: distant.addingTimeInterval(1)), 0)
    }

    func testUnknownWarmupNeverStartsTimerAndFinalTargetClearsIt() throws {
        var state = try WorkoutTestFixture.activeState()
        try state.updateTarget(.init(sets: 2, repsMin: 8, repsMax: 10), exerciseID: "bench_press", workoutID: "workout-1")
        try state.addSet(.init(kg: 40, reps: 8), exerciseID: "bench_press", workoutID: "workout-1", now: now)
        XCTAssertNil(state.restTimer)
        try state.addSet(.init(kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "workout-1", now: now)
        XCTAssertNotNil(state.restTimer)
        try state.addSet(.init(kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "workout-1", now: now)
        XCTAssertNil(state.restTimer)
    }
}
