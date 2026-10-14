import XCTest
@testable import GymaCore

final class ExerciseProgressComparisonTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var bench: ExerciseDefinition { ExerciseCatalog.builtIn.first { $0.id == "bench_press" }! }

    private func workout(_ id: String, daysAgo: Double, exerciseID: String = "bench_press", sets: [WorkSet]) -> Workout {
        let completed = now.addingTimeInterval(-daysAgo * 86400)
        return .init(id: id, start: completed.addingTimeInterval(-1800), end: completed,
                     exercises: [.init(exerciseID: exerciseID, sets: sets)])
    }

    private func working(_ kg: Double, reps: Int = 8, effort: SetEffort? = .challenging) -> WorkSet {
        .init(kg: kg, reps: reps, effort: effort, isWarmup: false)
    }

    func testOnlyCompletedWorkingExposuresOfTheSameExerciseFormTheComparison() throws {
        var active = workout("active", daysAgo: 0, sets: [working(120)])
        active.end = nil
        let excluded = [
            active,
            workout("future", daysAgo: -1, sets: [working(120)]),
            workout("other-exercise", daysAgo: 100, exerciseID: "squat", sets: [working(120)]),
            workout("warmup-only", daysAgo: 100, sets: [.init(kg: 100, reps: 8, effort: .limit, isWarmup: true)]),
            workout("unclassified-only", daysAgo: 100, sets: [.init(kg: 100, reps: 8, effort: .limit)])
        ]
        XCTAssertNil(ExerciseProgressComparison.make(exercise: bench, workouts: excluded, now: now))

        let first = workout("first", daysAgo: 60, sets: [working(60), .init(kg: 100, reps: 8, isWarmup: true)])
        let latest = workout("latest", daysAgo: 1, sets: [working(65, reps: 6), .init(kg: 110, reps: 8)])
        let comparison = try XCTUnwrap(ExerciseProgressComparison.make(exercise: bench, workouts: [latest] + excluded + [first], now: now))
        XCTAssertEqual(comparison.completedExposureCount, 2)
        XCTAssertTrue(comparison.hasMultipleExposures)
        XCTAssertEqual(comparison.first.workoutID, "first")
        XCTAssertEqual(comparison.latest.workoutID, "latest")
        XCTAssertEqual(comparison.topWorkingLoadChangeKg, 5)
        XCTAssertEqual(comparison.first.totalWorkingReps, 8)
        XCTAssertEqual(comparison.latest.totalWorkingReps, 6)
        XCTAssertEqual(comparison.first.workingSetCount, 1)
        XCTAssertEqual(comparison.latest.workingSetCount, 1)
        XCTAssertEqual(comparison.latest.workingVolumeKg, 390)
    }

    func testSingleSessionKeepsItsBaselineWithoutClaimingAnotherExposure() throws {
        let comparison = try XCTUnwrap(ExerciseProgressComparison.make(exercise: bench,
                                                                       workouts: [workout("only", daysAgo: 1, sets: [working(60)])], now: now))
        XCTAssertFalse(comparison.hasMultipleExposures)
        XCTAssertEqual(comparison.completedExposureCount, 1)
        XCTAssertEqual(comparison.first, comparison.latest)
        XCTAssertEqual(comparison.topWorkingLoadChangeKg, 0)
    }

    func testBoundedSetSampleKeepsFullTotalsAndUnknownEffort() throws {
        let sets = (0..<12).map { working(Double(40 + $0), reps: 8, effort: $0 == 11 ? nil : .challenging) }
        let comparison = try XCTUnwrap(ExerciseProgressComparison.make(exercise: bench,
                                                                       workouts: [workout("many-sets", daysAgo: 1, sets: sets)], now: now))
        XCTAssertEqual(comparison.latest.workingSetSample.count, 10)
        XCTAssertEqual(comparison.latest.workingSetCount, 12)
        XCTAssertEqual(comparison.latest.totalWorkingReps, 96)
        XCTAssertEqual(comparison.latest.topWorkingLoadKg, 51)
        XCTAssertEqual(comparison.latest.workingSetsWithEffort, 11)
        XCTAssertEqual(comparison.latest.workingVolumeKg, sets.reduce(0) { $0 + $1.volume })
        XCTAssertEqual(try XCTUnwrap(comparison.latest.estimatedOneRepMaxKg), 50 * (1 + 8.0 / 30), accuracy: 0.0001)
        XCTAssertEqual(try JSONDecoder().decode(ExerciseProgressComparison.self, from: JSONEncoder().encode(comparison)), comparison)
    }

    func testEstimatesRequireKnownRepetitionLoadAndEligibleEffort() throws {
        let recorded = workout("recorded", daysAgo: 1, sets: [working(60)])
        let known = try XCTUnwrap(ExerciseProgressComparison.make(exercise: bench, workouts: [recorded], now: now))
        XCTAssertEqual(try XCTUnwrap(known.latest.estimatedOneRepMaxKg), 76, accuracy: 0.0001)
        for metadata in [
            ExerciseMetadata(primaryMuscles: [.chest], loadConvention: .unknown),
            ExerciseMetadata(primaryMuscles: [.chest], loadConvention: .bodyweight),
            ExerciseMetadata(primaryMuscles: [.chest], measurement: .seconds, loadConvention: .totalExternalWeight)
        ] {
            var changed = bench
            changed.metadata = metadata
            let comparison = try XCTUnwrap(ExerciseProgressComparison.make(exercise: changed, workouts: [recorded], now: now))
            XCTAssertNil(comparison.latest.estimatedOneRepMaxKg)
            XCTAssertEqual(comparison.latest.topWorkingLoadKg, 60)
        }
        let unknownEffort = workout("unknown-effort", daysAgo: 1, sets: [working(60, effort: nil)])
        let comparison = try XCTUnwrap(ExerciseProgressComparison.make(exercise: bench, workouts: [unknownEffort], now: now))
        XCTAssertNil(comparison.latest.estimatedOneRepMaxKg)
        XCTAssertEqual(comparison.latest.workingSetsWithEffort, 0)
        XCTAssertEqual(comparison.latest.workingSetCount, 1)
    }
}
