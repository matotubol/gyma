import XCTest
@testable import GymaCore

final class TrainingHistoryContinuityTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return value
    }

    private var start: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12))!
    }

    private func completedBlock() throws -> GymaState {
        var state = GymaState()
        let target = ExerciseTarget(sets: 1, repsMin: 6, repsMax: 10, loadKg: 60, targetEffort: .challenging)
        state.trainingProgram = .init(id: "history-program", title: "Upper / lower", goal: "Consistent training", sessions: [
            .init(id: "upper", title: "Upper", exercises: [.init(exerciseID: "bench_press", target: target)]),
            .init(id: "lower", title: "Lower", exercises: [.init(exerciseID: "squat", target: target)])
        ], createdAt: start, updatedAt: start)
        state.trainingCalendar = .init(startDate: start,
                                       cycleAnchorDate: calendar.date(byAdding: .day, value: 4, to: start)!,
                                       timeZone: calendar.timeZone)
        state.workouts = (0..<8).map { index in
            let performed = calendar.date(byAdding: .day, value: index * 7, to: start)!
            return Workout(id: "week-\(index + 1)", start: performed, end: performed.addingTimeInterval(1800),
                           planTitle: "Upper week \(index + 1)", exercises: [
                            .init(exerciseID: "bench_press", sets: [
                                .init(id: "working-\(index)", kg: 60 + Double(index) * 2.5, reps: 8,
                                      effort: .challenging, isWarmup: false)
                            ], target: target)
                           ], programID: "history-program", programSessionID: "upper", programRevision: 1)
        }
        state.workoutReviews = state.workouts.map {
            WorkoutReview.make(workout: $0, history: state.workouts, program: state.trainingProgram,
                               catalog: state.catalog, now: $0.end!)
        }
        state.workoutFeedback = [.init(workoutID: "week-1", recordedAt: start.addingTimeInterval(1800),
                                      note: "First session with this equipment.")]
        try state.validate()
        return state
    }

    private func rollOver(_ state: inout GymaState) throws {
        let previous = try XCTUnwrap(state.trainingCalendar)
        let next = try previous.reconfigured(startDate: previous.reviewDate, cycleAnchorDate: previous.cycleAnchorDate,
                                             trainingCycleDays: previous.trainingCycleDays, prefersUpperLower: previous.prefersUpperLower)
        try state.saveTrainingCalendar(next, now: next.startDate)
    }

    func testEightWeekRolloverPreservesResultsReviewsFeedbackAndRotationThroughBackup() throws {
        var state = try completedBlock()
        let original = state
        let previous = try XCTUnwrap(state.trainingCalendar)
        XCTAssertEqual(previous.dates.count, 56)
        try rollOver(&state)

        XCTAssertEqual(state.workouts, original.workouts)
        XCTAssertEqual(state.workoutReviews, original.workoutReviews)
        XCTAssertEqual(state.workoutFeedback, original.workoutFeedback)
        XCTAssertEqual(state.trainingProgram, original.trainingProgram)
        XCTAssertEqual(state.trainingCalendarHistory, [previous])
        XCTAssertEqual(state.trainingProgram?.nextSession(history: state.workouts, now: previous.reviewDate)?.id, "lower")

        let analytics = TrainingAnalytics.make(workouts: state.workouts, catalog: state.catalog, now: previous.reviewDate)
        let bench = try XCTUnwrap(analytics.exposures.first { $0.exerciseID == "bench_press" })
        XCTAssertEqual(analytics.dataQuality.completedWorkoutCount, 8)
        XCTAssertEqual(bench.totalCompletedExposures, 8)
        XCTAssertEqual(bench.recentExposures.count, 4)
        XCTAssertEqual(bench.recentExposures.first?.topWorkingLoadKg, 77.5)
        XCTAssertFalse(bench.recentExposures.contains { $0.workoutID == "week-1" })
        let comparison = try XCTUnwrap(ExerciseProgressComparison.make(exercise: state.exercise("bench_press"),
                                                                       workouts: state.workouts, now: previous.reviewDate))
        XCTAssertEqual(comparison.completedExposureCount, 8)
        XCTAssertEqual(comparison.first.workoutID, "week-1")
        XCTAssertEqual(comparison.first.topWorkingLoadKg, 60)
        XCTAssertEqual(comparison.latest.workoutID, "week-8")
        XCTAssertEqual(comparison.latest.topWorkingLoadKg, 77.5)
        XCTAssertEqual(comparison.topWorkingLoadChangeKg, 17.5)

        let restored = try NativeBackup.decode(NativeBackup.encode(state))
        XCTAssertEqual(restored, state)
        let archived = try XCTUnwrap(restored.trainingCalendarHistory?.first)
        let days = archived.entries(program: nil, history: restored.workouts, now: previous.reviewDate)
        XCTAssertEqual(days.first?.workouts.first?.id, "week-1")
        XCTAssertEqual(days.flatMap(\.workouts).count, 8)
        XCTAssertEqual(restored.workouts.first?.exercises.first?.sets.first?.kg, 60)
        XCTAssertEqual(restored.workouts.last?.exercises.first?.sets.first?.kg, 77.5)
    }

    func testOldCompletedWorkoutCanStillBeReviewedBeyondRecentCoachWindowsAfterRollover() throws {
        var state = try completedBlock()
        try rollOver(&state)
        let now = try XCTUnwrap(state.trainingCalendar?.startDate)
        let original = try XCTUnwrap(state.workouts.first)
        try state.appendWorkoutCoachMessage("Review this first session and compare the saved evidence.", workoutID: original.id)
        let selected = try XCTUnwrap(state.workouts.first)
        XCTAssertEqual(selected.exercises, original.exercises)
        XCTAssertEqual(selected.end, original.end)
        XCTAssertFalse(try CoachAPI.historyContext(state.workouts).contains("Upper week 1"))

        let body = try WorkoutCoachAPI.requestBody(workout: selected, storeID: state.storeID, revision: state.revision,
                                                  restTimer: nil, catalog: state.catalog, history: state.workouts, now: now,
                                                  program: state.trainingProgram, reviews: state.workoutReviews ?? [],
                                                  feedback: state.workoutFeedback ?? [], trainingCalendar: state.trainingCalendar,
                                                  trainingCalendarHistory: state.trainingCalendarHistory ?? [])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let content = try XCTUnwrap((json["input"] as? [[String: String]])?.first?["content"])
        XCTAssertTrue(content.contains("COMPLETED: review actual results"))
        XCTAssertTrue(content.contains("First session with this equipment."))
        let prefix = "Live workout at the moment this message was sent: "
        let liveLine = try XCTUnwrap(content.components(separatedBy: "\n").first { $0.hasPrefix(prefix) })
        let liveData = Data(liveLine.dropFirst(prefix.count).utf8)
        let live = try XCTUnwrap(JSONSerialization.jsonObject(with: liveData) as? [String: Any])
        XCTAssertEqual(live["id"] as? String, "week-1")
        let exercise = try XCTUnwrap((live["exercises"] as? [[String: Any]])?.first)
        let actual = try XCTUnwrap((exercise["recentActualSets"] as? [[String: Any]])?.first)
        XCTAssertEqual(actual["kg"] as? Double, 60)
        XCTAssertEqual(actual["reps"] as? Int, 8)
        XCTAssertEqual(actual["effort"] as? String, "challenging")
    }
}
