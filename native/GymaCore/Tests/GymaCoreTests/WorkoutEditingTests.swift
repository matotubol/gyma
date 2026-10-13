import XCTest
@testable import GymaCore

final class WorkoutEditingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func makeState() throws -> GymaState {
        var state = GymaState()
        let target = ExerciseTarget(sets: 3, repsMin: 8, repsMax: 10, loadKg: 40)
        try state.startWorkout(.init(id: "active", start: start, exercises: [
            .init(exerciseID: "bench_press", target: target), .init(exerciseID: "squat", target: target)
        ]))
        return state
    }

    func testReorderKeepsExerciseDataAndRejectsMissingOrDuplicatedIDsAtomically() throws {
        var state = try makeState()
        try state.addSet(.init(id: "set", kg: 40, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "active", now: start.addingTimeInterval(20))
        let original = try XCTUnwrap(state.activeWorkout)
        let timer = state.restTimer
        try state.reorderExercises(["squat", "bench_press"], workoutID: "active")
        XCTAssertEqual(state.activeWorkout?.exercises, original.exercises.reversed().map { $0 })
        XCTAssertEqual(state.restTimer, timer)
        let reordered = state
        for ids in [["squat"], ["squat", "squat"], ["squat", "unknown"]] {
            XCTAssertThrowsError(try state.reorderExercises(ids, workoutID: "active"))
            XCTAssertEqual(state, reordered)
        }
        try state.validate()
    }

    func testManualReplacementKeepsOriginalSetsAndCopiesOnlyRemainingTarget() throws {
        var state = try makeState()
        try state.addSet(.init(id: "set", kg: 40, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "active", now: start.addingTimeInterval(20))
        let original = try XCTUnwrap(state.activeWorkout?.exercises.first)
        try state.replaceExercise("bench_press", with: "lat_pulldown", workoutID: "active", now: start.addingTimeInterval(50))
        let workout = try XCTUnwrap(state.activeWorkout)
        XCTAssertEqual(workout.exercises.map(\.exerciseID), ["bench_press", "lat_pulldown", "squat"])
        XCTAssertEqual(workout.exercises[0].sets, original.sets)
        XCTAssertEqual(workout.exercises[0].target, original.target)
        XCTAssertEqual(workout.exercises[0].skippedSetCount, 2)
        XCTAssertEqual(workout.exercises[1].target?.sets, 2)
        XCTAssertNil(workout.exercises[1].target?.loadKg)
        XCTAssertEqual(workout.nextExercise?.exerciseID, "lat_pulldown")
        XCTAssertEqual(workout.volume, original.volume)
        XCTAssertEqual(workout.restHistory?.first?.elapsedSeconds, 30)
        XCTAssertNil(state.restTimer)
        try state.validate()
    }

    func testUnstartedReplacementStaysInPlaceAndInvalidReplacementDoesNotMutateState() throws {
        var state = try makeState()
        try state.selectExercise("bench_press", workoutID: "active", now: start)
        try state.replaceExercise("bench_press", with: "lat_pulldown", workoutID: "active", now: start)
        XCTAssertEqual(state.activeWorkout?.exercises.map(\.exerciseID), ["lat_pulldown", "squat"])
        XCTAssertEqual(state.activeWorkout?.selectedExerciseID, "lat_pulldown")
        let original = state
        for replacement in ["unknown", "squat", "lat_pulldown"] {
            XCTAssertThrowsError(try state.replaceExercise("lat_pulldown", with: replacement, workoutID: "active", now: start))
            XCTAssertEqual(state, original)
        }
        try state.validate()
    }

    func testReplacementRejectsInvalidEventDateWithoutLosingLoggedSets() throws {
        var state = try makeState()
        try state.addSet(.init(kg: 40, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "active", now: start.addingTimeInterval(20))
        let original = state
        XCTAssertThrowsError(try state.replaceExercise("bench_press", with: "lat_pulldown", workoutID: "active", now: start.addingTimeInterval(-1)))
        XCTAssertEqual(state, original)
    }

    func testReplacementAfterSkippingWithoutLoggingKeepsSkipAndOnlyRemainingWork() throws {
        var state = try makeState()
        try state.skipSet(exerciseID: "bench_press", workoutID: "active", now: start)
        try state.replaceExercise("bench_press", with: "lat_pulldown", workoutID: "active", now: start)
        let exercises = try XCTUnwrap(state.activeWorkout?.exercises)
        XCTAssertEqual(exercises[0].exerciseID, "bench_press")
        XCTAssertEqual(exercises[0].skippedSetCount, 3)
        XCTAssertEqual(exercises[1].exerciseID, "lat_pulldown")
        XCTAssertEqual(exercises[1].target?.sets, 2)
        XCTAssertNil(exercises[1].target?.loadKg)
        XCTAssertEqual(state.activeWorkout?.totalSets, 0)
        try state.validate()
    }
}
