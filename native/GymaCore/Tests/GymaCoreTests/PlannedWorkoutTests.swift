import XCTest
@testable import GymaCore

final class PlannedWorkoutTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var checkIn: SessionCheckIn { .init(shift: .off, energy: .good, timeMinutes: 45) }
    private func proposedPlan() -> WorkoutPlan {
        WorkoutPlan(id: "plan-1", title: "Push session", exercises: [
            .init(exerciseID: "bench_press", target: .init(sets: 2, repsMin: 8, repsMax: 10, loadKg: 60, restSeconds: 90)),
            .init(exerciseID: "squat", target: .init(sets: 2, repsMin: 6, repsMax: 8, loadKg: 80, restSeconds: 120))
        ], checkIn: checkIn, createdAt: now)
    }
    private func plannedState() throws -> GymaState {
        var state = GymaState()
        try state.saveCoachConversation(.init(checkIn: checkIn, messages: [.init(role: .assistant, content: "Here is your proposed session.")], plan: proposedPlan()))
        return state
    }
    private func activeState() throws -> GymaState {
        var state = try plannedState()
        try state.acceptCoachPlan(planID: "plan-1", now: now)
        try state.startAcceptedPlan(planID: "plan-1", now: now)
        return state
    }
    func testPlanMustBeSavedAndExplicitlyAcceptedBeforeStarting() throws {
        var state = GymaState()
        XCTAssertThrowsError(try state.startAcceptedPlan(planID: "plan-1", now: now))
        var plan = proposedPlan(); plan.acceptedAt = now
        try state.saveCoachConversation(.init(checkIn: checkIn, plan: plan))
        XCTAssertNil(state.coachConversation?.plan?.acceptedAt, "Saving model output cannot forge user acceptance.")
        XCTAssertThrowsError(try state.startAcceptedPlan(planID: plan.id, now: now))
        XCTAssertThrowsError(try state.acceptCoachPlan(planID: "old-plan", now: now))
        try state.acceptCoachPlan(planID: plan.id, now: now)
        let workoutID = try state.startAcceptedPlan(planID: plan.id, now: now.addingTimeInterval(5))
        XCTAssertEqual(state.activeWorkout?.id, workoutID)
        XCTAssertEqual(state.activeWorkout?.acceptedPlanID, plan.id)
        XCTAssertEqual(state.activeWorkout?.planAcceptedAt, now)
        XCTAssertEqual(state.activeWorkout?.exercises, plan.exercises)
        XCTAssertNil(state.coachConversation?.plan)
        XCTAssertEqual(state.coachConversation?.startedWorkoutID, workoutID)
        var consumed = try XCTUnwrap(state.coachConversation)
        consumed.plan = plan
        XCTAssertThrowsError(try state.saveCoachConversation(consumed))
        try state.finishWorkout(workoutID, at: now.addingTimeInterval(100))
        XCTAssertThrowsError(try state.startAcceptedPlan(planID: plan.id, now: now.addingTimeInterval(200)))
    }
    func testRevisedPlanRequiresNewAcceptanceAndInvalidSaveIsAtomic() throws {
        var state = try plannedState()
        try state.acceptCoachPlan(planID: "plan-1", now: now)
        var revision = try XCTUnwrap(state.coachConversation)
        revision.plan?.exercises[0].target?.restSeconds = 120
        try state.saveCoachConversation(revision)
        XCTAssertNil(state.coachConversation?.plan?.acceptedAt)
        XCTAssertThrowsError(try state.startAcceptedPlan(planID: "plan-1", now: now))
        try state.acceptCoachPlan(planID: "plan-1", now: now)
        let accepted = state
        revision.plan?.exercises[0].target?.restSeconds = 0
        XCTAssertThrowsError(try state.saveCoachConversation(revision))
        XCTAssertEqual(state, accepted)
        var discussion = try XCTUnwrap(state.coachConversation)
        discussion.plan?.acceptedAt = nil
        discussion.messages.append(.init(role: .user, content: "Could we do less weight?"))
        try state.saveCoachConversation(discussion)
        XCTAssertNil(state.coachConversation?.plan?.acceptedAt)
    }
    func testStartingAcceptedPlanCannotReplaceAnActiveWorkout() throws {
        var state = try activeState()
        try state.saveCoachConversation(.init(checkIn: checkIn, plan: proposedPlan()))
        try state.acceptCoachPlan(planID: "plan-1", now: now)
        let before = state
        XCTAssertThrowsError(try state.startAcceptedPlan(planID: "plan-1", now: now))
        XCTAssertEqual(state, before)
    }
    func testAcceptedAdaptedPlanStillUsesItsRestTargets() throws {
        var plan = proposedPlan()
        plan.checkIn.painNote = "Avoid movements that irritate my shoulder."
        var state = GymaState()
        try state.saveCoachConversation(.init(checkIn: plan.checkIn, plan: plan))
        try state.acceptCoachPlan(planID: plan.id, now: now)
        let workoutID = try state.startAcceptedPlan(planID: plan.id, now: now)
        try state.addSet(.init(kg: 30, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now)
        XCTAssertEqual(state.restTimer?.plannedSeconds, 90)
        try state.validate()
    }
    func testPlanValidationRejectsIncompleteUnsafeOrUnknownTargets() throws {
        let base = proposedPlan()
        let catalog = GymaState().catalog
        XCTAssertNoThrow(try base.validate(catalog: catalog))
        var invalid = base; invalid.exercises = []
        XCTAssertThrowsError(try invalid.validate(catalog: catalog))
        invalid = base; invalid.exercises[0].target = nil
        XCTAssertThrowsError(try invalid.validate(catalog: catalog))
        invalid = base; invalid.exercises[0].exerciseID = "invented-by-coach"
        XCTAssertThrowsError(try invalid.validate(catalog: catalog))
        invalid = base; invalid.exercises.append(invalid.exercises[0])
        XCTAssertThrowsError(try invalid.validate(catalog: catalog))
        invalid = base; invalid.exercises[0].sets = [.init(kg: 60, reps: 8, isWarmup: false)]
        XCTAssertThrowsError(try invalid.validate(catalog: catalog))
        invalid = base; invalid.exercises[0].target?.loadKg = .infinity
        XCTAssertThrowsError(try invalid.validate(catalog: catalog))
        invalid = base; invalid.exercises[0].target?.restSeconds = 601
        XCTAssertThrowsError(try invalid.validate(catalog: catalog))
        invalid = base; invalid.exercises[0].target?.repsMin = 20
        XCTAssertThrowsError(try invalid.validate(catalog: catalog))
        invalid = base; invalid.exercises = catalog.prefix(13).map { .init(exerciseID: $0.id, target: base.exercises[0].target) }
        XCTAssertThrowsError(try invalid.validate(catalog: catalog))
    }
    func testActualRestWaitsForAcknowledgementBeforeOrAfterDeadline() throws {
        for duration in [30.0, 150.0] {
            var state = try activeState()
            let workoutID = try XCTUnwrap(state.activeWorkout?.id)
            try state.addSet(.init(id: "set-1", kg: 55, reps: 7, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now)
            let timer = try XCTUnwrap(state.restTimer)
            XCTAssertNil(state.activeWorkout?.restHistory)
            XCTAssertEqual(timer.remaining(at: now.addingTimeInterval(100)), 0)
            try state.skipRest(timerID: timer.id, now: now.addingTimeInterval(duration))
            let rest = try XCTUnwrap(state.activeWorkout?.restHistory?.first)
            XCTAssertEqual(rest.id, timer.id)
            XCTAssertEqual(rest.sourceSetID, "set-1")
            XCTAssertEqual(rest.plannedSeconds, 90)
            XCTAssertEqual(rest.elapsedSeconds, duration)
            XCTAssertNil(state.restTimer)
            XCTAssertThrowsError(try state.skipRest(timerID: timer.id, now: now.addingTimeInterval(200)))
            XCTAssertEqual(state.activeWorkout?.restHistory?.count, 1)
            try state.validate()
        }
    }
    func testDelayedAcknowledgementUsesWatchTimeAndSurvivesDuplicateDelivery() throws {
        var state = try activeState()
        let workoutID = try XCTUnwrap(state.activeWorkout?.id)
        try state.addSet(.init(id: "set-1", kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now)
        let timerID = try XCTUnwrap(state.restTimer?.id)
        let command = WatchCommand(id: "start-next-set", storeID: state.storeID, workoutID: workoutID, basedOnRevision: state.revision,
                                   createdAt: now.addingTimeInterval(110), action: .skipRest(timerID: timerID))
        XCTAssertEqual(GymaReducer.apply(command, to: &state, now: now.addingTimeInterval(400)).status, .applied)
        var reloaded = try NativeBackup.decode(NativeBackup.encode(state))
        XCTAssertEqual(GymaReducer.apply(command, to: &reloaded, now: now.addingTimeInterval(500)).status, .duplicate)
        XCTAssertEqual(reloaded.activeWorkout?.restHistory?.count, 1)
        XCTAssertEqual(reloaded.activeWorkout?.restHistory?.first?.elapsedSeconds, 110)
    }
    func testRestExtensionPreservesOriginalPlanAndCapturesActualTime() throws {
        var state = try activeState()
        let workoutID = try XCTUnwrap(state.activeWorkout?.id)
        try state.addSet(.init(id: "first", kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now)
        let timerID = try XCTUnwrap(state.restTimer?.id)
        try state.extendRest(timerID: timerID, seconds: 30, now: now.addingTimeInterval(30))
        XCTAssertEqual(state.restTimer?.endsAt, now.addingTimeInterval(120))
        try state.skipRest(timerID: timerID, now: now.addingTimeInterval(135))
        XCTAssertEqual(state.activeWorkout?.restHistory?.first?.plannedSeconds, 90)
        XCTAssertEqual(state.activeWorkout?.restHistory?.first?.elapsedSeconds, 135)
    }
    func testDelayedFinishClosesRestAtWatchTime() throws {
        var state = try activeState()
        let workoutID = try XCTUnwrap(state.activeWorkout?.id)
        try state.addSet(.init(id: "first", kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now)
        let command = WatchCommand(storeID: state.storeID, workoutID: workoutID, basedOnRevision: state.revision,
                                   createdAt: now.addingTimeInterval(45), action: .finishWorkout)
        XCTAssertEqual(GymaReducer.apply(command, to: &state, now: now.addingTimeInterval(300)).status, .applied)
        XCTAssertEqual(state.workouts[0].end, now.addingTimeInterval(45))
        XCTAssertEqual(state.workouts[0].restHistory?.first?.elapsedSeconds, 45)
        XCTAssertNil(state.activeWorkout)
    }
    func testSnapshotKeepsOnlyLatestRestWhenItsSourceSetIsPresent() throws {
        var state = try activeState()
        let workoutID = try XCTUnwrap(state.activeWorkout?.id)
        try state.addSet(.init(id: "first", kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now)
        try state.skipRest(timerID: XCTUnwrap(state.restTimer?.id), now: now.addingTimeInterval(90))
        try state.addSet(.init(id: "second", kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now.addingTimeInterval(120))
        try state.addSet(.init(id: "squat", kg: 80, reps: 6, isWarmup: false), exerciseID: "squat", workoutID: workoutID, now: now.addingTimeInterval(180))
        try state.skipRest(timerID: XCTUnwrap(state.restTimer?.id), now: now.addingTimeInterval(310))
        let snapshot = CompanionSnapshot(state: state, now: now.addingTimeInterval(320))
        XCTAssertEqual(snapshot.activeWorkout?.restHistory?.count, 1)
        XCTAssertEqual(snapshot.activeWorkout?.restHistory?.first?.sourceSetID, "squat")
        XCTAssertEqual(state.activeWorkout?.restHistory?.count, 2)
        try snapshot.activeWorkout?.validate()
    }
    func testRestFallbackClosesOnLoggingAndFinishWithoutPartialMutation() throws {
        var state = try activeState()
        let workoutID = try XCTUnwrap(state.activeWorkout?.id)
        try state.addSet(.init(id: "first", kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now.addingTimeInterval(10))
        let before = state
        XCTAssertThrowsError(try state.addSet(.init(id: "too-early", kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now))
        XCTAssertEqual(state, before)
        try state.addSet(.init(id: "second", kg: 60, reps: 7, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now.addingTimeInterval(70))
        XCTAssertEqual(state.activeWorkout?.restHistory?.first?.elapsedSeconds, 60)
        XCTAssertNil(state.restTimer, "A completed exercise does not start another set rest.")
        try state.addSet(.init(id: "squat", kg: 80, reps: 6, isWarmup: false), exerciseID: "squat", workoutID: workoutID, now: now.addingTimeInterval(100))
        try state.finishWorkout(workoutID, at: now.addingTimeInterval(250))
        XCTAssertEqual(state.workouts[0].restHistory?.map(\.elapsedSeconds), [60, 150])
        try state.validate()
    }
    func testDeletingRestSourcePrunesItsHistory() throws {
        var state = try activeState()
        let workoutID = try XCTUnwrap(state.activeWorkout?.id)
        try state.addSet(.init(id: "first", kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now)
        try state.skipRest(timerID: XCTUnwrap(state.restTimer?.id), now: now.addingTimeInterval(100))
        try state.removeSet("first", exerciseID: "bench_press", workoutID: workoutID)
        XCTAssertTrue(state.activeWorkout?.restHistory?.isEmpty ?? false)
        try state.validate()
    }
    func testSnapshotProgressSurvivesRecentSetWindowAndExcludesConversationAndRest() throws {
        var state = try activeState()
        let workoutID = try XCTUnwrap(state.activeWorkout?.id)
        try state.addSet(.init(id: "first", kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now)
        try state.skipRest(timerID: XCTUnwrap(state.restTimer?.id), now: now.addingTimeInterval(90))
        try state.addSet(.init(id: "second", kg: 60, reps: 7, isWarmup: false), exerciseID: "bench_press", workoutID: workoutID, now: now.addingTimeInterval(120))
        for index in 0..<25 {
            try state.addSet(.init(id: "warmup-\(index)", kg: 20, reps: 5, isWarmup: true), exerciseID: "bench_press", workoutID: workoutID, now: now.addingTimeInterval(150))
        }
        let snapshot = CompanionSnapshot(state: state, now: now.addingTimeInterval(200))
        XCTAssertTrue(snapshot.isTruncated)
        XCTAssertEqual(snapshot.totalExerciseCount, 2)
        XCTAssertEqual(snapshot.totalExerciseCount, snapshot.activeWorkout?.exercises.count)
        XCTAssertEqual(snapshot.activeWorkout?.exercises.first?.sets.count, 20)
        XCTAssertEqual(snapshot.activeWorkout?.exercises.first?.workingSetCount, 2)
        XCTAssertEqual(snapshot.activeWorkout?.exercises.first?.isTargetComplete, true)
        XCTAssertEqual(snapshot.activeWorkout?.nextExercise?.exerciseID, "squat")
        XCTAssertNil(snapshot.activeWorkout?.restHistory)
        XCTAssertEqual(state.activeWorkout?.restHistory?.count, 1)
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(json.contains("Here is your proposed session"))
        XCTAssertFalse(json.contains("elapsedSeconds"))
    }
    func testSnapshotReportsOmittedExercisesSeparatelyFromSetTruncation() throws {
        var state = GymaState()
        let entries = state.catalog.prefix(13).map { WorkoutExercise(exerciseID: $0.id) }
        try state.startWorkout(.init(start: now, exercises: entries))
        let snapshot = CompanionSnapshot(state: state, now: now)
        XCTAssertTrue(snapshot.isTruncated)
        XCTAssertEqual(snapshot.totalExerciseCount, 13)
        XCTAssertEqual(snapshot.activeWorkout?.exercises.count, 12)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        legacy.removeValue(forKey: "totalExerciseCount")
        let decoded = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.totalExerciseCount)
        XCTAssertTrue(decoded.isTruncated)
    }
    func testLegacyStateWithoutNewOptionalFieldsStillDecodes() throws {
        var state = GymaState()
        try state.startWorkout(.init(id: "legacy", start: now, exercises: [.init(exerciseID: "bench_press")]))
        let encoded = try JSONEncoder().encode(state)
        let string = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(string.contains("coachConversation"))
        XCTAssertFalse(string.contains("restHistory"))
        XCTAssertFalse(string.contains("snapshotWorkingSetCount"))
        XCTAssertFalse(string.contains("acceptedPlanID"))
        let legacy = try NativeBackup.decode(encoded)
        XCTAssertEqual(legacy, state)
        XCTAssertNil(legacy.coachConversation)
        XCTAssertNil(legacy.activeWorkout?.restHistory)
        XCTAssertEqual(legacy.activeWorkout?.exercises.first?.workingSetCount, 0)
    }
}
