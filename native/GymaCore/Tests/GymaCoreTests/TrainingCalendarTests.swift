import XCTest
@testable import GymaCore

final class TrainingCalendarTests: XCTestCase {
    private var timeZone: TimeZone { TimeZone(identifier: "Europe/Amsterdam")! }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }
    private func date(_ month: Int, _ day: Int, hour: Int = 12, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func plan() -> TrainingCalendarPlan {
        .init(startDate: date(10, 17), cycleAnchorDate: date(10, 17), timeZone: timeZone)
    }
    private func program() -> TrainingProgram {
        .init(id: "upper-lower", title: "Upper / lower", goal: "Build strength", sessions: [
            .init(id: "upper-a", title: "Upper A", exercises: [.init(exerciseID: "bench_press", target: .init(sets: 3, repsMin: 6, repsMax: 10, loadKg: 60))]),
            .init(id: "lower-a", title: "Lower A", exercises: [.init(exerciseID: "squat", target: .init(sets: 3, repsMin: 6, repsMax: 10, loadKg: 80))]),
            .init(id: "upper-b", title: "Upper B", exercises: [.init(exerciseID: "lat_pulldown", target: .init(sets: 3, repsMin: 8, repsMax: 12, loadKg: 50))]),
            .init(id: "lower-b", title: "Lower B", exercises: [.init(exerciseID: "leg_press", target: .init(sets: 3, repsMin: 8, repsMax: 12, loadKg: 100))])
        ], createdAt: date(10, 1), updatedAt: date(10, 1))
    }
    private func completed(on start: Date, sessionID: String = "upper-a", id: String = "completed") -> Workout {
        .init(id: id, start: start, end: start.addingTimeInterval(1800), exercises: [
            .init(exerciseID: "bench_press", sets: [.init(kg: 60, reps: 8, effort: .challenging, isWarmup: false)])
        ], programID: "upper-lower", programSessionID: sessionID, programRevision: 1)
    }

    func testBlockContains56CivilDaysAcrossAmsterdamDSTAndEndsOnDecember11() throws {
        let value = plan()
        try value.validate()
        XCTAssertEqual(value.dates.count, 56)
        XCTAssertEqual(Set(value.dates).count, 56)
        XCTAssertEqual(value.startDate, date(10, 17, hour: 0))
        XCTAssertEqual(value.lastDate, date(12, 11, hour: 0))
        XCTAssertEqual(value.reviewDate, date(12, 12, hour: 0))
        for (index, day) in value.dates.enumerated() {
            XCTAssertEqual(value.dayOffset(for: day), index)
            XCTAssertEqual(value.calendar.component(.hour, from: day), 0)
        }
        let october25 = try XCTUnwrap(value.date(at: 8))
        let october26 = try XCTUnwrap(value.date(at: 9))
        XCTAssertEqual(october26.timeIntervalSince(october25), 25 * 3600)
        XCTAssertEqual(value.dayOffset(for: date(10, 25, hour: 23)), 8)
        XCTAssertEqual(value.cycleDay(on: october25), 9)
        XCTAssertEqual(value.cycleDay(on: october26), 10)
        XCTAssertNil(value.date(at: -1))
        XCTAssertNil(value.date(at: 56))
        XCTAssertNil(value.dayOffset(for: date(10, 16)))
        XCTAssertNil(value.dayOffset(for: date(12, 12)))
    }

    func testCycleAndShiftRepeatAcrossAnchorInBothDirections() {
        let value = plan()
        XCTAssertEqual((17...26).map { value.cycleDay(on: date(10, $0)) }, Array(1...10))
        XCTAssertEqual((17...26).map { value.shift(on: date(10, $0)) }, [.morning, .morning, .afternoon, .afternoon, .night, .night, .off, .off, .off, .off])
        XCTAssertEqual(value.cycleDay(on: date(10, 16)), 10)
        XCTAssertEqual(value.shift(on: date(10, 16)), .off)
        XCTAssertEqual(value.cycleDay(on: date(10, 7)), 1)
        XCTAssertEqual(value.cycleDay(on: date(10, 6)), 10)
        XCTAssertEqual(value.cycleDay(on: date(10, 27)), 1)
        XCTAssertEqual(value.cycleDay(on: date(12, 12)), 7)
    }

    func testConfirmedPatternHasFiveSlotsPerFullCycleAnd27InEightWeeks() {
        let value = plan()
        for start in stride(from: 0, to: 50, by: 10) {
            let trainingDays = value.dates[start..<(start + 10)].filter { value.isTrainingDay(on: $0) }
            XCTAssertEqual(trainingDays.count, 5)
            XCTAssertEqual(trainingDays.map { value.cycleDay(on: $0) }, [2, 5, 8, 9, 10])
        }
        let trainingDates = value.dates.filter { value.isTrainingDay(on: $0) }
        XCTAssertEqual(trainingDates.count, 27)
        XCTAssertEqual(trainingDates.first, date(10, 18, hour: 0))
        XCTAssertEqual(trainingDates.last, date(12, 10, hour: 0))
    }

    func testBlockStartDoesNotResetTheIndependentShiftAnchor() {
        let value = TrainingCalendarPlan(startDate: date(10, 20), cycleAnchorDate: date(10, 17), timeZone: timeZone)
        let entries = value.entries(program: program(), history: [], now: date(10, 19))
        XCTAssertEqual(entries[0].cycleDay, 4)
        XCTAssertEqual(entries[0].shift, .afternoon)
        XCTAssertFalse(entries[0].isTraining)
        XCTAssertEqual(entries[1].cycleDay, 5)
        XCTAssertEqual(entries[1].shift, .night)
        XCTAssertEqual(entries[1].session?.id, "upper-a")
    }

    func testSessionRotationContinuesAcrossCycleAndWeekBoundariesWithoutChangingTargets() {
        let savedProgram = program()
        let entries = plan().entries(program: savedProgram, history: [], now: date(10, 16))
        let projected = entries.compactMap(\.session)
        XCTAssertEqual(projected.count, 27)
        for (index, session) in projected.enumerated() {
            XCTAssertEqual(session, savedProgram.sessions[index % 4])
        }
        XCTAssertEqual(projected[4].id, "upper-a")
        XCTAssertEqual(projected[5].id, "lower-a")
        XCTAssertEqual(projected.filter { $0.id.hasPrefix("upper") }.count, 14)
        XCTAssertEqual(projected.filter { $0.id.hasPrefix("lower") }.count, 13)
        XCTAssertTrue(entries.allSatisfy { $0.workouts.isEmpty })
    }

    func testMissedSlotsDoNotAdvanceNextSessionOrCreateCatchup() throws {
        let savedProgram = program()
        let history = [completed(on: date(10, 18, hour: 9))]
        let entries = plan().entries(program: savedProgram, history: history, now: date(11, 1))
        XCTAssertTrue(entries.filter { $0.date < date(11, 1, hour: 0) }.allSatisfy { $0.session == nil })
        let next = try XCTUnwrap(entries.first { $0.session != nil })
        XCTAssertEqual(next.date, date(11, 3, hour: 0))
        XCTAssertEqual(next.session?.id, "lower-a")
        XCTAssertEqual(entries.flatMap(\.workouts), history)
        XCTAssertEqual(savedProgram.nextSession(history: history, now: date(11, 1))?.id, "lower-a")
    }

    func testCompletedTodayAppearsOnceAndFutureStartsAfterItsSession() throws {
        let workout = completed(on: date(10, 21, hour: 9))
        let entries = plan().entries(program: program(), history: [workout], now: date(10, 21))
        let today = entries[4]
        XCTAssertEqual(today.workouts, [workout])
        XCTAssertTrue(today.isTraining)
        XCTAssertNil(today.session)
        XCTAssertEqual(entries[7].session?.id, "lower-a")
        XCTAssertEqual(entries.flatMap(\.workouts).count, 1)
    }

    func testActiveTodaySuppressesDuplicateButDoesNotPretendToCompleteSession() {
        var workout = completed(on: date(10, 21, hour: 9))
        workout.end = nil
        let savedProgram = program()
        let entries = plan().entries(program: savedProgram, history: [workout], now: date(10, 21))
        XCTAssertEqual(entries[4].workouts, [workout])
        XCTAssertNil(entries[4].session)
        XCTAssertEqual(entries[7].session?.id, "upper-a")
        XCTAssertEqual(savedProgram.nextSession(history: [workout], now: date(10, 21))?.id, "upper-a")
    }

    func testActualWorkoutsAreShownOnRestDaysAndUnlinkedWorkoutsDoNotAdvanceProgram() {
        var workout = completed(on: date(10, 17, hour: 9))
        workout.programID = nil
        workout.programSessionID = nil
        workout.programRevision = nil
        let entries = plan().entries(program: program(), history: [workout], now: date(10, 17))
        XCTAssertFalse(entries[0].isTraining)
        XCTAssertEqual(entries[0].workouts, [workout])
        XCTAssertEqual(entries[1].session?.id, "upper-a")
    }

    func testNoProgramAndExpiredBlockNeverInventSessions() {
        let workout = completed(on: date(10, 18, hour: 9))
        let withoutProgram = plan().entries(program: nil, history: [workout], now: date(10, 19))
        XCTAssertEqual(withoutProgram.count, 56)
        XCTAssertTrue(withoutProgram.allSatisfy { $0.session == nil })
        XCTAssertEqual(withoutProgram.flatMap(\.workouts), [workout])
        let expired = plan().entries(program: program(), history: [workout], now: date(12, 12))
        XCTAssertEqual(expired.count, 56)
        XCTAssertTrue(expired.allSatisfy { $0.session == nil })
        XCTAssertEqual(expired.flatMap(\.workouts), [workout])
        var empty = program()
        empty.sessions = []
        XCTAssertTrue(plan().entries(program: empty, history: [], now: date(10, 16)).allSatisfy { $0.session == nil })
    }

    func testMovePreservesCountAndRotationAndReturningToDefaultsRemovesOverrides() throws {
        var value = plan()
        try value.moveTrainingDay(from: date(10, 18), to: date(10, 19), now: date(10, 17))
        XCTAssertFalse(value.isTrainingDay(on: date(10, 18)))
        XCTAssertTrue(value.isTrainingDay(on: date(10, 19)))
        XCTAssertEqual(value.dayOverrides, [.init(dayOffset: 1, isTraining: false), .init(dayOffset: 2, isTraining: true)])
        let entries = value.entries(program: program(), history: [], now: date(10, 17))
        XCTAssertNil(entries[1].session)
        XCTAssertEqual(entries[2].session?.id, "upper-a")
        XCTAssertEqual(entries[4].session?.id, "lower-a")
        XCTAssertEqual(entries.filter(\.isTraining).count, 27)
        try value.moveTrainingDay(from: date(10, 19), to: date(10, 18), now: date(10, 17))
        XCTAssertTrue(value.dayOverrides.isEmpty)
        XCTAssertEqual(value, plan())
    }

    func testRejectedMovesAndPastEditsAreAtomic() throws {
        var value = plan()
        let original = value
        XCTAssertThrowsError(try value.moveTrainingDay(from: date(10, 18), to: date(10, 21), now: date(10, 17)))
        XCTAssertEqual(value, original)
        XCTAssertThrowsError(try value.moveTrainingDay(from: date(10, 18), to: date(10, 18), now: date(10, 17)))
        XCTAssertEqual(value, original)
        XCTAssertThrowsError(try value.moveTrainingDay(from: date(10, 17), to: date(10, 19), now: date(10, 17)))
        XCTAssertEqual(value, original)
        XCTAssertThrowsError(try value.moveTrainingDay(from: date(10, 18), to: date(12, 12), now: date(10, 17)))
        XCTAssertEqual(value, original)
        XCTAssertThrowsError(try value.moveTrainingDay(from: date(10, 18), to: date(10, 19), now: date(10, 19)))
        XCTAssertEqual(value, original)
        XCTAssertThrowsError(try value.setTrainingDay(on: date(10, 18), isTraining: false, now: date(10, 19)))
        XCTAssertEqual(value, original)
        XCTAssertThrowsError(try value.setTrainingDay(on: date(12, 12), isTraining: true, now: date(10, 17)))
        XCTAssertEqual(value, original)
        try value.setTrainingDay(on: date(10, 17, hour: 0), isTraining: true, now: date(10, 17, hour: 23))
        XCTAssertTrue(value.isTrainingDay(on: date(10, 17)))
    }

    func testOverridesNormalizeAndSurviveCodableWithSavedTimezone() throws {
        var value = plan()
        try value.setTrainingDay(on: date(10, 18), isTraining: false, now: date(10, 17))
        try value.setTrainingDay(on: date(10, 18), isTraining: false, now: date(10, 17))
        XCTAssertEqual(value.dayOverrides.count, 1)
        try value.setTrainingDay(on: date(10, 18), isTraining: true, now: date(10, 17))
        XCTAssertTrue(value.dayOverrides.isEmpty)
        try value.moveTrainingDay(from: date(10, 25), to: date(10, 23), now: date(10, 17))
        let restored = try JSONDecoder().decode(TrainingCalendarPlan.self, from: JSONEncoder().encode(value))
        try restored.validate()
        XCTAssertEqual(restored, value)
        XCTAssertEqual(restored.calendar.timeZone.identifier, "Europe/Amsterdam")
        XCTAssertEqual(restored.dates, value.dates)
        XCTAssertEqual(restored.entries(program: program(), history: [], now: date(10, 17)), value.entries(program: program(), history: [], now: date(10, 17)))
        XCTAssertTrue(restored.prefersUpperLower)
        var otherPreference = value
        otherPreference.prefersUpperLower = false
        let restoredPreference = try JSONDecoder().decode(TrainingCalendarPlan.self, from: JSONEncoder().encode(otherPreference))
        XCTAssertFalse(restoredPreference.prefersUpperLower)
    }

    func testMalformedCalendarValuesAreRejectedAndSafeToInspect() throws {
        let valid = plan()
        var invalid = valid
        invalid.trainingCycleDays = []
        XCTAssertThrowsError(try invalid.validate())
        XCTAssertTrue(invalid.entries(program: program(), history: [], now: date(10, 17)).isEmpty)
        invalid = valid; invalid.trainingCycleDays = [2, 2]
        XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.trainingCycleDays = [0, 11]
        XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.timeZoneIdentifier = "Not/A_Real_Zone"
        XCTAssertThrowsError(try invalid.validate())
        XCTAssertTrue(invalid.dates.isEmpty)
        XCTAssertNil(invalid.dayOffset(for: date(10, 17)))
        XCTAssertTrue(invalid.reviewDate.timeIntervalSince1970.isFinite)
        invalid = valid; invalid.dayOverrides = [.init(dayOffset: 1, isTraining: true), .init(dayOffset: 1, isTraining: false)]
        XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.dayOverrides = [.init(dayOffset: 56, isTraining: true)]
        XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.startDate = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try invalid.validate())
        XCTAssertTrue(invalid.dates.isEmpty)
        XCTAssertTrue(invalid.lastDate.timeIntervalSince1970.isFinite)
        XCTAssertTrue(invalid.reviewDate.timeIntervalSince1970.isFinite)
        invalid = valid; invalid.cycleAnchorDate = Date(timeIntervalSince1970: .nan)
        XCTAssertThrowsError(try invalid.validate())
        XCTAssertEqual(invalid.cycleDay(on: date(10, 17)), 1)
        invalid = valid; invalid.startDate = date(12, 31, year: 2099)
        XCTAssertThrowsError(try invalid.validate())
    }
}
