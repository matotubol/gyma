import XCTest
@testable import GymaCore

final class WorkoutCoachTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)
    private let target = ExerciseTarget(sets: 3, repsMin: 8, repsMax: 10, loadKg: 40, restSeconds: 90)

    private func stateWithLoggedSet() throws -> GymaState {
        var state = GymaState()
        var soreness = Soreness.allNone; soreness[.legs] = .high
        let workout = Workout(id: "active", start: start, energy: .medium,
                              checkIn: .init(shift: .off, energy: .good, notes: "CURRENT_NOTE"),
                              readiness: .init(energy: .medium, soreness: soreness, recordedAt: start),
                              exercises: [.init(exerciseID: "bench_press", target: target),
                                          .init(exerciseID: "lat_pulldown", target: target)])
        try state.startWorkout(workout)
        try state.addSet(.init(id: "set-one", kg: 40, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "active", now: start.addingTimeInterval(30))
        return state
    }

    private func change(in state: GymaState, exerciseID: String = "bench_press", replacement: String? = nil,
                        sets: Int = 3) -> WorkoutCoachChange {
        WorkoutCoachChange(storeID: state.storeID, workoutID: "active", basedOnRevision: state.revision,
                           exerciseID: exerciseID, replacementExerciseID: replacement,
                           target: .init(sets: sets, repsMin: 6, repsMax: 8, loadKg: 35, restSeconds: 120, reason: "Keep the remaining sets comfortable."),
                           reason: "Keep the remaining sets comfortable.")
    }

    private func save(_ proposal: WorkoutCoachChange?, in state: inout GymaState) throws {
        try state.appendWorkoutCoachMessage("Please adjust my workout.", workoutID: "active")
        let conversation = try XCTUnwrap(state.activeWorkout?.coachConversation)
        try state.saveWorkoutCoachReply(.init(message: "Here is a suggestion for your review.", change: proposal), workoutID: "active",
                                        expectedStoreID: state.storeID, expectedRevision: state.revision, expectedConversation: conversation)
    }

    func testAdvicePersistsWithoutChangingTrainingRevisionAndRetryDoesNotDuplicate() throws {
        var state = try stateWithLoggedSet()
        let revision = state.revision
        let originalSets = state.activeWorkout?.exercises
        try state.appendWorkoutCoachMessage("How was my last set?", workoutID: "active")
        try state.appendWorkoutCoachMessage("How was my last set?", workoutID: "active")
        XCTAssertEqual(state.activeWorkout?.coachConversation?.messages.count, 1)
        let conversation = try XCTUnwrap(state.activeWorkout?.coachConversation)
        try state.saveWorkoutCoachReply(.init(message: "You logged eight reps at 40kg."), workoutID: "active",
                                        expectedStoreID: state.storeID, expectedRevision: revision, expectedConversation: conversation)
        XCTAssertEqual(state.revision, revision)
        XCTAssertEqual(state.activeWorkout?.exercises, originalSets)
        XCTAssertEqual(state.activeWorkout?.coachConversation?.messages.count, 2)
        XCTAssertNil(state.activeWorkout?.coachConversation?.proposal)
        let restored = try JSONDecoder().decode(GymaState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
        XCTAssertNil(CompanionSnapshot(state: state).activeWorkout?.coachConversation)
    }

    func testApplyingTargetChangePreservesCompletedSetsRestsReadinessAndCurrentTimer() throws {
        var state = try stateWithLoggedSet()
        try state.skipRest(timerID: XCTUnwrap(state.restTimer).id, now: start.addingTimeInterval(100))
        try state.addSet(.init(id: "set-two", kg: 40, reps: 7, isWarmup: false), exerciseID: "bench_press", workoutID: "active", now: start.addingTimeInterval(140))
        let original = try XCTUnwrap(state.activeWorkout)
        let timer = state.restTimer
        let proposal = change(in: state, sets: 4)
        try save(proposal, in: &state)
        let revision = state.revision
        try state.applyWorkoutCoachChange(proposal.id, workoutID: "active")
        let changed = try XCTUnwrap(state.activeWorkout)
        XCTAssertEqual(changed.exercises[0].target, proposal.target)
        XCTAssertEqual(changed.exercises.map(\.sets), original.exercises.map(\.sets))
        XCTAssertEqual(changed.exercises[1], original.exercises[1])
        XCTAssertEqual(changed.restHistory, original.restHistory)
        XCTAssertEqual(state.restTimer, timer)
        XCTAssertEqual(changed.readiness, original.readiness)
        XCTAssertEqual(changed.checkIn, original.checkIn)
        XCTAssertEqual(changed.start, original.start)
        XCTAssertNil(changed.coachConversation?.proposal)
        XCTAssertEqual(state.revision, revision + 1)
        try state.validate()
    }

    func testSwapOnlyTouchesUnstartedExerciseAtOriginalPosition() throws {
        var state = try stateWithLoggedSet()
        let original = try XCTUnwrap(state.activeWorkout)
        let proposal = change(in: state, exerciseID: "lat_pulldown", replacement: "squat")
        try save(proposal, in: &state)
        try state.applyWorkoutCoachChange(proposal.id, workoutID: "active")
        XCTAssertEqual(state.activeWorkout?.exercises.map(\.exerciseID), ["bench_press", "squat"])
        XCTAssertEqual(state.activeWorkout?.exercises[0], original.exercises[0])
        XCTAssertEqual(state.activeWorkout?.exercises[1].target, proposal.target)
        XCTAssertTrue(state.activeWorkout?.exercises[1].sets.isEmpty == true)
        try state.validate()
    }

    func testStartedCompletedDuplicateUnknownAndTruncatedTargetsCannotBeEdited() throws {
        var state = try stateWithLoggedSet()
        let workout = try XCTUnwrap(state.activeWorkout)
        for proposal in [change(in: state, replacement: "squat"),
                         change(in: state, exerciseID: "lat_pulldown", replacement: "bench_press"),
                         change(in: state, exerciseID: "lat_pulldown", replacement: "unknown"),
                         change(in: state, sets: 1)] {
            XCTAssertThrowsError(try proposal.validate(for: workout, catalog: state.catalog))
        }
        try state.addSet(.init(kg: 40, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "active", now: start.addingTimeInterval(130))
        try state.addSet(.init(kg: 40, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "active", now: start.addingTimeInterval(230))
        XCTAssertThrowsError(try change(in: state, sets: 4).validate(for: XCTUnwrap(state.activeWorkout), catalog: state.catalog))
    }

    func testRepliesAreRejectedWhenSetsRestStoreOrConversationChanged() throws {
        var state = try stateWithLoggedSet()
        try state.appendWorkoutCoachMessage("Is this load okay?", workoutID: "active")
        let conversation = try XCTUnwrap(state.activeWorkout?.coachConversation)
        let revision = state.revision
        let storeID = state.storeID
        let reply = WorkoutCoachReply(message: "Advice based on the earlier set.")
        var changedSet = state
        try changedSet.addSet(.init(kg: 35, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "active", now: start.addingTimeInterval(140))
        var changedRest = state
        try changedRest.extendRest(timerID: XCTUnwrap(state.restTimer).id, now: start.addingTimeInterval(60))
        var changedStore = state; changedStore.storeID = "restored-store"
        var changedConversation = state
        try changedConversation.appendWorkoutCoachMessage("Actually, my shoulder is uncomfortable.", workoutID: "active")
        for changed in [changedSet, changedRest, changedStore, changedConversation] {
            var copy = changed
            XCTAssertThrowsError(try copy.saveWorkoutCoachReply(reply, workoutID: "active", expectedStoreID: storeID,
                                                                 expectedRevision: revision, expectedConversation: conversation))
            XCTAssertEqual(copy, changed)
        }
    }

    func testStaleAndFinishedProposalsCannotApplyOrMutateHistory() throws {
        var state = try stateWithLoggedSet()
        let proposal = change(in: state)
        try save(proposal, in: &state)
        var changed = state
        try changed.addSet(.init(kg: 40, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "active", now: start.addingTimeInterval(140))
        let before = changed
        XCTAssertThrowsError(try changed.applyWorkoutCoachChange(proposal.id, workoutID: "active"))
        XCTAssertEqual(changed, before)
        try state.finishWorkout("active", at: start.addingTimeInterval(200))
        let finished = state
        XCTAssertThrowsError(try state.applyWorkoutCoachChange(proposal.id, workoutID: "active"))
        XCTAssertEqual(state, finished)
        try state.appendWorkoutCoachMessage("Review the result and my next session.", workoutID: "active")
        let conversation = try XCTUnwrap(state.workouts.first?.coachConversation)
        XCTAssertEqual(conversation.messages.last?.content, "Review the result and my next session.")
        XCTAssertNil(conversation.proposal)
        try state.saveWorkoutCoachReply(.init(message: "Your completed sets stay recorded. Let's discuss the next session."),
                                         workoutID: "active", expectedStoreID: state.storeID,
                                         expectedRevision: state.revision, expectedConversation: conversation)
        XCTAssertEqual(state.workouts.first?.exercises, finished.workouts.first?.exercises)
        XCTAssertEqual(state.workouts.first?.restHistory, finished.workouts.first?.restHistory)
        XCTAssertEqual(state.workouts.first?.readiness, finished.workouts.first?.readiness)
        XCTAssertEqual(state.workouts.first?.end, finished.workouts.first?.end)
        XCTAssertEqual(state.workoutReviews, finished.workoutReviews)
        XCTAssertEqual(state.revision, finished.revision)
        XCTAssertEqual(state.workouts.first?.coachConversation?.messages.last?.role, .assistant)
    }
}
