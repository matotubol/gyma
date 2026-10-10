import XCTest
@testable import GymaCore

final class CalendarAbsRecoveryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return value
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func configuredState(withAbsProgram: Bool = false) throws -> GymaState {
        var state = GymaState()
        let plan = TrainingCalendarPlan(startDate: date(13), cycleAnchorDate: date(17), trainingCycleDays: [2], timeZone: calendar.timeZone)
        try state.saveTrainingCalendar(plan, now: date(10))
        if withAbsProgram {
            state.trainingProgram = .init(id: "abs-program", title: "Strength", goal: "Strength", sessions: [
                .init(id: "strength", title: "Strength with abs", exercises: [
                    .init(exerciseID: "squat", target: .init(sets: 2, repsMin: 6, repsMax: 8)),
                    .init(exerciseID: "crunches", target: .init(sets: 2, repsMin: 8, repsMax: 12))
                ])
            ], createdAt: date(1), updatedAt: date(1))
        }
        return state
    }
    private func absWorkout(on date: Date, warmup: Bool? = false) -> Workout {
        .init(id: "recorded-abs", start: date, end: date.addingTimeInterval(1800), exercises: [
            .init(exerciseID: "crunches", sets: [.init(kg: 0, reps: 10, effort: .challenging, isWarmup: warmup)])
        ])
    }

    func testAdjacentRecordedAbsBlocksPlanningEvenOutsideCalendarAndWithoutWarmupClassification() throws {
        let classifications: [Bool?] = [false, nil]
        for warmup in classifications {
            var state = try configuredState()
            state.workouts = [absWorkout(on: date(12), warmup: warmup)]
            let before = state
            XCTAssertThrowsError(try state.setCalendarActivity(on: date(13), kind: .abs, isPlanned: true, now: date(13)))
            XCTAssertEqual(state, before)
            try state.setCalendarActivity(on: date(14), kind: .abs, isPlanned: true, now: date(13))
            try state.validate()
        }
        var warmupOnly = try configuredState()
        warmupOnly.workouts = [absWorkout(on: date(12), warmup: true)]
        try warmupOnly.setCalendarActivity(on: date(13), kind: .abs, isPlanned: true, now: date(13))
        try warmupOnly.validate()
    }

    func testNewlyRecordedAbsPreventsCompletionButStillAllowsRemovingOptionalPlan() throws {
        var state = try configuredState()
        try state.setCalendarActivity(on: date(14), kind: .abs, isPlanned: true, now: date(13))
        state.workouts = [absWorkout(on: date(13))]
        let before = state
        XCTAssertThrowsError(try state.setCalendarActivityCompleted(on: date(14), kind: .abs, isCompleted: true, now: date(14)))
        XCTAssertEqual(state, before)
        try state.setCalendarActivity(on: date(14), kind: .abs, isPlanned: false, now: date(14))
        XCTAssertTrue(state.trainingCalendar?.activities.isEmpty == true)
        XCTAssertEqual(state.workouts, before.workouts)
    }

    func testProjectedStrengthAbsBlockAdjacentOptionalAbsInEitherDirection() throws {
        let state = try configuredState(withAbsProgram: true)
        for day in [17, 19] {
            var candidate = state
            XCTAssertThrowsError(try candidate.setCalendarActivity(on: date(day), kind: .abs, isPlanned: true, now: date(13)))
            XCTAssertEqual(candidate, state)
        }
        var rested = state
        try rested.setCalendarActivity(on: date(16), kind: .abs, isPlanned: true, now: date(13))
        try rested.setCalendarActivity(on: date(17), kind: .stretching, isPlanned: true, now: date(13))
        try rested.validate()
    }

    func testAllReschedulingPathsRespectOptionalAbsCompletedTodayOrYesterday() throws {
        for now in [date(13), date(14)] {
            for operation in 0..<3 {
                var state = try configuredState(withAbsProgram: true)
                try state.setCalendarActivity(on: date(13), kind: .abs, isPlanned: true, now: date(13))
                try state.setCalendarActivityCompleted(on: date(13), kind: .abs, isCompleted: true, now: date(13))
                let before = state
                switch operation {
                case 0:
                    XCTAssertThrowsError(try state.setCalendarTrainingDay(on: date(14), isTraining: true, now: now))
                case 1:
                    XCTAssertThrowsError(try state.moveCalendarTrainingDay(from: date(18), to: date(14), now: now))
                default:
                    var changed = try XCTUnwrap(state.trainingCalendar)
                    try changed.setTrainingDay(on: date(14), isTraining: true, now: now)
                    XCTAssertThrowsError(try state.saveTrainingCalendar(changed, now: now))
                }
                XCTAssertEqual(state, before)
            }
        }
    }

    func testReconfigurationRespectsPlannedAbsAndDoesNotRejectUnrelatedOldHistory() throws {
        var state = try configuredState(withAbsProgram: true)
        try state.setCalendarActivity(on: date(13), kind: .abs, isPlanned: true, now: date(13))
        let planned = state
        XCTAssertThrowsError(try state.moveCalendarTrainingDay(from: date(18), to: date(14), now: date(13)))
        XCTAssertEqual(state, planned)
        try state.setCalendarActivityCompleted(on: date(13), kind: .abs, isCompleted: true, now: date(13))
        // Imported actual history must stay editable in its own workflow; an unrelated future
        // calendar change cannot reject the state because two historical efforts were adjacent.
        state.workouts = [absWorkout(on: date(12))]
        try state.moveCalendarTrainingDay(from: date(18), to: date(20), now: date(14))
        XCTAssertEqual(state.trainingCalendar?.activities(on: date(13)).first?.isCompleted, true)
        XCTAssertTrue(state.trainingCalendar?.isTrainingDay(on: date(20)) == true)
        try state.validate()
    }
}
