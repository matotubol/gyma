import XCTest
@testable import GymaCore

final class WatchWorkoutNavigationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func state() throws -> GymaState {
        var state = GymaState()
        try state.startWorkout(.init(id: "workout", start: now, exercises: [
            .init(exerciseID: "bench_press", target: .init(sets: 3, repsMin: 8, repsMax: 10, loadKg: 40)),
            .init(exerciseID: "squat", target: .init(sets: 2, repsMin: 6, repsMax: 8, loadKg: 60))
        ]))
        return state
    }
    private func snapshot(_ state: GymaState) -> CompanionSnapshot { .init(state: state, now: now) }
    private func flow(_ state: GymaState, phase: WatchSetPhase = .prepared) throws -> WatchSetFlow {
        var flow = WatchSetFlow()
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        if phase == .performing || phase == .review {
            try flow.start(snapshot: snapshot(state))
        }
        if phase == .review {
            try flow.done(snapshot: snapshot(state))
            try flow.setActual(kg: 37.5, reps: 5)
        }
        return flow
    }
    private func command(_ state: GymaState, action: WatchAction) -> WatchCommand {
        .init(storeID: state.storeID, workoutID: "workout", basedOnRevision: state.revision, createdAt: now, action: action)
    }

    func testCancelPerformingAndReviewedSetsCreatesNoLogOrSkipAndResetsPreparation() throws {
        let state = try state()
        for phase in [WatchSetPhase.performing, .review] {
            var flow = try flow(state, phase: phase)
            try flow.cancelSet(snapshot: snapshot(state))
            XCTAssertEqual(flow.draft?.phase, .prepared)
            XCTAssertEqual(flow.draft?.actualReps, 8)
            XCTAssertNil(flow.draft?.setID)
            XCTAssertNil(flow.draft?.commandID)
            XCTAssertEqual(state.activeWorkout?.totalSets, 0)
            XCTAssertEqual(state.activeWorkout?.exercises[0].skippedSetCount, 0)
        }
    }

    func testCancelCannotEraseASetAlreadySubmitted() throws {
        let state = try state()
        var flow = try flow(state, phase: .review)
        try flow.confirmReps()
        try flow.confirmWeight()
        try flow.confirmEffort(.challenging)
        _ = try flow.prepareSubmission(snapshot: snapshot(state))
        let saved = flow
        XCTAssertThrowsError(try flow.cancelSet(snapshot: snapshot(state)))
        XCTAssertEqual(flow, saved)
    }

    func testSkipWhilePerformingWaitsForReceiptAndSnapshotBeforeDiscardingDraft() throws {
        var state = try state()
        let oldSnapshot = snapshot(state)
        var flow = try flow(state, phase: .performing)
        let command = command(state, action: .skipSet(exerciseID: "bench_press"))
        flow.markWorkoutChangeSubmitted(command)
        flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
        let receipt = GymaReducer.apply(command, to: &state, now: now)
        XCTAssertEqual(receipt.status, .applied)

        flow.reconcile(snapshot: oldSnapshot, pending: nil, acknowledgement: receipt)
        XCTAssertEqual(flow.draft?.phase, .performing)
        XCTAssertEqual(flow.pendingWorkoutChange?.id, command.id)
        XCTAssertThrowsError(try flow.done(snapshot: oldSnapshot))
        XCTAssertThrowsError(try flow.cancelSet(snapshot: oldSnapshot))

        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
        XCTAssertNil(flow.pendingWorkoutChange)
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertEqual(flow.draft?.position?.skippedSetCount, 1)
        XCTAssertEqual(flow.draft?.workingSetCount, 0)
        XCTAssertTrue(flow.draft?.matches(snapshot(state)) == true)
        XCTAssertEqual(state.activeWorkout?.totalSets, 0)
        try flow.validate()
    }

    func testSelectionRecoversFromJournalAfterCrashBeforeLocalIntentWasSaved() throws {
        var state = try state()
        var flow = try flow(state)
        let command = command(state, action: .selectExercise(exerciseID: "squat"))
        flow = try JSONDecoder().decode(WatchSetFlow.self, from: JSONEncoder().encode(flow))
        flow.reconcile(snapshot: snapshot(state), pending: command, acknowledgement: nil)
        XCTAssertEqual(flow.pendingWorkoutChange?.id, command.id)
        let receipt = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
        XCTAssertEqual(flow.draft?.exerciseID, "squat")
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertEqual(flow.draft?.kg, 60)
        XCTAssertNil(flow.pendingWorkoutChange)
    }

    func testSnapshotBeforeDuplicateReceiptStillPreservesDraftUntilAcceptance() throws {
        var state = try state()
        var flow = try flow(state, phase: .review)
        let originalDraft = flow.draft
        let command = command(state, action: .skipExercise(exerciseID: "bench_press"))
        flow.markWorkoutChangeSubmitted(command)
        _ = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: command, acknowledgement: nil)
        XCTAssertEqual(flow.draft, originalDraft)
        let duplicate = GymaReducer.apply(command, to: &state, now: now)
        XCTAssertEqual(duplicate.status, .duplicate)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: duplicate)
        XCTAssertEqual(flow.draft?.exerciseID, "squat")
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertNil(flow.pendingWorkoutChange)
    }

    func testRejectedSkipPreservesCompletedReviewAndAllEnteredValues() throws {
        var state = try state()
        var flow = try flow(state, phase: .review)
        let originalDraft = flow.draft
        let command = command(state, action: .skipSet(exerciseID: "bench_press"))
        flow.markWorkoutChangeSubmitted(command)
        state.revision += 1
        let rejected = GymaReducer.apply(command, to: &state, now: now)
        XCTAssertEqual(rejected.status, .rejected)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: rejected)
        XCTAssertEqual(flow.draft, originalDraft)
        XCTAssertNil(flow.pendingWorkoutChange)
        XCTAssertEqual(state.activeWorkout?.exercises[0].skippedSetCount, 0)
    }

    func testPhoneSkipInvalidatesOldWatchPositionWithoutDiscardingReview() throws {
        var state = try state()
        var flow = try flow(state, phase: .review)
        let originalDraft = flow.draft
        try state.skipSet(exerciseID: "bench_press", workoutID: "workout", now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: nil)
        XCTAssertEqual(flow.draft, originalDraft)
        XCTAssertFalse(flow.draft?.matches(snapshot(state)) == true)
        XCTAssertThrowsError(try flow.prepareSubmission(snapshot: snapshot(state)))
        try flow.cancelSet(snapshot: snapshot(state))
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertEqual(flow.draft?.position?.skippedSetCount, 1)
    }

    func testAcceptedSelectionDoesNotAutoStartOrResurrectRestResume() throws {
        var state = try state()
        try state.addSet(.init(kg: 40, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "workout", now: now)
        var flow = try flow(state)
        try flow.prepareRestResume(snapshot: snapshot(state))
        let command = command(state, action: .selectExercise(exerciseID: "squat"))
        flow.markWorkoutChangeSubmitted(command)
        XCTAssertNil(flow.resumeRestTimer)
        let receipt = GymaReducer.apply(command, to: &state, now: now)
        flow.reconcile(snapshot: snapshot(state), pending: nil, acknowledgement: receipt)
        XCTAssertEqual(flow.draft?.phase, .prepared)
        XCTAssertEqual(flow.draft?.exerciseID, "squat")
        XCTAssertNil(state.restTimer)
    }

    func testAcceptedChangeForReplacedStoreCannotDiscardOldDraft() throws {
        let state = try state()
        var flow = try flow(state, phase: .review)
        let command = command(state, action: .skipSet(exerciseID: "bench_press"))
        flow.markWorkoutChangeSubmitted(command)
        let draft = flow.draft
        var replacement = state
        replacement.storeID = "new-phone-store"
        replacement.revision += 5
        let receipt = CommandAcknowledgement(commandID: command.id, status: .applied, revision: state.revision + 1)
        flow.reconcile(snapshot: snapshot(replacement), pending: nil, acknowledgement: receipt)
        XCTAssertEqual(flow.draft, draft)
        XCTAssertEqual(flow.pendingWorkoutChange, command)
    }

    func testNewNavigationCommandsSuppressPendingRestHaptics() throws {
        var state = try state()
        try state.addSet(.init(kg: 40, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "workout", now: now)
        for action in [WatchAction.selectExercise(exerciseID: "squat"), .skipSet(exerciseID: "bench_press"), .skipExercise(exerciseID: "bench_press")] {
            XCTAssertNil(RestAlertPolicy.hapticSchedule(snapshot: snapshot(state), pending: command(state, action: action), enabled: true,
                                                      isAppActive: true, workoutRunning: true, lastAlertKey: nil, now: now))
        }
    }
}
