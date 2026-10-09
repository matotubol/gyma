import XCTest
@testable import GymaCore

final class GymaCoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func activeState() throws -> GymaState {
        var state = GymaState()
        try state.startWorkout(Workout(id: "workout-1", start: now, exercises: [.init(exerciseID: "bench_press")]))
        return state
    }
    private func command(_ state: GymaState, id: String = UUID().uuidString, action: WatchAction) -> WatchCommand {
        WatchCommand(id: id, storeID: state.storeID, workoutID: "workout-1", basedOnRevision: state.revision, createdAt: now, action: action)
    }
    func testDuplicateDeliveryAfterPersistenceLogsExactlyOneSet() throws {
        var state = try activeState()
        let event = command(state, id: "event-1", action: .logSet(exerciseID: "bench_press", set: .init(id: "set-1", kg: 60, reps: 8, effort: .challenging, isWarmup: false)))
        XCTAssertEqual(GymaReducer.apply(event, to: &state, now: now).status, .applied)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileStore(url: directory.appendingPathComponent("state.json"))
        try store.save(state); var reloaded = try store.load()
        let revision = reloaded.revision
        XCTAssertEqual(GymaReducer.apply(event, to: &reloaded, now: now.addingTimeInterval(100)).status, .duplicate)
        XCTAssertEqual(reloaded.activeWorkout?.totalSets, 1)
        XCTAssertEqual(reloaded.revision, revision)
        XCTAssertEqual(reloaded.restTimer?.endsAt, state.restTimer?.endsAt)
    }
    func testRejectedCommandRemainsRejectedAfterStateChanges() throws {
        var state = try activeState()
        var event = command(state, id: "stale", action: .finishWorkout)
        event.basedOnRevision = 0
        let receipt = GymaReducer.apply(event, to: &state, now: now)
        XCTAssertEqual(receipt.status, .rejected)
        try state.addExercise("squat", to: "workout-1")
        XCTAssertEqual(GymaReducer.apply(event, to: &state, now: now), receipt)
        XCTAssertNotNil(state.activeWorkout)
    }
    func testCommandIdentityCollisionCannotChangePriorMutation() throws {
        var state = try activeState()
        var event = command(state, id: "event", action: .logSet(exerciseID: "bench_press", set: .init(kg: 40, reps: 5)))
        XCTAssertEqual(GymaReducer.apply(event, to: &state, now: now).status, .applied)
        event.action = .finishWorkout
        XCTAssertEqual(GymaReducer.apply(event, to: &state, now: now).status, .rejected)
        XCTAssertEqual(state.activeWorkout?.totalSets, 1)
    }
    func testOldWorkoutAndStoreEpochAreRejected() throws {
        var state = try activeState()
        var wrongStore = command(state, action: .finishWorkout); wrongStore.storeID = "previous-install"
        XCTAssertEqual(GymaReducer.apply(wrongStore, to: &state, now: now).status, .rejected)
        var oldWorkout = command(state, action: .finishWorkout); oldWorkout.workoutID = "workout-from-yesterday"
        XCTAssertEqual(GymaReducer.apply(oldWorkout, to: &state, now: now).status, .rejected)
        XCTAssertNotNil(state.activeWorkout)
    }
    func testRestDeadlineReplacementStaleSkipAndFinish() throws {
        var state = try activeState()
        try state.addSet(.init(id: "first", kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "workout-1", now: now)
        let first = try XCTUnwrap(state.restTimer)
        XCTAssertEqual(first.remaining(at: now.addingTimeInterval(30)), 90)
        try state.addSet(.init(id: "second", kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "workout-1", now: now.addingTimeInterval(60))
        let second = try XCTUnwrap(state.restTimer)
        XCTAssertNotEqual(first.id, second.id)
        let staleSkip = command(state, action: .skipRest(timerID: first.id))
        XCTAssertEqual(GymaReducer.apply(staleSkip, to: &state, now: now).status, .rejected)
        XCTAssertEqual(state.restTimer, second)
        try state.extendRest(timerID: second.id, seconds: 30, now: second.endsAt.addingTimeInterval(10))
        XCTAssertEqual(state.restTimer?.endsAt, second.endsAt.addingTimeInterval(40))
        try state.finishWorkout("workout-1", at: now.addingTimeInterval(300))
        XCTAssertNil(state.restTimer)
    }
    func testDelayedSetUsesOriginalRestDeadline() throws {
        var state = try activeState()
        let event = command(state, action: .logSet(exerciseID: "bench_press", set: .init(kg: 40, reps: 8, isWarmup: false)))
        let receipt = GymaReducer.apply(event, to: &state, now: now.addingTimeInterval(300))
        XCTAssertEqual(receipt.status, .applied)
        XCTAssertEqual(state.restTimer?.endsAt, now.addingTimeInterval(120))
        XCTAssertEqual(state.restTimer?.remaining(at: now.addingTimeInterval(300)), 0)
    }
    func testTimerRemainingIsSafeFor32BitWatchIntegerConversion() {
        let distant = Date(timeIntervalSince1970: 4_102_444_800)
        let timer = RestTimer(workoutID: "future", exerciseID: "bench_press", startedAt: distant.addingTimeInterval(-120), endsAt: distant, sourceSetID: "set")
        XCTAssertEqual(timer.remaining(at: now), 86400)
        XCTAssertNotNil(Int32(exactly: ceil(timer.remaining(at: now))))
        XCTAssertEqual(timer.remaining(at: distant.addingTimeInterval(1)), 0)
    }
    func testExpiredAndFutureCommandsCannotMutateWorkout() throws {
        for offset in [-86401.0, 301.0] {
            var state = try activeState()
            var event = command(state, action: .finishWorkout); event.createdAt = now.addingTimeInterval(offset)
            XCTAssertEqual(GymaReducer.apply(event, to: &state, now: now).status, .rejected)
            XCTAssertNotNil(state.activeWorkout)
        }
    }
    func testUnknownWarmupNeverStartsTimerAndFinalTargetClearsIt() throws {
        var state = try activeState()
        try state.updateTarget(.init(sets: 2, repsMin: 8, repsMax: 10), exerciseID: "bench_press", workoutID: "workout-1")
        try state.addSet(.init(kg: 40, reps: 8), exerciseID: "bench_press", workoutID: "workout-1", now: now)
        XCTAssertNil(state.restTimer)
        try state.addSet(.init(kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "workout-1", now: now)
        XCTAssertNotNil(state.restTimer)
        try state.addSet(.init(kg: 60, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: "workout-1", now: now)
        XCTAssertNil(state.restTimer)
    }
    func testNativeBackupRoundTripsCompleteState() throws {
        var state = try activeState()
        try state.addCustomExercise(.init(id: "custom-1", name: "My row", muscle: .back, custom: true))
        try state.addSet(.init(kg: 60, reps: 8, effort: .challenging, isWarmup: false), exerciseID: "bench_press", workoutID: "workout-1", now: now)
        state.deletedWorkouts = [Workout(id: "deleted", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-300))]
        let encoded = try NativeBackup.encode(state)
        let decoded = try NativeBackup.decode(encoded)
        XCTAssertEqual(decoded, state)
        var invalid = state
        invalid.schemaVersion = 99
        XCTAssertThrowsError(try NativeBackup.decode(JSONEncoder().encode(invalid)))
        invalid = state
        invalid.revision = Int.max
        XCTAssertThrowsError(try NativeBackup.decode(JSONEncoder().encode(invalid)))
        invalid = state; invalid.workouts[0].start = Date(timeIntervalSince1970: 1e30)
        XCTAssertThrowsError(try NativeBackup.decode(JSONEncoder().encode(invalid)))
    }
    func testInvalidBackupDoesNotOverwriteExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("data.json")
        let bytes = Data("{\"version\":99,\"workouts\":[]}".utf8)
        try bytes.write(to: url)
        XCTAssertThrowsError(try JSONFileStore(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertThrowsError(try NativeBackup.decode(Data("{\"workouts\":[{\"id\":\"bad\"}]}".utf8)))
    }
    func testSnapshotExcludesBackupAndBoundsHistory() throws {
        var state = try activeState()
        state.deletedWorkouts = [Workout(id: "history never sent to watch", start: now, end: now)]
        for index in 0..<30 { try state.addSet(.init(id: "set-\(index)", kg: 20, reps: 5), exerciseID: "bench_press", workoutID: "workout-1", now: now) }
        let snapshot = CompanionSnapshot(state: state, now: now)
        XCTAssertEqual(snapshot.activeWorkout?.totalSets, 20)
        XCTAssertTrue(snapshot.isTruncated)
        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("history never sent"))
        XCTAssertEqual(snapshot.catalog.map(\.id), ["bench_press"])
    }
    func testSnapshotByteLimitWithMultibyteIdentifiers() throws {
        var state = try activeState()
        state.workouts[0].exercises = state.catalog.prefix(12).enumerated().map { ei, definition in
            WorkoutExercise(exerciseID: definition.id, sets: (0..<20).map { si in
                WorkSet(id: String(repeating: "🏋️", count: 180) + "-\(ei)-\(si)", kg: 20, reps: 5)
            })
        }
        try state.validate()
        let snapshot = CompanionSnapshot(state: state, now: now)
        XCTAssertTrue(snapshot.isTruncated)
        XCTAssertLessThanOrEqual(try JSONEncoder().encode(snapshot).count, 48 * 1024)
        XCTAssertEqual(state.activeWorkout?.totalSets, 240)
    }
    func testInvalidSaveKeepsLastGoodFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileStore(url: directory.appendingPathComponent("data.json"))
        let good = try activeState(); try store.save(good)
        var invalid = good; invalid.workouts[0].exercises.append(.init(exerciseID: "bench_press"))
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try store.load(), good)
    }
    func testNativeBackupRejectsOrphanExerciseReferencesIncludingDeletedWorkouts() throws {
        var state = try activeState()
        state.workouts[0].exercises = [.init(exerciseID: "missing-custom-definition")]
        XCTAssertThrowsError(try NativeBackup.decode(JSONEncoder().encode(state)))
        state = try activeState()
        state.deletedWorkouts = [Workout(id: "deleted", start: now, end: now, exercises: [.init(exerciseID: "missing-custom-definition")])]
        XCTAssertThrowsError(try NativeBackup.decode(JSONEncoder().encode(state)))
        try state.addCustomExercise(.init(id: "missing-custom-definition", name: "Custom movement", muscle: .legs, custom: true))
        XCTAssertNoThrow(try state.validate())
    }
}
