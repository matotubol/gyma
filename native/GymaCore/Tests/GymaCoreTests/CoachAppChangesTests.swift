import XCTest
@testable import GymaCore

final class CoachAppChangesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var target: ExerciseTarget { .init(sets: 3, repsMin: 8, repsMax: 12, loadKg: 50, restSeconds: 120, targetEffort: .challenging) }
    private var program: TrainingProgram {
        .init(id: "program", title: "My program", goal: "Build strength", sessions: [
            .init(id: "upper", title: "Upper", exercises: [.init(exerciseID: "bench_press", target: target)]),
            .init(id: "lower", title: "Lower", exercises: [.init(exerciseID: "squat", target: target)])
        ], createdAt: now.addingTimeInterval(-86400), updatedAt: now.addingTimeInterval(-86400))
    }
    private var workout: Workout {
        .init(id: "workout", start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1800),
              planTitle: "Upper", exercises: [.init(exerciseID: "bench_press", sets: [
                .init(id: "set", kg: 50, reps: 8, effort: .challenging, isWarmup: false)
              ], target: target)], programID: "program", programSessionID: "upper", programRevision: 1)
    }
    private var calendar: TrainingCalendarPlan {
        .init(startDate: now, cycleAnchorDate: now, trainingCycleDays: [2, 5, 8], timeZone: TimeZone(secondsFromGMT: 0)!)
    }
    private func apply(_ changes: [CoachAppChange], to state: inout GymaState) throws {
        let proposal = try CoachAppChangeProposal(changes: changes, state: state, now: now)
        try state.applyCoachAppChanges(proposal, now: now)
    }

    func testProgramRevisionCanRenameAddSessionChangeTargetsDuringActiveWorkout() throws {
        var state = GymaState(); state.trainingProgram = program
        var active = workout; active.end = nil; state.workouts = [active]
        var revised = program
        revised.title = "Upper lower plus accessories"
        revised.sessions[0].title = "Push and pull"
        revised.sessions[0].exercises[0].target = .init(sets: 4, repsMin: 6, repsMax: 8, loadKg: 55, restSeconds: 150)
        revised.sessions.append(.init(id: "extra", title: "Accessories", exercises: [.init(exerciseID: "biceps_curl", target: target)]))
        let proposal = try CoachAppChangeProposal(changes: [.init(kind: .replaceProgram, program: revised)], state: state, now: now)
        XCTAssertTrue(proposal.summaries[0].contains("4 × 6–8 reps"))
        XCTAssertTrue(proposal.summaries[0].contains("Accessories"))
        XCTAssertEqual(state.trainingProgram, program)
        try proposal.apply(to: &state, now: now)
        XCTAssertEqual(state.trainingProgram?.revision, 2)
        XCTAssertEqual(state.trainingProgram?.createdAt, program.createdAt)
        XCTAssertEqual(state.trainingProgram?.sessions.map(\.id), ["upper", "lower", "extra"])
        XCTAssertEqual(state.programHistory, [program])
        XCTAssertEqual(state.workouts, [active])
        XCTAssertEqual(state.revision, 1)
        try state.validate()
    }

    func testProgramDeleteArchivesAndKeepsCompletedHistory() throws {
        var state = GymaState(); state.trainingProgram = program; state.workouts = [workout]
        try apply([.init(kind: .deleteProgram, programID: program.id)], to: &state)
        XCTAssertNil(state.trainingProgram)
        XCTAssertEqual(state.programHistory, [program])
        XCTAssertEqual(state.workouts, [workout])
        XCTAssertThrowsError(try apply([.init(kind: .deleteProgram, programID: program.id)], to: &state))
    }

    func testBatchFailureRollsBackEarlierChangesAndRevision() throws {
        var state = GymaState(); state.workouts = [workout]
        let original = state
        let proposal = CoachAppChangeProposal(baseStoreID: state.storeID, baseRevision: state.revision, changes: [
            .init(kind: .renameWorkout, workoutID: workout.id, name: "Renamed"),
            .init(kind: .correctSet, exerciseID: "bench_press", workoutID: workout.id,
                  set: .init(id: "set", kg: -5, reps: 8), setID: "set")
        ])
        XCTAssertThrowsError(try state.applyCoachAppChanges(proposal, now: now))
        XCTAssertEqual(state, original)
    }

    func testStaleRevisionAndDifferentStoreCannotApply() throws {
        var state = GymaState()
        let proposal = try CoachAppChangeProposal(changes: [.init(kind: .setRestEnabled, enabled: false)], state: state, now: now)
        state.revision += 1
        XCTAssertThrowsError(try state.applyCoachAppChanges(proposal, now: now))
        state.revision = 0; state.storeID = "restored-backup"
        XCTAssertThrowsError(try state.applyCoachAppChanges(proposal, now: now))
        XCTAssertTrue(state.restEnabled)
    }

    func testCalendarCycleExtraDayMoveAndActivityAreAtomic() throws {
        var state = GymaState(); state.trainingCalendar = calendar
        var revised = calendar; revised.trainingCycleDays = [2, 6, 9]; revised.prefersUpperLower = false
        let tomorrow = revised.date(at: 1)!, thirdDay = revised.date(at: 2)!
        try apply([
            .init(kind: .configureCalendar, calendar: revised),
            .init(kind: .setTrainingDay, date: now, enabled: true),
            .init(kind: .moveTrainingDay, date: tomorrow, destinationDate: thirdDay),
            .init(kind: .setActivity, date: now, enabled: true, activityKind: .inclineWalking, durationMinutes: 25),
            .init(kind: .completeActivity, date: now, enabled: true, activityKind: .inclineWalking)
        ], to: &state)
        XCTAssertEqual(state.trainingCalendar?.trainingCycleDays, [2, 6, 9])
        XCTAssertEqual(state.trainingCalendar?.prefersUpperLower, false)
        XCTAssertEqual(state.trainingCalendar?.isTrainingDay(on: now), true)
        XCTAssertEqual(state.trainingCalendar?.isTrainingDay(on: tomorrow), false)
        XCTAssertEqual(state.trainingCalendar?.isTrainingDay(on: thirdDay), true)
        XCTAssertEqual(state.trainingCalendar?.activities(on: now).first?.durationMinutes, 25)
        XCTAssertEqual(state.trainingCalendar?.activities(on: now).first?.isCompleted, true)
        XCTAssertEqual(state.revision, 1)
        try state.validate()
    }

    func testCalendarConfigurationCannotDropSavedDayEdits() throws {
        var state = GymaState(); state.trainingCalendar = calendar
        try state.setCalendarTrainingDay(on: now, isTraining: true, now: now)
        let original = state
        XCTAssertThrowsError(try apply([.init(kind: .configureCalendar, calendar: calendar)], to: &state))
        XCTAssertEqual(state, original)
    }

    func testActivitySummaryUsesPreservedActualDuration() throws {
        var state = GymaState(); state.trainingCalendar = calendar
        try state.setCalendarActivity(on: now, kind: .inclineWalking, isPlanned: true, durationMinutes: 35, now: now)
        let proposal = try CoachAppChangeProposal(changes: [.init(kind: .setActivity, date: now, enabled: true, activityKind: .inclineWalking)], state: state, now: now)
        XCTAssertTrue(proposal.summaries[0].contains("35 minutes"))
    }

    func testBuiltInRenameDeleteAndRestorePreserveWorkoutIdentityAndBackup() throws {
        var state = GymaState(); state.workouts = [workout]
        state.workoutReviews = [.make(workout: workout, history: state.workouts, program: nil, catalog: state.catalog, now: now)]
        var bench = state.exercise("bench_press"); bench.name = "My bench press"
        try apply([.init(kind: .upsertExercise, exercise: bench), .init(kind: .deleteExercise, exerciseID: bench.id)], to: &state)
        XCTAssertEqual(state.exercise(bench.id).name, bench.name)
        XCTAssertFalse(state.availableExercises.contains { $0.id == bench.id })
        XCTAssertEqual(state.workouts, [workout])
        XCTAssertEqual(state.workoutReviews?.first?.exercises.first?.exerciseName, bench.name)
        XCTAssertEqual(state.workoutReviews?.first?.exercises.first?.actualWorkingSets, 1)
        XCTAssertEqual(try NativeBackup.decode(NativeBackup.encode(state)), state)
        try apply([.init(kind: .upsertExercise, exercise: bench)], to: &state)
        XCTAssertTrue(state.availableExercises.contains { $0.id == bench.id })
    }

    func testOlderBackupWithoutCatalogEditFieldsStillLoads() throws {
        let state = GymaState()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: NativeBackup.encode(state)) as? [String: Any])
        json.removeValue(forKey: "exerciseOverrides"); json.removeValue(forKey: "hiddenExerciseIDs")
        let restored = try NativeBackup.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.catalog, ExerciseCatalog.builtIn)
        XCTAssertNil(restored.exerciseOverrides); XCTAssertNil(restored.hiddenExerciseIDs)
    }

    func testUsedExerciseCannotChangeWeightMeaning() throws {
        var state = GymaState(); state.workouts = [workout]
        var bench = state.exercise("bench_press")
        bench.metadata = .init(primaryMuscles: [.chest], equipment: .dumbbells, loadConvention: .perDumbbell)
        XCTAssertThrowsError(try apply([.init(kind: .upsertExercise, exercise: bench)], to: &state))
        XCTAssertEqual(state.exercise("bench_press").trainingMetadata?.equipment, .barbell)
    }

    func testNewExerciseAndProgramCanBeAddedInOneBatch() throws {
        var state = GymaState()
        let exercise = ExerciseDefinition(id: "custom_row", name: "Chest supported row", muscle: .back,
                                          metadata: .init(primaryMuscles: [.upperBack], equipment: .machines))
        var revised = program; revised.sessions[0].exercises = [.init(exerciseID: exercise.id, target: target)]
        try apply([.init(kind: .upsertExercise, exercise: exercise), .init(kind: .replaceProgram, program: revised)], to: &state)
        XCTAssertEqual(state.customExercises.first?.id, exercise.id)
        XCTAssertEqual(state.trainingProgram?.sessions[0].exercises[0].exerciseID, exercise.id)
        try state.validate()
    }

    func testLoggedSetCorrectionRegeneratesReviewAndRetainsID() throws {
        var state = GymaState(); state.workouts = [workout]; state.trainingProgram = program
        let corrected = WorkSet(id: "set", kg: 55, reps: 10, effort: .easy, isWarmup: false)
        try apply([.init(kind: .correctSet, exerciseID: "bench_press", workoutID: workout.id, set: corrected, setID: "set")], to: &state)
        XCTAssertEqual(state.workouts[0].exercises[0].sets, [corrected])
        XCTAssertEqual(state.workoutReviews?.first?.workoutID, workout.id)
        XCTAssertThrowsError(try apply([.init(kind: .correctSet, exerciseID: "bench_press", workoutID: workout.id,
                                            set: .init(id: "different", kg: 60, reps: 8), setID: "set")], to: &state))
    }

    func testWorkoutManagementProfileAndRestSetting() throws {
        var state = GymaState(); state.workouts = [workout]
        let profile = AthleteProfile(primaryGoal: .strength, daysPerWeek: 4, equipment: [.barbell], updatedAt: now)
        try apply([
            .init(kind: .renameWorkout, workoutID: workout.id, name: "Monday upper"),
            .init(kind: .setWorkoutTarget, exerciseID: "bench_press", workoutID: workout.id, target: .init(sets: 4, repsMin: 6, repsMax: 8)),
            .init(kind: .addWorkoutExercise, exerciseID: "biceps_curl", workoutID: workout.id, target: target),
            .init(kind: .removeSet, exerciseID: "bench_press", workoutID: workout.id, setID: "set"),
            .init(kind: .removeWorkoutExercise, exerciseID: "biceps_curl", workoutID: workout.id),
            .init(kind: .updateProfile, profile: profile),
            .init(kind: .setRestEnabled, enabled: false),
            .init(kind: .deleteWorkout, workoutID: workout.id),
            .init(kind: .restoreWorkout, workoutID: workout.id)
        ], to: &state)
        XCTAssertEqual(state.workouts[0].planTitle, "Monday upper")
        XCTAssertEqual(state.workouts[0].exercises[0].target?.sets, 4)
        XCTAssertEqual(state.workouts[0].totalSets, 0)
        XCTAssertEqual(state.workouts[0].exercises.count, 1)
        XCTAssertEqual(state.athleteProfile?.daysPerWeek, 4)
        XCTAssertFalse(state.restEnabled)
        XCTAssertTrue(state.deletedWorkouts.isEmpty)
        try apply([.init(kind: .clearProfile)], to: &state)
        XCTAssertNil(state.athleteProfile)
        try state.validate()
    }

    func testUnexpectedPayloadAndEmptyBatchAreRejected() throws {
        let state = GymaState()
        XCTAssertThrowsError(try CoachAppChangeProposal(changes: [], state: state, now: now))
        XCTAssertThrowsError(try CoachAppChangeProposal(changes: [.init(kind: .setRestEnabled, enabled: false, workoutID: "ignored")], state: state, now: now))
        XCTAssertThrowsError(try CoachAppChangeProposal(changes: [.init(kind: .renameWorkout, workoutID: "missing")], state: state, now: now))
    }

    func testRestPreferenceAndWorkoutNameKeepAcceptedDailyPlan() throws {
        var state = GymaState(); state.workouts = [workout]
        let checkIn = SessionCheckIn(shift: .off, energy: .good)
        let plan = WorkoutPlan(title: "Today's session", exercises: [.init(exerciseID: "bench_press", target: target)],
                               checkIn: checkIn, createdAt: now, acceptedAt: now, scheduledFor: now)
        state.coachConversation = .init(checkIn: checkIn, plan: plan)
        try apply([.init(kind: .setRestEnabled, enabled: false),
                   .init(kind: .renameWorkout, workoutID: workout.id, name: "New title")], to: &state)
        XCTAssertEqual(state.coachConversation?.plan, plan)
    }

    func testExerciseRenameCannotCollideWithAnotherName() throws {
        var state = GymaState()
        var bench = state.exercise("bench_press")
        bench.name = "  \(state.exercise("squat").name.lowercased())  "
        XCTAssertThrowsError(try apply([.init(kind: .upsertExercise, exercise: bench)], to: &state))
        XCTAssertEqual(state.exercise("bench_press").name, ExerciseCatalog.builtIn.first { $0.id == "bench_press" }?.name)
    }
}
