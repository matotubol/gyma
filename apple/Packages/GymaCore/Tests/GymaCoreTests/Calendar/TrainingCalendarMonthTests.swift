import XCTest
@testable import GymaCore

final class TrainingCalendarMonthTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return value
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 12, year: Int = 2026,
                      in source: Calendar? = nil) -> Date {
        (source ?? calendar).date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func completed(_ id: String, on start: Date) -> Workout {
        .init(id: id, start: start, end: start.addingTimeInterval(1800), exercises: [
            .init(exerciseID: "bench_press", sets: [.init(kg: 60, reps: 8, effort: .challenging, isWarmup: false)])
        ])
    }

    private func program() -> TrainingProgram {
        let target = ExerciseTarget(sets: 3, repsMin: 6, repsMax: 10, loadKg: 60)
        return .init(id: "month-program", title: "Upper / lower", goal: "Build strength", sessions: [
            .init(id: "upper", title: "Upper", exercises: [.init(exerciseID: "bench_press", target: target)]),
            .init(id: "lower", title: "Lower", exercises: [.init(exerciseID: "squat", target: target)])
        ], createdAt: date(10, 1), updatedAt: date(10, 1))
    }

    func testOctoberShowsEveryDateAndTodayBeforeTheBlockStarts() throws {
        var state = GymaState()
        state.trainingCalendar = .defaultPlan(now: date(10, 10), timeZone: calendar.timeZone)
        state.trainingProgram = program()
        let month = TrainingCalendarMonth.make(state: state, containing: date(10, 10), now: date(10, 10))

        XCTAssertEqual(month.monthStart, date(10, 1, hour: 0))
        XCTAssertEqual(month.days.count, 31)
        XCTAssertEqual(Set(month.days.map(\.id)).count, 31)
        XCTAssertEqual(month.days.last?.date, date(10, 31, hour: 0))
        XCTAssertEqual(month.days.filter(\.isToday).map(\.date), [date(10, 10, hour: 0)])
        XCTAssertTrue(month.days.prefix(12).allSatisfy { $0.plan == nil && $0.scheduledDay == nil })
        XCTAssertEqual(month.days[12].scheduledDay?.dayOffset, 0)
        XCTAssertEqual(month.days[12].scheduledDay?.session?.id, "upper")
        XCTAssertTrue(month.days[12].isCurrentPlan)

        let december = TrainingCalendarMonth.make(state: state, containing: date(12, 20), now: date(10, 10))
        XCTAssertEqual(december.days.count, 31)
        XCTAssertNotNil(december.days[6].scheduledDay)
        XCTAssertTrue(december.days.dropFirst(7).allSatisfy { $0.scheduledDay == nil })
    }

    func testMonthNavigationCrossesYearsAndLeapDayUsingCivilDatesThroughDST() throws {
        let state = GymaState()
        let december = TrainingCalendarMonth.make(state: state, containing: date(12, 31), now: date(12, 31), calendar: calendar)
        XCTAssertEqual(december.month(byAdding: 1), date(1, 1, hour: 0, year: 2027))
        XCTAssertEqual(december.month(byAdding: -12), date(12, 1, hour: 0, year: 2025))
        let january = TrainingCalendarMonth.make(state: state, containing: try XCTUnwrap(december.month(byAdding: 1)),
                                                 now: date(12, 31), calendar: calendar)
        XCTAssertEqual(january.month(byAdding: -1), december.monthStart)
        let leap = TrainingCalendarMonth.make(state: state, containing: date(2, 15, year: 2028),
                                              now: date(12, 31), calendar: calendar)
        XCTAssertEqual(leap.days.count, 29)
        XCTAssertEqual(leap.days.last?.date, date(2, 29, hour: 0, year: 2028))
        let ordinary = TrainingCalendarMonth.make(state: state, containing: date(2, 15, year: 2027),
                                                  now: date(12, 31), calendar: calendar)
        XCTAssertEqual(ordinary.days.count, 28)

        let march = TrainingCalendarMonth.make(state: state, containing: date(3, 29), now: date(3, 29), calendar: calendar)
        let october = TrainingCalendarMonth.make(state: state, containing: date(10, 25), now: date(10, 25), calendar: calendar)
        XCTAssertEqual(march.days[29].date.timeIntervalSince(march.days[28].date), 23 * 3600)
        XCTAssertEqual(october.days[25].date.timeIntervalSince(october.days[24].date), 25 * 3600)
        XCTAssertTrue((march.days + october.days).allSatisfy { calendar.component(.hour, from: $0.date) == 0 })
        XCTAssertEqual(Set(march.days.map(\.id)).count, 31)
        XCTAssertEqual(Set(october.days.map(\.id)).count, 31)
    }

    func testRecordedWorkoutsSurviveBeforeAndAcrossSavedBlocksWithoutInventingOldSessions() throws {
        var state = GymaState()
        var archived = TrainingCalendarPlan(startDate: date(10, 1), cycleAnchorDate: date(10, 1), timeZone: calendar.timeZone)
        archived.activities = [.init(dayOffset: 55, kind: .stretching, isCompleted: true)]
        state.trainingCalendarHistory = [archived]
        state.trainingCalendar = .init(startDate: archived.reviewDate, cycleAnchorDate: archived.cycleAnchorDate,
                                       timeZone: calendar.timeZone)
        state.trainingProgram = program()
        let earlier = completed("standalone-before-blocks", on: date(9, 20))
        let archivedWorkout = completed("archived", on: date(11, 25))
        let currentWorkout = completed("current", on: date(11, 27))
        state.workouts = [currentWorkout, earlier, archivedWorkout]
        let original = state

        let september = TrainingCalendarMonth.make(state: state, containing: date(9, 20), now: date(12, 1))
        XCTAssertEqual(september.days.flatMap(\.workouts), [earlier])
        XCTAssertNil(september.days[19].scheduledDay)
        let november = TrainingCalendarMonth.make(state: state, containing: date(11, 1), now: date(12, 1))
        XCTAssertEqual(november.days.flatMap(\.workouts), [archivedWorkout, currentWorkout])
        XCTAssertFalse(november.days[24].isCurrentPlan)
        XCTAssertEqual(november.days[24].activities, archived.activities)
        XCTAssertTrue(november.days[25].isCurrentPlan)
        XCTAssertEqual(november.days[25].scheduledDay?.dayOffset, 0)
        XCTAssertTrue(november.days.allSatisfy { $0.scheduledDay?.session == nil })
        XCTAssertEqual(state, original)
    }

    func testWithoutAnActivePlanTheMonthStillShowsArchivedActivitiesAndStandaloneHistory() {
        var state = GymaState()
        var archived = TrainingCalendarPlan(startDate: date(10, 1), cycleAnchorDate: date(10, 1), timeZone: calendar.timeZone)
        archived.activities = [.init(dayOffset: 2, kind: .inclineWalking, isCompleted: true)]
        state.trainingCalendarHistory = [archived]
        state.trainingProgram = program()
        let actual = completed("early", on: date(10, 3, hour: 8))
        let future = completed("future", on: date(10, 30))
        state.workouts = [future, actual]
        let month = TrainingCalendarMonth.make(state: state, containing: date(10, 1), now: date(10, 20), calendar: calendar)

        XCTAssertEqual(month.calendar.timeZone, calendar.timeZone)
        XCTAssertEqual(month.days.count, 31)
        XCTAssertEqual(month.days.flatMap(\.workouts), [actual])
        XCTAssertEqual(month.days[2].activities, archived.activities)
        XCTAssertTrue(month.days.allSatisfy { !$0.isCurrentPlan && $0.scheduledDay?.session == nil })
    }

    func testArchivedCivilDatesStaySavedWhileWorkoutsUseOneDisplayZoneAndCurrentPlanWinsOverlap() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var state = GymaState()
        var archived = TrainingCalendarPlan(startDate: date(10, 1, in: tokyo), cycleAnchorDate: date(10, 1, in: tokyo),
                                             timeZone: tokyo.timeZone)
        archived.activities = [.init(dayOffset: 0, kind: .stretching, isCompleted: true),
                               .init(dayOffset: 12, kind: .inclineWalking, isCompleted: true)]
        state.trainingCalendarHistory = [archived]
        state.trainingCalendar = .init(startDate: date(10, 13), cycleAnchorDate: date(10, 17), timeZone: calendar.timeZone)
        let acrossMidnight = completed("tokyo-october-2", on: date(10, 2, hour: 1, in: tokyo))
        let overlapping = completed("overlap", on: date(10, 13))
        state.workouts = [acrossMidnight, overlapping]
        let month = TrainingCalendarMonth.make(state: state, containing: date(10, 1), now: date(10, 20), calendar: tokyo)

        XCTAssertEqual(month.calendar.timeZone, calendar.timeZone)
        XCTAssertEqual(month.days[0].scheduledDay?.dayOffset, 0)
        XCTAssertEqual(month.days[0].scheduledDay?.date, archived.startDate)
        XCTAssertEqual(month.days[0].activities.first?.kind, .stretching)
        XCTAssertEqual(month.days[0].workouts, [acrossMidnight])
        XCTAssertEqual(month.days[0].scheduledDay?.workouts, [acrossMidnight])
        XCTAssertTrue(month.days[1].workouts.isEmpty)
        XCTAssertTrue(month.days[12].isCurrentPlan)
        XCTAssertEqual(month.days[12].scheduledDay?.dayOffset, 0)
        XCTAssertTrue(month.days[12].activities.isEmpty)
        XCTAssertEqual(month.days[12].workouts, [overlapping])
        XCTAssertEqual(month.days.flatMap(\.workouts).count, 2)
    }

    func testMonthBoundaryDoesNotRestartSessionRotationAndActiveWorkoutStaysOnItsStartDate() throws {
        var state = GymaState()
        state.trainingCalendar = .defaultPlan(now: date(10, 10), timeZone: calendar.timeZone)
        state.trainingProgram = program()
        let now = date(10, 31, hour: 23)
        var active = completed("overnight", on: now)
        active.end = nil
        state.workouts = [active]
        let afterMidnight = date(11, 1, hour: 1)
        let october = TrainingCalendarMonth.make(state: state, containing: date(10, 1), now: afterMidnight)
        let november = TrainingCalendarMonth.make(state: state, containing: date(11, 1), now: afterMidnight)
        let expected = try XCTUnwrap(state.trainingCalendar).entries(program: state.trainingProgram,
                                                                     history: state.workouts, now: afterMidnight)
            .filter { calendar.component(.month, from: $0.date) == 11 }

        XCTAssertEqual(october.days.last?.workouts, [active])
        XCTAssertTrue(november.days.flatMap(\.workouts).isEmpty)
        XCTAssertEqual(november.days.compactMap { $0.scheduledDay?.session }, expected.compactMap(\.session))
        XCTAssertEqual(state.workouts, [active])
    }
}
