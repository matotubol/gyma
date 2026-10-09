import XCTest
@testable import GymaCore

final class CoachingContinuityTests: XCTestCase {
    func testChangedEquipmentIncrementRequiresCompatibleProgramRules() throws {
        var state = GymaState()
        state.trainingProgram = program
        state.athleteProfile = .init(equipment: [.barbell], loadIncrements: [.init(equipment: .barbell, incrementKg: 5)], updatedAt: now)
        XCTAssertThrowsError(try state.nextProgramPlan(checkIn: checkIn, now: now))
        try state.updateProgressionRule(.init(loadIncrementKg: 5), now: now)
        XCTAssertNoThrow(try state.nextProgramPlan(checkIn: checkIn, now: now))
    }

    func testNewFeedbackInvalidatesAnAlreadyPreparedDraftUntilItIsRegenerated() throws {
        var state = GymaState()
        state.trainingProgram = program
        state.workouts = [completedExposure(id: "previous", daysAgo: 1, program: program)]
        let draft = try state.nextProgramPlan(checkIn: checkIn, now: now)
        try state.saveCoachConversation(.init(checkIn: checkIn, messages: [.init(role: .assistant, content: "Prepared")], plan: draft))
        try state.acceptCoachPlan(planID: draft.id, now: now)
        try state.saveWorkoutFeedback(.init(workoutID: "previous", recordedAt: now.addingTimeInterval(1), painNote: "Discomfort after training"))
        XCTAssertNil(state.coachConversation?.plan?.acceptedAt)
        XCTAssertThrowsError(try state.acceptCoachPlan(planID: draft.id, now: now.addingTimeInterval(2)))
        let updated = try state.nextProgramPlan(checkIn: checkIn, now: now.addingTimeInterval(3))
        try state.saveCoachConversation(.init(checkIn: checkIn, plan: updated))
        XCTAssertNoThrow(try state.acceptCoachPlan(planID: updated.id, now: now.addingTimeInterval(4)))
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var checkIn: SessionCheckIn { .init(shift: .off, energy: .good) }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var program: TrainingProgram {
        .init(id: "program", title: "Repeatable training", goal: "Build strength", sessions: [
            .init(id: "upper", title: "Upper", exercises: [.init(exerciseID: "bench_press", target: target)]),
            .init(id: "lower", title: "Lower", exercises: [.init(exerciseID: "squat", target: target)])
        ], createdAt: now.addingTimeInterval(-10 * 86400), updatedAt: now)
    }
    private var target: ExerciseTarget {
        .init(sets: 2, repsMin: 8, repsMax: 10, loadKg: 60, restSeconds: 90, targetEffort: .challenging)
    }
    private func proposalState() throws -> GymaState {
        var state = GymaState()
        var conversation = CoachConversation(checkIn: checkIn, messages: [.init(role: .assistant, content: "Review this program.")])
        conversation.proposedProgram = program
        try state.saveCoachConversation(conversation)
        return state
    }
    private func completedExposure(id: String, daysAgo: Double, program: TrainingProgram) -> Workout {
        Workout(id: id, start: now.addingTimeInterval(-daysAgo * 86400 - 3600), end: now.addingTimeInterval(-daysAgo * 86400),
                checkIn: checkIn, exercises: [.init(exerciseID: "bench_press", sets: [
                    .init(kg: 60, reps: 10, effort: .challenging, isWarmup: false),
                    .init(kg: 60, reps: 10, effort: .challenging, isWarmup: false)
                ], target: target)], programID: program.id, programSessionID: "upper", programRevision: program.revision)
    }

    func testProgramAcceptanceLinksAnUnacceptedSessionAndRotatesOnlyOnCompletion() throws {
        var state = try proposalState()
        try state.acceptProgramProposal(programID: "program", now: now)
        XCTAssertEqual(state.trainingProgram?.id, "program")
        XCTAssertNil(state.coachConversation?.proposedProgram)
        let plan = try XCTUnwrap(state.coachConversation?.plan)
        XCTAssertNil(plan.acceptedAt)
        XCTAssertEqual(plan.programSessionID, "upper")
        XCTAssertEqual(plan.programRevision, program.revision)
        XCTAssertEqual(try state.nextProgramPlan(checkIn: checkIn, now: now.addingTimeInterval(14 * 86400)).programSessionID, "upper")
        try state.acceptCoachPlan(planID: plan.id, now: now)
        let workoutID = try state.startAcceptedPlan(planID: plan.id, now: now, calendar: calendar)
        XCTAssertEqual(state.activeWorkout?.programID, "program")
        XCTAssertEqual(state.activeWorkout?.programSessionID, "upper")
        XCTAssertEqual(state.activeWorkout?.programRevision, program.revision)
        XCTAssertNil(state.coachConversation?.plan)
        XCTAssertEqual(state.trainingProgram?.nextSession(history: state.workouts, now: now)?.id, "upper")
        state.setRestEnabled(false)
        try state.addSet(.init(kg: 20, reps: 10, isWarmup: true), exerciseID: "bench_press", workoutID: workoutID, now: now.addingTimeInterval(1))
        try state.addSet(.init(kg: 60, reps: 8, effort: .challenging, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now.addingTimeInterval(2))
        try state.finishWorkout(workoutID, at: now.addingTimeInterval(60))
        XCTAssertEqual(try state.nextProgramPlan(checkIn: checkIn, now: now.addingTimeInterval(2 * 86400)).programSessionID, "lower")
        XCTAssertEqual(state.trainingProgram?.sessions.count, 2)
        let review = try XCTUnwrap(state.workoutReviews?.first)
        XCTAssertEqual(review.workoutID, workoutID)
        XCTAssertEqual(review.exercises.first?.actualWorkingSets, 1)
        XCTAssertEqual(review.exercises.first?.warmupSets, 1)
        try state.saveWorkoutFeedback(.init(workoutID: workoutID, recordedAt: now.addingTimeInterval(70), note: "Ran out of time"))
        let restored = try NativeBackup.decode(NativeBackup.encode(state))
        XCTAssertEqual(restored.trainingProgram, state.trainingProgram)
        XCTAssertEqual(restored.workoutReviews, state.workoutReviews)
        XCTAssertEqual(restored.workoutFeedback, state.workoutFeedback)
        XCTAssertEqual(restored.workouts.first?.programSessionID, "upper")
    }

    func testProgramAcceptanceRejectsConflictsAndInvalidDatesWithoutPartialMutation() throws {
        var conflict = try proposalState()
        conflict.athleteProfile = .init(equipment: [.dumbbells], updatedAt: now)
        let beforeConflict = conflict
        XCTAssertThrowsError(try conflict.acceptProgramProposal(programID: "program", now: now))
        XCTAssertEqual(conflict, beforeConflict)

        var wrongIdentity = try proposalState()
        let beforeIdentity = wrongIdentity
        XCTAssertThrowsError(try wrongIdentity.acceptProgramProposal(programID: "replaced-proposal", now: now))
        XCTAssertEqual(wrongIdentity, beforeIdentity)

        var badDate = try proposalState()
        let beforeDate = badDate
        XCTAssertThrowsError(try badDate.acceptProgramProposal(programID: "program", now: program.createdAt.addingTimeInterval(-1)))
        XCTAssertEqual(badDate, beforeDate)

        var active = try proposalState()
        try active.startWorkout(.init(id: "active", start: now))
        let beforeActive = active
        XCTAssertThrowsError(try active.acceptProgramProposal(programID: "program", now: now))
        XCTAssertEqual(active, beforeActive)
    }

    func testRevisedProgramInvalidatesPreviouslyAcceptedSessionLink() throws {
        var state = try proposalState()
        try state.acceptProgramProposal(programID: "program", now: now)
        let planID = try XCTUnwrap(state.coachConversation?.plan?.id)
        try state.acceptCoachPlan(planID: planID, now: now)
        state.trainingProgram?.revision += 1
        let before = state
        XCTAssertThrowsError(try state.startAcceptedPlan(planID: planID, now: now, calendar: calendar))
        XCTAssertEqual(state, before)
        XCTAssertNil(state.activeWorkout)
    }

    func testStandalonePlanRechecksProfileWhenStartingRestoredAcceptance() throws {
        var state = GymaState()
        let plan = WorkoutPlan(id: "standalone", title: "Bench", exercises: [.init(exerciseID: "bench_press", target: target)], checkIn: checkIn, createdAt: now)
        try state.saveCoachConversation(.init(checkIn: checkIn, plan: plan))
        try state.acceptCoachPlan(planID: plan.id, now: now)
        // Simulate an imported accepted plan with a conflicting saved profile.
        state.athleteProfile = .init(equipment: [.dumbbells], updatedAt: now)
        let before = state
        XCTAssertThrowsError(try state.startAcceptedPlan(planID: plan.id, now: now, calendar: calendar))
        XCTAssertEqual(state, before)
    }

    func testPainFeedbackSuppressesOtherwiseEarnedNextLoadIncrease() throws {
        var repeatable = program
        repeatable.sessions = [repeatable.sessions[0]]
        var state = GymaState()
        state.trainingProgram = repeatable
        state.workouts = [completedExposure(id: "latest", daysAgo: 1, program: repeatable), completedExposure(id: "previous", daysAgo: 3, program: repeatable)]
        let before = try state.nextProgramPlan(checkIn: checkIn, now: now)
        XCTAssertEqual(before.exercises.first?.target?.loadKg, 62.5)
        try state.saveWorkoutFeedback(.init(workoutID: "latest", recordedAt: now, note: "Finished all reps", painNote: "Shoulder pain"))
        let after = try state.nextProgramPlan(checkIn: checkIn, now: now)
        XCTAssertNil(after.exercises.first?.target?.loadKg)
        XCTAssertTrue(after.exercises.first?.target?.reason.contains("review") == true)
        XCTAssertEqual(state.workouts.first?.exercises.first?.sets.first?.kg, 60)
    }

    func testCompletedWorkoutChatCanSaveAdviceButCannotChangeTraining() throws {
        var state = GymaState()
        state.workouts = [completedExposure(id: "finished", daysAgo: 1, program: program)]
        let originalTraining = state.workouts[0]
        let revision = state.revision
        try state.appendWorkoutCoachMessage("What should I do next time?", workoutID: "finished")
        let conversation = try XCTUnwrap(state.workouts[0].coachConversation)
        try state.saveWorkoutCoachReply(.init(message: "Review your next session targets."), workoutID: "finished", expectedStoreID: state.storeID,
                                        expectedRevision: revision, expectedConversation: conversation)
        XCTAssertEqual(state.revision, revision)
        XCTAssertEqual(state.workouts[0].exercises, originalTraining.exercises)
        XCTAssertEqual(state.workouts[0].end, originalTraining.end)
        XCTAssertEqual(state.workouts[0].coachConversation?.messages.last?.role, .assistant)

        try state.appendWorkoutCoachMessage("Increase it", workoutID: "finished")
        let pending = try XCTUnwrap(state.workouts[0].coachConversation)
        let before = state
        let change = WorkoutCoachChange(storeID: state.storeID, workoutID: "finished", basedOnRevision: revision,
                                        exerciseID: "bench_press", target: target, reason: "Change next time")
        XCTAssertThrowsError(try state.saveWorkoutCoachReply(.init(message: "Change proposed", change: change), workoutID: "finished",
                                                             expectedStoreID: state.storeID, expectedRevision: revision, expectedConversation: pending))
        XCTAssertEqual(state, before)
    }

    func testProfileEditMakesInFlightWorkoutAdviceStale() throws {
        var state = GymaState()
        state.workouts = [completedExposure(id: "finished", daysAgo: 1, program: program)]
        try state.appendWorkoutCoachMessage("Review this", workoutID: "finished")
        let conversation = try XCTUnwrap(state.workouts[0].coachConversation)
        let revision = state.revision
        try state.saveAthleteProfile(.init(primaryGoal: .strength, updatedAt: now), now: now)
        let before = state
        XCTAssertThrowsError(try state.saveWorkoutCoachReply(.init(message: "Old advice"), workoutID: "finished", expectedStoreID: state.storeID,
                                                             expectedRevision: revision, expectedConversation: conversation))
        XCTAssertEqual(state, before)
    }

    func testLegacyBackupWithoutContinuityFieldsRemainsReadable() throws {
        var original = GymaState()
        original.workouts = [.init(id: "legacy", start: now.addingTimeInterval(-3600), end: now)]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for key in ["athleteProfile", "trainingProgram", "programHistory", "workoutReviews", "workoutFeedback"] { json.removeValue(forKey: key) }
        let restored = try NativeBackup.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.athleteProfile)
        XCTAssertNil(restored.trainingProgram)
        XCTAssertNil(restored.workoutReviews)
        XCTAssertNil(restored.workoutFeedback)
        XCTAssertNil(restored.workouts[0].programID)
        XCTAssertEqual(restored.workouts[0].id, "legacy")
    }

    func testShortSessionKeepsPriorityWorkAndLeavesSavedTemplateUnchanged() throws {
        var longer = program
        let longerTarget = ExerciseTarget(sets: 6, repsMin: 8, repsMax: 12, loadKg: 60, restSeconds: 300, targetEffort: .challenging)
        longer.sessions = [.init(id: "priority", title: "Priority work", exercises: [
            .init(exerciseID: "bench_press", target: longerTarget),
            .init(exerciseID: "squat", target: longerTarget),
            .init(exerciseID: "barbell_row", target: longerTarget)
        ])]
        var state = GymaState()
        state.trainingProgram = longer
        let before = state
        let short = try state.nextProgramPlan(checkIn: .init(shift: .off, energy: .good, timeMinutes: 15), now: now)
        XCTAssertEqual(short.exercises.map(\.exerciseID), ["bench_press"])
        XCTAssertLessThan(try XCTUnwrap(short.exercises.first?.target?.sets), longerTarget.sets)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(short.exercises.first?.target?.sets), 1)
        XCTAssertTrue(short.exercises.first?.target?.reason.contains("Shortened") == true)
        XCTAssertEqual(short.programSessionID, "priority")
        XCTAssertEqual(state, before)
        let full = try state.nextProgramPlan(checkIn: .init(shift: .off, energy: .good, timeMinutes: 120), now: now)
        XCTAssertEqual(full.exercises.map(\.exerciseID), longer.sessions[0].exercises.map(\.exerciseID))
        XCTAssertEqual(full.exercises.map { $0.target?.sets }, [6, 6, 6])
        XCTAssertEqual(state.trainingProgram, longer)
    }
}
