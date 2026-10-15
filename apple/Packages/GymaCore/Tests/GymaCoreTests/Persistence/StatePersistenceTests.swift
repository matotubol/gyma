import XCTest
@testable import GymaCore

final class StatePersistenceTests: XCTestCase {
    private let now = WorkoutTestFixture.now

    func testNativeBackupRoundTripsCompleteState() throws {
        var state = try WorkoutTestFixture.activeState()
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

    func testInvalidSaveKeepsLastGoodFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileStore(url: directory.appendingPathComponent("data.json"))
        let good = try WorkoutTestFixture.activeState(); try store.save(good)
        var invalid = good; invalid.workouts[0].exercises.append(.init(exerciseID: "bench_press"))
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try store.load(), good)
    }

    func testNativeBackupRejectsOrphanExerciseReferencesIncludingDeletedWorkouts() throws {
        var state = try WorkoutTestFixture.activeState()
        state.workouts[0].exercises = [.init(exerciseID: "missing-custom-definition")]
        XCTAssertThrowsError(try NativeBackup.decode(JSONEncoder().encode(state)))
        state = try WorkoutTestFixture.activeState()
        state.deletedWorkouts = [Workout(id: "deleted", start: now, end: now, exercises: [.init(exerciseID: "missing-custom-definition")])]
        XCTAssertThrowsError(try NativeBackup.decode(JSONEncoder().encode(state)))
        try state.addCustomExercise(.init(id: "missing-custom-definition", name: "Custom movement", muscle: .legs, custom: true))
        XCTAssertNoThrow(try state.validate())
    }
}
