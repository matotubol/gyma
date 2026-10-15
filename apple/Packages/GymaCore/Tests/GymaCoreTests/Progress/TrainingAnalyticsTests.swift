import XCTest
@testable import GymaCore

final class TrainingAnalyticsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func workout(_ id: String, daysAgo: Double, exerciseID: String = "bench_press", sets: [WorkSet]) -> Workout {
        let date = now.addingTimeInterval(-daysAgo * 86400)
        return .init(id: id, start: date.addingTimeInterval(-1200), end: date, exercises: [.init(exerciseID: exerciseID, sets: sets)])
    }
    private var working: WorkSet { .init(kg: 60, reps: 8, effort: .challenging, isWarmup: false) }

    func testEstimatedMaximumRequiresComparableClassifiedHardSets() throws {
        let ineligible: [WorkSet] = [
            .init(kg: 100, reps: 8, isWarmup: false),
            .init(kg: 100, reps: 8, effort: .easy, isWarmup: false),
            .init(kg: 100, reps: 11, effort: .limit, isWarmup: false),
            .init(kg: 100, reps: 8, effort: .limit),
            .init(kg: 100, reps: 8, effort: .limit, isWarmup: true),
            .init(kg: 0, reps: 8, effort: .limit, isWarmup: false)
        ]
        XCTAssertNil(TrainingAnalytics.estimatedOneRepMax(for: ineligible))
        XCTAssertEqual(try XCTUnwrap(TrainingAnalytics.estimatedOneRepMax(for: ineligible + [working])), 76, accuracy: 0.0001)
        XCTAssertEqual(TrainingAnalytics.estimatedOneRepMax(for: [.init(kg: 80, reps: 1, effort: .limit, isWarmup: false)]), 80)
    }

    func testRollingVolumeSeparatesDirectSecondaryWarmupAndUnknown() throws {
        let week = workout("week", daysAgo: 1, sets: [working, .init(kg: 60, reps: 8, isWarmup: false), .init(kg: 20, reps: 8, isWarmup: true), .init(kg: 30, reps: 8)])
        let older = workout("older", daysAgo: 10, sets: [working])
        let stale = workout("stale", daysAgo: 29, sets: [working])
        let stats = TrainingAnalytics.make(workouts: [week, older, stale], catalog: ExerciseCatalog.builtIn, now: now)
        XCTAssertEqual(stats.volume7Days.first { $0.muscle == .chest }?.directSets, 2)
        XCTAssertEqual(stats.volume7Days.first { $0.muscle == .triceps }?.directSets, 0)
        XCTAssertEqual(stats.volume7Days.first { $0.muscle == .triceps }?.secondarySets, 2)
        XCTAssertEqual(stats.volume28Days.first { $0.muscle == .chest }?.directSets, 3)
        XCTAssertEqual(stats.quality7Days.workingSetCount, 2)
        XCTAssertEqual(stats.quality7Days.workingSetsWithEffort, 1)
        XCTAssertEqual(stats.quality7Days.effortCoverage, 0.5)
        XCTAssertEqual(stats.quality7Days.warmupSetCount, 1)
        XCTAssertEqual(stats.quality7Days.unclassifiedSetCount, 1)
        XCTAssertEqual(stats.dataQuality.completedWorkoutCount, 3)
        XCTAssertEqual(stats.dataQuality.workingSetCount, 4)
    }

    func testFullHistoryRetainsRelevantLiftBeyondLastSixWorkouts() throws {
        var history = (1...8).map { workout("squat-\($0)", daysAgo: Double($0), exerciseID: "squat", sets: [working]) }
        history.append(workout("old-bench", daysAgo: 20, sets: [working]))
        let stats = TrainingAnalytics.make(workouts: history, catalog: ExerciseCatalog.builtIn, now: now, relevantExerciseIDs: ["bench_press"])
        XCTAssertEqual(stats.exposures.count, 1)
        XCTAssertEqual(stats.exposures[0].totalCompletedExposures, 1)
        XCTAssertEqual(stats.exposures[0].recentExposures.first?.workoutID, "old-bench")
        XCTAssertEqual(stats.volume28Days.first { $0.muscle == .chest }?.directSets, 1)
        XCTAssertEqual(stats.volume28Days.first { $0.muscle == .quadriceps }?.directSets, 8)
    }

    func testActiveFutureAndBoundaryWorkoutsDoNotPolluteWindows() throws {
        var active = workout("active", daysAgo: 0, sets: [working]); active.end = nil
        let future = workout("future", daysAgo: -1, sets: [working])
        let boundary = workout("boundary", daysAgo: 7, sets: [working])
        let stats = TrainingAnalytics.make(workouts: [active, future, boundary], catalog: ExerciseCatalog.builtIn, now: now)
        XCTAssertEqual(stats.dataQuality.completedWorkoutCount, 1)
        XCTAssertEqual(stats.quality7Days.workingSetCount, 0)
        XCTAssertNil(stats.quality7Days.effortCoverage)
        XCTAssertEqual(stats.quality28Days.workingSetCount, 1)
    }

    func testCustomMusclesStayUnknownUntilExplicitlyConfigured() throws {
        var custom = ExerciseDefinition(id: "custom", name: "My machine", muscle: .legs, custom: true)
        let history = [workout("custom-workout", daysAgo: 1, exerciseID: custom.id, sets: [working])]
        let unknown = TrainingAnalytics.make(workouts: history, catalog: [custom], now: now)
        XCTAssertEqual(unknown.quality7Days.workingSetsWithoutMuscleMetadata, 1)
        XCTAssertEqual(unknown.volume7Days.reduce(0) { $0 + $1.directSets }, 0)
        custom.metadata = .init(primaryMuscles: [.quadriceps], secondaryMuscles: [.glutes], equipment: .machines, loadConvention: .machineStack)
        let known = TrainingAnalytics.make(workouts: history, catalog: [custom], now: now)
        XCTAssertEqual(known.quality7Days.workingSetsWithoutMuscleMetadata, 0)
        XCTAssertEqual(known.volume7Days.first { $0.muscle == .quadriceps }?.directSets, 1)
        XCTAssertEqual(known.volume7Days.first { $0.muscle == .glutes }?.secondarySets, 1)
        XCTAssertThrowsError(try ExerciseMetadata(primaryMuscles: [.chest], secondaryMuscles: [.chest]).validate())
    }

    func testReviewUsesActualWorkAndDoesNotInventEffortOrAProgram() throws {
        var recorded = workout("review", daysAgo: 0, sets: [working, .init(kg: 55, reps: 6, isWarmup: false), .init(kg: 20, reps: 5, isWarmup: true)])
        recorded.exercises[0].target = .init(sets: 3, repsMin: 8, repsMax: 10, loadKg: 60, targetEffort: .challenging)
        let review = WorkoutReview.make(workout: recorded, history: [recorded], program: nil, catalog: ExerciseCatalog.builtIn, now: now)
        let entry = try XCTUnwrap(review.exercises.first)
        XCTAssertEqual(entry.actualWorkingSets, 2)
        XCTAssertEqual(entry.target?.sets, 3)
        XCTAssertEqual(entry.setsBelowRepMinimum, 1)
        XCTAssertEqual(entry.missingEffortSets, 1)
        XCTAssertEqual(entry.minWorkingLoadKg, 55)
        XCTAssertEqual(entry.maxWorkingLoadKg, 60)
        XCTAssertEqual(entry.totalWorkingReps, 14)
        XCTAssertNil(entry.recommendation)
        XCTAssertTrue(review.summary.contains("unknown"))
        XCTAssertNoThrow(try review.validate())
        XCTAssertEqual(try JSONDecoder().decode(WorkoutReview.self, from: JSONEncoder().encode(review)), review)
    }

    func testReviewProgressionIncludesFinishedWorkoutExactlyOnce() throws {
        let target = ExerciseTarget(sets: 1, repsMin: 8, repsMax: 10, loadKg: 60, targetEffort: .challenging)
        let session = ProgramSession(id: "a", title: "A", exercises: [.init(exerciseID: "bench_press", target: target)])
        let program = TrainingProgram(id: "program", title: "Program", goal: "Strength", sessions: [session], createdAt: now, updatedAt: now)
        var recorded = workout("finished", daysAgo: 0, sets: [.init(kg: 60, reps: 10, effort: .challenging, isWarmup: false)])
        recorded.exercises[0].target = target
        recorded.programID = program.id; recorded.programSessionID = session.id; recorded.programRevision = 1
        let review = WorkoutReview.make(workout: recorded, history: [recorded], program: program, catalog: ExerciseCatalog.builtIn, now: now)
        XCTAssertEqual(review.exercises.first?.recommendation?.action, .repeatTarget)
        XCTAssertEqual(review.exercises.first?.recommendation?.evidenceWorkoutIDs, [recorded.id])
        XCTAssertNoThrow(try review.validate())
    }
}
