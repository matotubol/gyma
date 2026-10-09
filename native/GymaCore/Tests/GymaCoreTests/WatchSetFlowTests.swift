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
        try flow.confirmReps()
        return flow
    }

    private func confirmWorkingReview(_ flow: inout WatchSetFlow) throws {
        if flow.draft?.currentReviewStep == .weight { try flow.confirmWeight() }
        if flow.draft?.currentReviewStep == .effort, flow.draft?.effortWasConfirmed != true {
            try flow.confirmEffort(.challenging)
        }
    }

    private func submit(_ flow: inout WatchSetFlow, state: GymaState) throws -> WatchCommand {
        try confirmWorkingReview(&flow)
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
        XCTAssertEqual(flow.draft?.currentReviewStep, .reps)
        XCTAssertEqual(flow.draft?.actualReps, 10)
        try flow.setActual(kg: 40, reps: 9)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        try flow.confirmReps()
        XCTAssertEqual(flow.draft?.currentReviewStep, .weight)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        try flow.confirmWeight()
        XCTAssertEqual(flow.draft?.currentReviewStep, .effort)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        try flow.confirmEffort(.challenging)
        let set = try flow.prepareSubmission(snapshot: snapshot(state))
        XCTAssertEqual(set.kg, 40)
        XCTAssertEqual(set.reps, 9)
        XCTAssertEqual(set.isWarmup, false)
        XCTAssertEqual(set.effort, .challenging)
        XCTAssertEqual(flow.draft?.phase, .submitting)
    }

    func testDraftResumesWithActualEditsAcrossRelaunch() throws {
        let flow = try completedFlow(state())
        var restored = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
        restored.reconcile(snapshot: snapshot(state()), pending: nil, acknowledgement: nil)
        XCTAssertEqual(restored, flow)
        XCTAssertEqual(restored.draft?.actualReps, 9)
        XCTAssertEqual(restored.draft?.expectedReps, 10)
        XCTAssertEqual(restored.draft?.currentReviewStep, .weight)
    }

    func testUnrelatedRevisionChangesDuringSetUseCurrentRevisionAtConfirmation() throws {
        var state = state()
        var flow = try completedFlow(state)
        state.revision += 7
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        try confirmWorkingReview(&flow)
        _ = try flow.prepareSubmission(snapshot: snapshot(state))
        XCTAssertEqual(flow.draft?.completionRevision, 7)
    }

    func testPreparedDraftAdoptsChangedCoachLoadAndRepsWithoutDiscardingManualEditsOnUnrelatedSync() throws {
        var state = state()
        var flow = readyFlow(state)
        try flow.setPreparation(kg: 45, reps: 10)
        let target = ExerciseTarget(sets: 3, repsMin: 6, repsMax: 8, loadKg: 35, restSeconds: 120)
        try state.updateTarget(target, exerciseID: "bench_press", workoutID: "workout")
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.kg, 35)
        XCTAssertEqual(flow.draft?.expectedReps, 6)
        XCTAssertEqual(flow.draft?.actualKg, 35)
        XCTAssertEqual(flow.draft?.actualReps, 6)
        XCTAssertEqual(flow.draft?.sourceTarget, target)
        try flow.setPreparation(kg: 37.5, reps: 7)
        state.revision += 1
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.kg, 37.5)
        XCTAssertEqual(flow.draft?.expectedReps, 7)
    }

    func testRestOnlyCoachEditDoesNotResetPreparedLoadOrReps() throws {
        var state = state()
        var flow = readyFlow(state)
        try flow.setPreparation(kg: 42.5, reps: 10)
        var target = try XCTUnwrap(state.activeWorkout?.exercises.first?.target)
        target.restSeconds = 150; target.reason = "Take a longer rest."
        try state.updateTarget(target, exerciseID: "bench_press", workoutID: "workout")
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.kg, 42.5)
        XCTAssertEqual(flow.draft?.expectedReps, 10)
    }

    func testChangedCoachTargetWaitsUntilAfterPerformingSetAndPreservesActuals() throws {
        var state = state()
        var flow = readyFlow(state)
        try flow.start(snapshot: snapshot(state))
        let target = ExerciseTarget(sets: 3, repsMin: 6, repsMax: 8, loadKg: 35, restSeconds: 120)
        try state.updateTarget(target, exerciseID: "bench_press", workoutID: "workout")
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.phase, .performing)
        XCTAssertEqual(flow.draft?.kg, 40)
        XCTAssertEqual(flow.draft?.expectedReps, 8)
        try flow.done(snapshot: snapshot(state))
        try flow.setActual(kg: 42.5, reps: 7)
        try flow.confirmReps()
        let command = try submit(&flow, state: state)
        let receipt = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
        XCTAssertEqual(state.activeWorkout?.exercises.first?.sets.last?.kg, 42.5)
        XCTAssertEqual(state.activeWorkout?.exercises.first?.sets.last?.reps, 7)
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertEqual(flow.draft?.kg, 35)
        XCTAssertEqual(flow.draft?.expectedReps, 6)
        XCTAssertEqual(flow.draft?.sourceTarget, target)
    }

    func testChangedCoachTargetDoesNotReplaceReviewValues() throws {
        var state = state()
        var flow = try completedFlow(state)
        try state.updateTarget(.init(sets: 3, repsMin: 6, repsMax: 8, loadKg: 35), exerciseID: "bench_press", workoutID: "workout")
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.phase, .review)
        XCTAssertEqual(flow.draft?.actualKg, 40)
        XCTAssertEqual(flow.draft?.actualReps, 9)
        XCTAssertEqual(flow.draft?.currentReviewStep, .weight)
        try confirmWorkingReview(&flow)
        let submitted = try flow.prepareSubmission(snapshot: snapshot(state))
        XCTAssertEqual(submitted.kg, 40)
        XCTAssertEqual(submitted.reps, 9)
    }

    func testLegacyPreparedDraftSeedsTargetWithoutReplacingSavedValues() throws {
        var state = state()
        var flow = readyFlow(state)
        try flow.setPreparation(kg: 37.5, reps: 10)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(flow)) as? [String: Any])
        var draft = try XCTUnwrap(object["draft"] as? [String: Any])
        draft.removeValue(forKey: "sourceTarget"); object["draft"] = draft
        flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONSerialization.data(withJSONObject: object))
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.kg, 37.5)
        XCTAssertEqual(flow.draft?.expectedReps, 10)
        try state.updateTarget(.init(sets: 3, repsMin: 6, repsMax: 8, loadKg: 35), exerciseID: "bench_press", workoutID: "workout")
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.kg, 35)
        XCTAssertEqual(flow.draft?.expectedReps, 6)
    }

    func testPhoneAdvancingSameExerciseCannotDuplicateAnUnsentSet() throws {
        var state = state()
        var flow = try completedFlow(state)
        try confirmWorkingReview(&flow)
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
        try confirmWorkingReview(&flow)
        state.storeID = "new-store"
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.storeID, "phone-store")
        XCTAssertEqual(flow.draft?.actualReps, 9)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
    }

    func testDifferentWorkoutDoesNotInheritPerformedOrActualSetValues() throws {
        var state = state()
        var flow = try completedFlow(state)
        try confirmWorkingReview(&flow)
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
        XCTAssertEqual(flow.draft?.currentReviewStep, .effort)
        let originalID = flow.draft?.setID
        try confirmWorkingReview(&flow)
        let retry = try flow.prepareSubmission(snapshot: snapshot(state))
        XCTAssertEqual(retry.id, originalID)
        XCTAssertEqual(flow.draft?.completionRevision, state.revision)
    }

    func testCrashAfterOutboxWriteRecoversPendingCommandAndDoesNotResubmit() throws {
        var state = state()
        var flow = try completedFlow(state)
        try confirmWorkingReview(&flow)
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
        XCTAssertEqual(flow.draft?.currentReviewStep, .reps)
        XCTAssertEqual(flow.draft?.kg, 40)
        XCTAssertEqual(flow.draft?.expectedReps, 10, "Fewer actual reps do not lower the next expected rep target.")
    }

    func testCrashBeforeOutboxWriteReturnsToReviewWithoutLosingCompletedValues() throws {
        let state = state()
        var flow = try completedFlow(state)
        try confirmWorkingReview(&flow)
        let prepared = try flow.prepareSubmission(snapshot: snapshot(state))
        flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.phase, .review)
        XCTAssertEqual(flow.draft?.actualReps, 9)
        XCTAssertEqual(flow.draft?.currentReviewStep, .effort)
        try confirmWorkingReview(&flow)
        let retry = try flow.prepareSubmission(snapshot: snapshot(state))
        XCTAssertEqual(retry.id, prepared.id)
    }

    func testBackToRepsPreservesEditedWeightAndRequiresReconfirmation() throws {
        let state = state()
        var flow = try completedFlow(state)
        try flow.setActual(kg: 37.5, reps: 9)
        XCTAssertEqual(flow.draft?.currentReviewStep, .weight)
        try flow.backToReps()
        XCTAssertEqual(flow.draft?.actualKg, 37.5)
        XCTAssertEqual(flow.draft?.actualReps, 9)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        try flow.setActual(kg: 37.5, reps: 8)
        try flow.confirmReps()
        try confirmWorkingReview(&flow)
        let set = try flow.prepareSubmission(snapshot: snapshot(state))
        XCTAssertEqual(set.kg, 37.5)
        XCTAssertEqual(set.reps, 8)
    }

    func testChangingConfirmedRepsReturnsToRepsReview() throws {
        let state = state()
        var flow = try completedFlow(state)
        try flow.setActual(kg: 40, reps: 8)
        XCTAssertEqual(flow.draft?.currentReviewStep, .reps)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        try flow.confirmReps()
        try confirmWorkingReview(&flow)
        XCTAssertEqual(try flow.prepareSubmission(snapshot: snapshot(state)).reps, 8)
    }

    func testRepsReviewSurvivesRelaunchBeforeConfirmation() throws {
        let state = state()
        var flow = readyFlow(state)
        try flow.start(snapshot: snapshot(state))
        try flow.done(snapshot: snapshot(state))
        try flow.setActual(kg: 42.5, reps: 7)
        var restored = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
        restored.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(restored.draft?.currentReviewStep, .reps)
        XCTAssertEqual(restored.draft?.actualReps, 7)
        XCTAssertEqual(restored.draft?.actualKg, 42.5)
        XCTAssertThrowsError(try restored.prepareSubmission(snapshot: snapshot(state)))
        try restored.confirmReps()
        try confirmWorkingReview(&restored)
        XCTAssertEqual(try restored.prepareSubmission(snapshot: snapshot(state)).kg, 42.5)
    }

    func testLegacyCombinedReviewDefaultsToRepsAndKeepsActualValues() throws {
        let state = state()
        let flow = try completedFlow(state)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(flow)) as? [String: Any])
        var draft = try XCTUnwrap(object["draft"] as? [String: Any])
        draft.removeValue(forKey: "reviewStep")
        object["draft"] = draft
        var restored = try JSONDecoder().decode(WatchSetFlow.self, from: JSONSerialization.data(withJSONObject: object))
        try restored.validate()
        restored.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(restored.draft?.phase, .review)
        XCTAssertEqual(restored.draft?.currentReviewStep, .reps)
        XCTAssertEqual(restored.draft?.actualKg, 40)
        XCTAssertEqual(restored.draft?.actualReps, 9)
        XCTAssertThrowsError(try restored.prepareSubmission(snapshot: snapshot(state)))
        try restored.confirmReps()
        try confirmWorkingReview(&restored)
        XCTAssertEqual(try restored.prepareSubmission(snapshot: snapshot(state)).reps, 9)
    }

    func testFailedSubmissionReturnsToEffortWithSameCompletedSetIdentity() throws {
        let state = state()
        var flow = try completedFlow(state)
        try confirmWorkingReview(&flow)
        let first = try flow.prepareSubmission(snapshot: snapshot(state))
        flow.submissionFailed()
        XCTAssertEqual(flow.draft?.phase, .review)
        XCTAssertEqual(flow.draft?.currentReviewStep, .effort)
        XCTAssertEqual(flow.draft?.actualReps, first.reps)
        XCTAssertEqual(flow.draft?.actualKg, first.kg)
        try confirmWorkingReview(&flow)
        XCTAssertEqual(try flow.prepareSubmission(snapshot: snapshot(state)).id, first.id)
    }

    func testLegacyPendingCommandRecoversEffortReviewAfterRejection() throws {
        var state = state()
        var flow = try completedFlow(state)
        let command = try submit(&flow, state: state)
        let originalSetID = flow.draft?.setID
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(flow)) as? [String: Any])
        var draft = try XCTUnwrap(object["draft"] as? [String: Any])
        draft.removeValue(forKey: "reviewStep")
        object["draft"] = draft
        flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONSerialization.data(withJSONObject: object))
        flow.reconcile(snapshot: snapshot(state), pending: command, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.phase, .submitting)
        XCTAssertEqual(flow.draft?.currentReviewStep, .effort)
        state.revision += 1
        let rejected = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: rejected)
        XCTAssertEqual(flow.draft?.phase, .review)
        XCTAssertEqual(flow.draft?.currentReviewStep, .effort)
        XCTAssertEqual(flow.draft?.actualReps, 9)
        XCTAssertEqual(flow.draft?.actualKg, 40)
        try confirmWorkingReview(&flow)
        let retried = try flow.prepareSubmission(snapshot: snapshot(state))
        XCTAssertEqual(retried.id, originalSetID)
    }

    func testReviewTransitionsRejectWrongSetPhases() throws {
        let state = state()
        var flow = readyFlow(state)
        XCTAssertThrowsError(try flow.confirmReps())
        XCTAssertThrowsError(try flow.backToReps())
        try flow.start(snapshot: snapshot(state))
        XCTAssertThrowsError(try flow.confirmReps())
        try flow.done(snapshot: snapshot(state))
        XCTAssertThrowsError(try flow.backToReps())
        try flow.confirmReps()
        XCTAssertThrowsError(try flow.confirmReps())
        try confirmWorkingReview(&flow)
        _ = try flow.prepareSubmission(snapshot: snapshot(state))
        XCTAssertThrowsError(try flow.confirmReps())
        XCTAssertThrowsError(try flow.backToReps())
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

    func testEachEffortAndExplicitUnknownSurviveRelaunchAndSubmission() throws {
        let choices: [SetEffort?] = SetEffort.allCases.map { Optional($0) } + [nil]
        for effort in choices {
            var state = state()
            var flow = try completedFlow(state)
            try flow.confirmWeight()
            flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
            XCTAssertEqual(flow.draft?.currentReviewStep, .effort)
            XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
            try flow.confirmEffort(effort)
            flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
            XCTAssertEqual(flow.draft?.effortWasConfirmed, true)
            let command = try submit(&flow, state: state)
            let receipt = GymaReducer.apply(command, to: &state, now: now)
            XCTAssertEqual(receipt.status, .applied)
            XCTAssertEqual(state.activeWorkout?.exercises.first?.sets.last?.effort, effort)
            flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
            XCTAssertNil(flow.draft?.effort, "The next set never inherits the previous effort.")
            XCTAssertNil(flow.draft?.effortWasConfirmed)
            XCTAssertEqual(flow.draft?.phase, .prepared)
        }
    }

    func testBackFromEffortRetainsValuesAndRequiresFreshConfirmation() throws {
        let state = state()
        var flow = try completedFlow(state)
        try flow.confirmWeight()
        try flow.confirmEffort(.limit)
        try flow.backToWeight()
        XCTAssertEqual(flow.draft?.actualKg, 40)
        XCTAssertEqual(flow.draft?.actualReps, 9)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        try flow.setActual(kg: 37.5, reps: 9)
        try flow.confirmWeight()
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        try flow.confirmEffort(nil)
        let set = try flow.prepareSubmission(snapshot: snapshot(state))
        XCTAssertEqual(set.kg, 37.5)
        XCTAssertNil(set.effort)
    }

    func testWarmupChoiceAndReviewPersistWithoutCompletingWorkingTarget() throws {
        var state = state()
        var flow = readyFlow(state)
        try flow.setWarmup(true)
        try flow.setPreparation(kg: 20, reps: 12)
        flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
        XCTAssertEqual(flow.draft?.isWarmupSet, true)
        try flow.start(snapshot: snapshot(state))
        XCTAssertThrowsError(try flow.setWarmup(false))
        flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
        try flow.done(snapshot: snapshot(state))
        try flow.confirmReps()
        try flow.confirmWeight()
        XCTAssertEqual(flow.draft?.currentReviewStep, .weight)
        XCTAssertThrowsError(try flow.confirmEffort(.easy))
        let command = try submit(&flow, state: state)
        let receipt = GymaReducer.apply(command, to: &state, now: now)
        XCTAssertEqual(receipt.status, .applied)
        let entry = try XCTUnwrap(state.activeWorkout?.exercises.first)
        XCTAssertEqual(entry.sets.count, 1)
        XCTAssertEqual(entry.sets.last?.isWarmup, true)
        XCTAssertNil(entry.sets.last?.effort)
        XCTAssertEqual(entry.workingSetCount, 0)
        XCTAssertFalse(entry.isTargetComplete)
        XCTAssertNil(state.restTimer)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertEqual(flow.draft?.workingSetCount, 0)
        XCTAssertEqual(flow.draft?.isWarmupSet, false)
        XCTAssertEqual(flow.draft?.kg, 40, "A warm-up load must not become the working load.")
        XCTAssertEqual(flow.draft?.expectedReps, 8)
        XCTAssertEqual(flow.draft?.matches(snapshot(state)), true)
        try flow.start(snapshot: snapshot(state))
    }

    func testWarmupReceiptBeforeSnapshotCannotReleaseDraftOrDuplicateSet() throws {
        var state = state()
        var flow = readyFlow(state)
        try flow.setWarmup(true)
        try flow.start(snapshot: snapshot(state))
        try flow.done(snapshot: snapshot(state))
        try flow.confirmReps()
        let before = snapshot(state)
        let command = try submit(&flow, state: state)
        let receipt = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: before, pending: nil, acknowledgement: receipt)
        XCTAssertEqual(flow.draft?.phase, .submitting)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: before))
        flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertEqual(flow.draft?.workingSetCount, 0)
        XCTAssertEqual(flow.draft?.matches(snapshot(state)), true)
        let duplicate = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: duplicate)
        XCTAssertEqual(state.activeWorkout?.exercises.first?.sets.count, 1)
    }

    func testCoachTargetChangeKeepsWarmupValuesAndUpdatesFollowingWorkingSet() throws {
        var state = state()
        var flow = readyFlow(state)
        try flow.setWarmup(true)
        try flow.setPreparation(kg: 20, reps: 12)
        try state.updateTarget(.init(sets: 2, repsMin: 6, repsMax: 8, loadKg: 35), exerciseID: "bench_press", workoutID: "workout")
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.kg, 20)
        XCTAssertEqual(flow.draft?.expectedReps, 12)
        try flow.start(snapshot: snapshot(state))
        try flow.done(snapshot: snapshot(state))
        try flow.confirmReps()
        let command = try submit(&flow, state: state)
        let receipt = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
        XCTAssertEqual(flow.draft?.isWarmupSet, false)
        XCTAssertEqual(flow.draft?.kg, 35)
        XCTAssertEqual(flow.draft?.expectedReps, 6)
    }

    func testPhoneWarmupAdvancingSameWorkingCountInvalidatesUnsentDraft() throws {
        var state = state()
        var flow = try completedFlow(state)
        try confirmWorkingReview(&flow)
        try state.addSet(.init(kg: 20, reps: 10, isWarmup: true), exerciseID: "bench_press", workoutID: "workout", now: now)
        XCTAssertEqual(state.activeWorkout?.exercises.first?.workingSetCount, 0)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.phase, .review)
        XCTAssertEqual(flow.draft?.actualReps, 9)
        XCTAssertEqual(flow.draft?.matches(snapshot(state)), false)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        flow.useCurrentWorkout(snapshot(state))
        XCTAssertEqual(flow.draft?.matches(snapshot(state)), true)
    }

    func testWarmupPendingCommandRestoresMissingDraftAndRejectedRetry() throws {
        var state = state()
        let set = WorkSet(id: "warmup", kg: 22.5, reps: 12, isWarmup: true)
        let command = WatchCommand(id: "queued-warmup", storeID: state.storeID, workoutID: "workout",
                                   basedOnRevision: state.revision, createdAt: now,
                                   action: .logSet(exerciseID: "bench_press", set: set))
        var flow = WatchSetFlow()
        flow.reconcile(snapshot: snapshot(state), pending: command, acknowledgement: nil)
        XCTAssertEqual(flow.draft?.phase, .submitting)
        XCTAssertEqual(flow.draft?.isWarmupSet, true)
        XCTAssertEqual(flow.draft?.actualKg, 22.5)
        state.revision += 1
        let rejected = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: rejected)
        XCTAssertEqual(flow.draft?.currentReviewStep, .weight)
        XCTAssertEqual(try flow.prepareSubmission(snapshot: snapshot(state)), set)
    }

    func testLegacyDraftWithoutNewFieldsNeedsEffortAndSeedsPosition() throws {
        let state = state()
        let original = readyFlow(state)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var draft = try XCTUnwrap(object["draft"] as? [String: Any])
        for key in ["position", "isWarmup", "effort", "effortWasConfirmed"] { draft.removeValue(forKey: key) }
        object["draft"] = draft
        var flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONSerialization.data(withJSONObject: object))
        try flow.validate()
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertNotNil(flow.draft?.position)
        XCTAssertEqual(flow.draft?.isWarmupSet, false)
        try flow.start(snapshot: snapshot(state))
        try flow.done(snapshot: snapshot(state))
        try flow.confirmReps()
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        try flow.confirmWeight()
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        try flow.confirmEffort(nil)
        XCTAssertNil(try flow.prepareSubmission(snapshot: snapshot(state)).effort)
    }

    func testFinalWorkingSetWithEffortAdvancesExerciseWithoutRest() throws {
        var state = state()
        state.workouts[0].exercises[0].target?.sets = 1
        var flow = try completedFlow(state)
        let command = try submit(&flow, state: state)
        let receipt = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
        XCTAssertTrue(state.activeWorkout?.exercises.first?.isTargetComplete == true)
        XCTAssertNil(state.restTimer)
        XCTAssertEqual(flow.draft?.exerciseID, "squat")
        XCTAssertEqual(flow.draft?.kg, 60)
        XCTAssertNil(flow.draft?.effort)
        XCTAssertEqual(flow.draft?.isWarmupSet, false)
    }
}
