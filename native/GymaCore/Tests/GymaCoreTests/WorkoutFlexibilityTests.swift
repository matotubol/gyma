import XCTest
@testable import GymaCore

final class WorkoutFlexibilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var target: ExerciseTarget { .init(sets: 3, repsMin: 8, repsMax: 10, loadKg: 40, targetEffort: .challenging) }

    private func state() throws -> GymaState {
        var state = GymaState()
        try state.startWorkout(.init(id: "workout", start: now, exercises: [
            .init(exerciseID: "bench_press", target: target),
            .init(exerciseID: "squat", target: target)
        ]))
        return state
    }
    private func command(_ state: GymaState, _ action: WatchAction, at date: Date? = nil) -> WatchCommand {
        .init(storeID: state.storeID, workoutID: "workout", basedOnRevision: state.revision, createdAt: date ?? now, action: action)
    }
    private func log(_ state: inout GymaState, exerciseID: String = "bench_press", at date: Date? = nil) throws {
        try state.addSet(.init(kg: 40, reps: 10, effort: .challenging, isWarmup: false),
                         exerciseID: exerciseID, workoutID: "workout", now: date ?? now)
    }

    func testSkippedThirdSetResolvesExerciseWithoutInventingWorkOrAlteringTarget() throws {
        var state = try state()
        try log(&state)
        try log(&state, at: now.addingTimeInterval(90))
        try state.skipSet(exerciseID: "bench_press", workoutID: "workout", now: now.addingTimeInterval(120))
        let workout = try XCTUnwrap(state.activeWorkout)
        let exercise = workout.exercises[0]
        XCTAssertEqual(exercise.target, target)
        XCTAssertEqual(exercise.workingSetCount, 2)
        XCTAssertEqual(exercise.skippedSetCount, 1)
        XCTAssertEqual(exercise.resolvedSetCount, 3)
        XCTAssertEqual(exercise.remainingSetCount, 0)
        XCTAssertTrue(exercise.isTargetResolved)
        XCTAssertFalse(exercise.isTargetComplete)
        XCTAssertEqual(workout.nextExercise?.exerciseID, "squat")
        XCTAssertEqual(workout.totalSets, 2)
        XCTAssertEqual(workout.totalReps, 20)
        XCTAssertEqual(workout.volume, 800)
        XCTAssertNil(state.restTimer)
        XCTAssertEqual(workout.restHistory?.last?.elapsedSeconds, 30)
        try state.validate()
        try state.finishWorkout("workout", at: now.addingTimeInterval(150))
        XCTAssertTrue(state.workoutReviews?.last?.summary.contains("1 planned sets were skipped") == true)
        XCTAssertEqual(state.workoutReviews?.last?.exercises.first?.actualWorkingSets, 2)
    }

    func testChooseExerciseAndReturnLaterKeepsOriginalOrderAndProgress() throws {
        var state = try state()
        try state.selectExercise("squat", workoutID: "workout", now: now)
        XCTAssertEqual(state.activeWorkout?.nextExercise?.exerciseID, "squat")
        try log(&state, exerciseID: "squat")
        let timer = try XCTUnwrap(state.restTimer)
        try state.selectExercise("bench_press", workoutID: "workout", now: now.addingTimeInterval(30))
        XCTAssertEqual(state.activeWorkout?.exercises.map(\.exerciseID), ["bench_press", "squat"])
        XCTAssertEqual(state.activeWorkout?.nextExercise?.exerciseID, "bench_press")
        XCTAssertEqual(state.activeWorkout?.exercises[1].workingSetCount, 1)
        XCTAssertNil(state.restTimer)
        XCTAssertEqual(state.activeWorkout?.restHistory?.last?.id, timer.id)
        try state.skipExercise(exerciseID: "bench_press", workoutID: "workout", now: now.addingTimeInterval(35))
        XCTAssertEqual(state.activeWorkout?.nextExercise?.exerciseID, "squat")
        XCTAssertEqual(state.activeWorkout?.nextExercise?.remainingSetCount, 2)
        XCTAssertEqual(state.activeWorkout?.totalSets, 1)
        try state.validate()
    }

    func testSkipRemainingOnlySkipsUnperformedPlannedWorkAndCannotRepeat() throws {
        var state = try state()
        try log(&state)
        try state.skipExercise(exerciseID: "bench_press", workoutID: "workout", now: now)
        XCTAssertEqual(state.activeWorkout?.exercises[0].skippedSetCount, 2)
        XCTAssertEqual(state.activeWorkout?.exercises[0].workingSetCount, 1)
        let unchanged = state
        XCTAssertThrowsError(try state.skipExercise(exerciseID: "bench_press", workoutID: "workout", now: now))
        XCTAssertThrowsError(try state.skipSet(exerciseID: "bench_press", workoutID: "workout", now: now))
        XCTAssertThrowsError(try state.selectExercise("bench_press", workoutID: "workout", now: now))
        XCTAssertEqual(state, unchanged)
    }

    func testFreeformExerciseCanBeSkippedWithoutFakeSet() throws {
        var state = try state()
        try state.updateTarget(nil, exerciseID: "bench_press", workoutID: "workout")
        try state.skipExercise(exerciseID: "bench_press", workoutID: "workout", now: now)
        XCTAssertEqual(state.activeWorkout?.exercises[0].skippedSetCount, 0)
        XCTAssertTrue(state.activeWorkout?.exercises[0].isTargetResolved == true)
        XCTAssertEqual(state.activeWorkout?.nextExercise?.exerciseID, "squat")
        XCTAssertEqual(state.activeWorkout?.totalSets, 0)
        try state.validate()
    }

    func testWarmupsDoNotConsumeRemainingPlannedSets() throws {
        var state = try state()
        try state.addSet(.init(kg: 20, reps: 5, isWarmup: true), exerciseID: "bench_press", workoutID: "workout", now: now)
        try state.skipSet(exerciseID: "bench_press", workoutID: "workout", now: now)
        XCTAssertEqual(state.activeWorkout?.exercises[0].remainingSetCount, 2)
        XCTAssertEqual(state.activeWorkout?.exercises[0].workingSetCount, 0)
        XCTAssertEqual(state.activeWorkout?.exercises[0].sets.count, 1)
    }

    func testNavigationCommandsSurviveRoundTripAndReplayExactlyOnce() throws {
        for action in [WatchAction.selectExercise(exerciseID: "squat"), .skipSet(exerciseID: "bench_press"), .skipExercise(exerciseID: "bench_press")] {
            var state = try state()
            let command = try JSONDecoder().decode(WatchCommand.self, from: JSONEncoder().encode(command(state, action)))
            let accepted = GymaReducer.apply(command, to: &state, now: now)
            XCTAssertEqual(accepted.status, .applied)
            state = try JSONDecoder().decode(GymaState.self, from: JSONEncoder().encode(state))
            let saved = state
            let repeated = GymaReducer.apply(command, to: &state, now: now.addingTimeInterval(3600))
            XCTAssertEqual(repeated.status, .duplicate)
            XCTAssertEqual(repeated.originalStatus, .applied)
            XCTAssertEqual(state, saved)
            try state.validate()
        }
    }

    func testNavigationRejectsMissingRevisionStaleRevisionWrongStoreAndOldWorkout() throws {
        for action in [WatchAction.selectExercise(exerciseID: "squat"), .skipSet(exerciseID: "bench_press"), .skipExercise(exerciseID: "bench_press")] {
            for variant in 0..<4 {
                var state = try state()
                var command = command(state, action)
                switch variant {
                case 0: command.basedOnRevision = nil
                case 1: command.basedOnRevision = state.revision - 1
                case 2: command.storeID = "replaced"
                default: command.workoutID = "finished-workout"
                }
                let before = state.activeWorkout
                XCTAssertEqual(GymaReducer.apply(command, to: &state, now: now).status, .rejected)
                XCTAssertEqual(state.activeWorkout, before)
            }
        }
    }

    func testDelayedSelectionEndsRestAtCommandTimeWithoutRestartingIt() throws {
        var state = try state()
        try log(&state)
        let command = command(state, .selectExercise(exerciseID: "squat"), at: now.addingTimeInterval(30))
        XCTAssertEqual(GymaReducer.apply(command, to: &state, now: now.addingTimeInterval(600)).status, .applied)
        XCTAssertNil(state.restTimer)
        XCTAssertEqual(state.activeWorkout?.restHistory?.last?.elapsedSeconds, 30)
        XCTAssertEqual(state.activeWorkout?.nextExercise?.exerciseID, "squat")
    }

    func testSkippedHistoryAndSelectionPersistAndOldWorkoutsDecode() throws {
        var state = try state()
        try state.skipSet(exerciseID: "bench_press", workoutID: "workout", now: now)
        try state.selectExercise("squat", workoutID: "workout", now: now)
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GymaState.self, from: encoded)
        XCTAssertEqual(decoded, state)
        try decoded.validate()

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state.activeWorkout!)) as? [String: Any])
        legacy.removeValue(forKey: "selectedExerciseID")
        var exercises = try XCTUnwrap(legacy["exercises"] as? [[String: Any]])
        for index in exercises.indices {
            exercises[index].removeValue(forKey: "skippedSets")
            exercises[index].removeValue(forKey: "skippedRemainingAt")
        }
        legacy["exercises"] = exercises
        let old = try JSONDecoder().decode(Workout.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.selectedExerciseID)
        XCTAssertEqual(old.exercises[0].skippedSetCount, 0)
        XCTAssertEqual(old.nextExercise?.exerciseID, "bench_press")
    }

    func testMalformedOrFutureSkippedHistoryIsRejected() throws {
        var state = try state()
        try state.skipSet(exerciseID: "bench_press", workoutID: "workout", now: now.addingTimeInterval(10))
        XCTAssertThrowsError(try state.finishWorkout("workout", at: now))
        let skip = try XCTUnwrap(state.activeWorkout?.exercises[0].skippedSets?.first)
        state.workouts[0].exercises[1].skippedSets = [skip]
        XCTAssertThrowsError(try state.validate())
        state.workouts[0].exercises[1].skippedSets = [.init(skippedAt: now.addingTimeInterval(-1))]
        XCTAssertThrowsError(try state.validate())
    }

    func testNewWorkoutsPlansAndProgramsRejectSkippedState() throws {
        var exercise = WorkoutExercise(exerciseID: "bench_press", target: target)
        for markerOnly in [false, true] {
            exercise.skippedSets = markerOnly ? nil : [.init(skippedAt: now)]
            exercise.skippedRemainingAt = markerOnly ? now : nil
            var state = GymaState()
            XCTAssertThrowsError(try state.startWorkout(.init(start: now, exercises: [exercise])))
            let plan = WorkoutPlan(title: "Today", exercises: [exercise], checkIn: .init(shift: .off, energy: .good), createdAt: now)
            XCTAssertThrowsError(try plan.validate(catalog: state.catalog))
            let program = TrainingProgram(title: "Program", goal: "Strength", sessions: [.init(title: "A", exercises: [exercise])])
            XCTAssertThrowsError(try program.validate(catalog: state.catalog))
        }
    }

    func testSkippedSetsDoNotQualifyAsSuccessfulProgressionOrSessionRotation() throws {
        let session = ProgramSession(id: "a", title: "A", exercises: [.init(exerciseID: "bench_press", target: target)])
        let program = TrainingProgram(id: "program", title: "Program", goal: "Strength", sessions: [session, .init(id: "b", title: "B", exercises: [.init(exerciseID: "squat", target: target)])], createdAt: now, updatedAt: now)
        var state = try state()
        state.workouts[0].programID = program.id
        state.workouts[0].programSessionID = session.id
        state.workouts[0].programRevision = program.revision
        try state.skipExercise(exerciseID: "bench_press", workoutID: "workout", now: now)
        try state.finishWorkout("workout", at: now)
        XCTAssertEqual(program.nextSession(history: state.workouts, now: now)?.id, "a")
        XCTAssertNotEqual(program.recommendations(for: session, history: state.workouts, now: now).first?.action, .increaseLoad)
        XCTAssertEqual(state.workouts[0].volume, 0)
        XCTAssertEqual(state.workouts[0].totalReps, 0)
    }

    func testSnapshotRetainsSelectedExerciseOutsideFirstTwelveAndSkipProgress() throws {
        var state = GymaState()
        let exercises = Array(state.catalog.prefix(13)).map { WorkoutExercise(exerciseID: $0.id, target: target) }
        try state.startWorkout(.init(id: "workout", start: now, exercises: exercises))
        let selectedID = try XCTUnwrap(exercises.last?.exerciseID)
        try state.skipSet(exerciseID: selectedID, workoutID: "workout", now: now)
        try state.selectExercise(selectedID, workoutID: "workout", now: now)
        let snapshot = CompanionSnapshot(state: state, now: now)
        XCTAssertTrue(snapshot.isTruncated)
        XCTAssertEqual(snapshot.activeWorkout?.nextExercise?.exerciseID, selectedID)
        XCTAssertEqual(snapshot.activeWorkout?.nextExercise?.skippedSetCount, 1)
        XCTAssertEqual(snapshot.totalExerciseCount, 13)
        try snapshot.activeWorkout?.validate()
    }
}
