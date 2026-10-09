import XCTest
@testable import GymaCore

final class WatchSetFlowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func state() -> GymaState {
        var state = GymaState()
        state.storeID = "phone-store"
        state.workouts = [.init(id: "workout", start: now, exercises: [
            .init(exerciseID: "bench_press", target: .init(sets: 2, repsMin: 8, repsMax: 10, loadKg: 40, restSeconds: 90)),
            .init(exerciseID: "squat", target: .init(sets: 2, repsMin: 6, repsMax: 8, loadKg: 60, restSeconds: 120))
        ])]
        return state
    }

    private func snapshot(_ state: GymaState) -> CompanionSnapshot { .init(state: state, now: now) }

    private func readyFlow(_ state: GymaState) -> WatchSetFlow {
        var flow = WatchSetFlow()
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        return flow
    }

    private func completedFlow(_ state: GymaState) throws -> WatchSetFlow {
        var flow = readyFlow(state)
        try flow.setPreparation(kg: 42.5, reps: 10)
        try flow.start(snapshot: snapshot(state))
        try flow.done(snapshot: snapshot(state))
        try flow.setActual(kg: 40, reps: 9)
        return flow
    }

    private func submit(_ flow: inout WatchSetFlow, state: GymaState) throws -> WatchCommand {
        let set = try flow.prepareSubmission(snapshot: snapshot(state))
        let command = WatchCommand(storeID: state.storeID, workoutID: "workout",
                                   basedOnRevision: flow.draft?.completionRevision, createdAt: now,
                                   action: .logSet(exerciseID: "bench_press", set: set))
        flow.markSubmitted(command)
        return command
    }

    func testSetMustStartThenCompleteThenConfirmBeforeCommandExists() throws {
        let state = state()
        var flow = readyFlow(state)
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertEqual(flow.draft?.kg, 40)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        try flow.setPreparation(kg: 42.5, reps: 10)
        try flow.start(snapshot: snapshot(state))
        XCTAssertEqual(flow.draft?.phase, .performing)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        try flow.done(snapshot: snapshot(state))
        XCTAssertEqual(flow.draft?.actualReps, 10)
        try flow.setActual(kg: 40, reps: 9)
        let set = try flow.prepareSubmission(snapshot: snapshot(state))
        XCTAssertEqual(set.kg, 40)
        XCTAssertEqual(set.reps, 9)
        XCTAssertEqual(set.isWarmup, false)
        XCTAssertEqual(flow.draft?.phase, .submitting)
    }

    func testDraftResumesWithActualEditsAcrossRelaunch() throws {
        let flow = try completedFlow(state())
        var restored = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
        restored.reconcile(snapshot: snapshot(state()), pending: nil, acknowledgement: nil)
        XCTAssertEqual(restored, flow)
        XCTAssertEqual(restored.draft?.actualReps, 9)
        XCTAssertEqual(restored.draft?.expectedReps, 10)
    }

    func testUnrelatedRevisionChangesDuringSetUseCurrentRevisionAtConfirmation() throws {
        var state = state()
        var flow = try completedFlow(state)
        state.revision += 7
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        _ = try flow.prepareSubmission(snapshot: snapshot(state))
        XCTAssertEqual(flow.draft?.completionRevision, 7)
    }

    func testPhoneAdvancingSameExerciseCannotDuplicateAnUnsentSet() throws {
        var state = state()
        var flow = try completedFlow(state)
        try state.addSet(.init(kg: 40, reps: 10, isWarmup: false), exerciseID: "bench_press", workoutID: "workout", now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.phase, .review)
        XCTAssertEqual(flow.draft?.workingSetCount, 0)
        XCTAssertEqual(flow.draft?.actualReps, 9)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        flow.useCurrentWorkout(snapshot(state))
        XCTAssertEqual(flow.draft?.workingSetCount, 1)
        XCTAssertEqual(flow.draft?.phase, .prepared)
    }

    func testReplacementPhoneStoreKeepsUnsentDraftForExplicitReview() throws {
        var state = state()
        var flow = try completedFlow(state)
        state.storeID = "new-store"
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.storeID, "phone-store")
        XCTAssertEqual(flow.draft?.actualReps, 9)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
    }

    func testDifferentWorkoutDoesNotInheritPerformedOrActualSetValues() throws {
        var state = state()
        var flow = try completedFlow(state)
        state.workouts[0].id = "replacement-workout"
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.workoutID, "workout")
        XCTAssertEqual(flow.draft?.actualReps, 9)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        flow.useCurrentWorkout(snapshot(state))
        XCTAssertEqual(flow.draft?.workoutID, "replacement-workout")
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertEqual(flow.draft?.expectedReps, 8)
    }

    func testRejectedCommandRetainsActualEditsAndCanRetryWithSameSetIdentity() throws {
        var state = state()
        var flow = try completedFlow(state)
        let command = try submit(&flow, state: state)
        state.revision += 1
        let receipt = GymaReducer.apply(command, to: &state, now: now)
        XCTAssertEqual(receipt.status, .rejected)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
        XCTAssertEqual(flow.draft?.phase, .review)
        XCTAssertEqual(flow.draft?.actualKg, 40)
        XCTAssertEqual(flow.draft?.actualReps, 9)
        let originalID = flow.draft?.setID
        let retry = try flow.prepareSubmission(snapshot: snapshot(state))
        XCTAssertEqual(retry.id, originalID)
        XCTAssertEqual(flow.draft?.completionRevision, state.revision)
    }

    func testCrashAfterOutboxWriteRecoversPendingCommandAndDoesNotResubmit() throws {
        var state = state()
        var flow = try completedFlow(state)
        let set = try flow.prepareSubmission(snapshot: snapshot(state))
        let command = WatchCommand(id: "queued", storeID: state.storeID, workoutID: "workout",
                                   basedOnRevision: state.revision, createdAt: now,
                                   action: .logSet(exerciseID: "bench_press", set: set))
        // No markSubmitted write happened before process exit.
        flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
        flow.reconcile(snapshot: snapshot(state), pending: command, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.commandID, "queued")
        XCTAssertEqual(flow.draft?.phase, .submitting)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        let receipt = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: command, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.phase, .submitting, "A snapshot arriving before the receipt does not free the draft.")
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
        XCTAssertEqual(flow.draft?.workingSetCount, 1)
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertEqual(flow.draft?.kg, 40)
        XCTAssertEqual(flow.draft?.expectedReps, 10, "Fewer actual reps do not lower the next expected rep target.")
    }

    func testCrashBeforeOutboxWriteReturnsToReviewWithoutLosingCompletedValues() throws {
        let state = state()
        var flow = try completedFlow(state)
        let prepared = try flow.prepareSubmission(snapshot: snapshot(state))
        flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.phase, .review)
        XCTAssertEqual(flow.draft?.actualReps, 9)
        let retry = try flow.prepareSubmission(snapshot: snapshot(state))
        XCTAssertEqual(retry.id, prepared.id)
    }

    func testDismissRestWaitsForAcceptedReceiptThenStartsPreparedNextSet() throws {
        var state = state()
        var flow = try completedFlow(state)
        let command = try submit(&flow, state: state)
        let logged = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: logged)
        try flow.setPreparation(kg: 37.5, reps: 8)
        XCTAssertThrowsError(try flow.start(snapshot: snapshot(state)))
        try flow.prepareRestResume(snapshot: snapshot(state))
        let timerID = try XCTUnwrap(state.restTimer?.id)
        let resume = WatchCommand(id: "resume", storeID: state.storeID, workoutID: "workout",
                                  basedOnRevision: state.revision, createdAt: now.addingTimeInterval(92),
                                  action: .skipRest(timerID: timerID))
        flow.markRestSubmitted(resume)
        flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
        let receipt = GymaReducer.apply(resume, to: &state, now: now.addingTimeInterval(100))
        flow.reconcile(snapshot: snapshot(state), pending: resume, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertEqual(flow.resumeRestTimer?.id, timerID)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
        XCTAssertEqual(flow.draft?.phase, .performing)
        XCTAssertEqual(flow.draft?.kg, 37.5)
        XCTAssertEqual(flow.draft?.expectedReps, 8)
        XCTAssertNil(flow.resumeRestTimer)
        XCTAssertEqual(state.activeWorkout?.restHistory?.last?.elapsedSeconds, 92)
    }

    func testRejectedRestExitNeverStartsNextSet() throws {
        var state = state()
        var flow = try completedFlow(state)
        let command = try submit(&flow, state: state)
        let logged = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: logged)
        try flow.prepareRestResume(snapshot: snapshot(state))
        let resume = WatchCommand(id: "resume", storeID: state.storeID, workoutID: "workout",
                                  basedOnRevision: state.revision - 1, createdAt: now,
                                  action: .skipRest(timerID: try XCTUnwrap(state.restTimer?.id)))
        flow.markRestSubmitted(resume)
        let receipt = GymaReducer.apply(resume, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertNotNil(state.restTimer)
        XCTAssertNil(flow.resumeCommandID)
    }

    func testWorkoutEndingWhileRestExitIsPendingDoesNotStartAnotherSet() throws {
        var state = state()
        var flow = try completedFlow(state)
        let command = try submit(&flow, state: state)
        let logged = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: logged)
        try flow.prepareRestResume(snapshot: snapshot(state))
        let resume = WatchCommand(id: "resume", storeID: state.storeID, workoutID: "workout",
                                  basedOnRevision: state.revision, createdAt: now,
                                  action: .skipRest(timerID: try XCTUnwrap(state.restTimer?.id)))
        flow.markRestSubmitted(resume)
        try state.finishWorkout("workout", at: now.addingTimeInterval(30))
        flow.reconcile(snapshot: snapshot(state), pending: resume, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.phase, .prepared)
        let receipt = GymaReducer.apply(resume, to: &state, now: now.addingTimeInterval(30))
        XCTAssertEqual(receipt.status, .rejected)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertNil(flow.resumeRestTimer)
        XCTAssertFalse(flow.draft?.matches(snapshot(state)) ?? true)
    }
}
