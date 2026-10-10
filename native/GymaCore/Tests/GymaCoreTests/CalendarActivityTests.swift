import XCTest
@testable import GymaCore

final class CalendarActivityTests: XCTestCase {
    private var timeZone: TimeZone { TimeZone(identifier: "Europe/Amsterdam")! }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }
    private func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private func plan() -> TrainingCalendarPlan {
        .defaultPlan(now: date(10, 10), timeZone: timeZone)
    }

    func testFreshDefaultStartsOnFirstOffDayWithoutMovingFirstMorning() throws {
        let value = plan()
        try value.validate()
        XCTAssertEqual(value.startDate, date(10, 13, hour: 0))
        XCTAssertEqual(value.cycleAnchorDate, date(10, 17, hour: 0))
        XCTAssertEqual(value.trainingCycleDays, [2, 5, 8, 9, 10])
        XCTAssertEqual((13...16).map { value.cycleDay(on: date(10, $0)) }, [7, 8, 9, 10])
        XCTAssertEqual((13...16).map { value.shift(on: date(10, $0)) }, [.off, .off, .off, .off])
        XCTAssertEqual((13...16).filter { value.isTrainingDay(on: date(10, $0)) }, [13, 14, 16])
        XCTAssertEqual(value.cycleDay(on: date(10, 17)), 1)
        XCTAssertEqual(value.shift(on: date(10, 17)), .morning)
        XCTAssertFalse(value.isTrainingDay(on: date(10, 17)))
        XCTAssertTrue(value.isTrainingDay(on: date(10, 18)))
        XCTAssertTrue(value.activities.isEmpty)
        XCTAssertEqual(value.lastDate, date(12, 7, hour: 0))
        XCTAssertEqual(value.reviewDate, date(12, 8, hour: 0))
    }

    func testDefaultIsDeterministicAndDoesNotBackdateNewSetups() throws {
        XCTAssertEqual(plan(), plan())
        let later = TrainingCalendarPlan.defaultPlan(now: date(10, 20), timeZone: timeZone)
        try later.validate()
        XCTAssertEqual(later.startDate, date(10, 20, hour: 0))
        XCTAssertEqual(later.cycleDay(on: later.startDate), 4)
        XCTAssertEqual(later.cycleAnchorDate, date(10, 17, hour: 0))
        XCTAssertTrue(later.dayOverrides.isEmpty)
        let openingInProgress = TrainingCalendarPlan.defaultPlan(now: date(10, 14), timeZone: timeZone)
        XCTAssertEqual(openingInProgress.dayOverrides, [.init(dayOffset: 1, isTraining: false)])
        XCTAssertFalse(openingInProgress.isTrainingDay(on: date(10, 15)))
    }

    func testFreshDefaultAndActivitiesUseSavedCivilDatesAcrossDST() throws {
        var value = plan()
        try value.setActivity(on: date(10, 25, hour: 23), kind: .stretching, isPlanned: true, now: date(10, 13))
        XCTAssertEqual(value.activities.first?.dayOffset, 12)
        XCTAssertEqual(value.activities(on: date(10, 25, hour: 1)).first?.kind, .stretching)
        XCTAssertTrue(value.activities(on: date(10, 26)).isEmpty)
        XCTAssertEqual(value.date(at: 13)!.timeIntervalSince(value.date(at: 12)!), 25 * 3600)
        XCTAssertEqual(value.dates.count, 56)
        XCTAssertEqual(Set(value.dates).count, 56)
        for (offset, day) in value.dates.enumerated() {
            XCTAssertEqual(value.dayOffset(for: day), offset)
            XCTAssertEqual(value.calendar.component(.hour, from: day), 0)
        }
        let restored = try JSONDecoder().decode(TrainingCalendarPlan.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored, value)
        XCTAssertEqual(restored.calendar.timeZone, timeZone)
    }

    func testLegacyCalendarDecodesWithoutChangingSavedStartPatternOrOverrides() throws {
        var saved = TrainingCalendarPlan(startDate: date(10, 17), cycleAnchorDate: date(10, 17),
                                         trainingCycleDays: [2, 5, 9], timeZone: timeZone, prefersUpperLower: false)
        try saved.setTrainingDay(on: date(10, 20), isTraining: true, now: date(10, 10))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        legacy.removeValue(forKey: "activities")
        let restored = try JSONDecoder().decode(TrainingCalendarPlan.self, from: JSONSerialization.data(withJSONObject: legacy))
        try restored.validate()
        XCTAssertEqual(restored, saved)
        XCTAssertTrue(restored.activities.isEmpty)
        XCTAssertEqual(restored.startDate, date(10, 17, hour: 0))
        XCTAssertNotEqual(restored.startDate, plan().startDate)
    }

    func testOptionalActivitiesDoNotCreateStrengthSlotsOrAdvanceProjectedSessions() throws {
        let program = TrainingProgram(id: "program", title: "Strength", goal: "Strength", sessions: [
            .init(id: "a", title: "Upper", exercises: [.init(exerciseID: "bench_press", target: .init(sets: 2, repsMin: 6, repsMax: 8))]),
            .init(id: "b", title: "Lower", exercises: [.init(exerciseID: "squat", target: .init(sets: 2, repsMin: 6, repsMax: 8))])
        ], createdAt: date(10, 1), updatedAt: date(10, 1))
        var value = plan()
        let before = value.entries(program: program, history: [], now: date(10, 13))
        try value.setActivity(on: date(10, 13), kind: .abs, isPlanned: true, now: date(10, 13))
        try value.setActivityCompleted(on: date(10, 13), kind: .abs, isCompleted: true, now: date(10, 13))
        try value.setActivity(on: date(10, 15), kind: .inclineWalking, isPlanned: true, now: date(10, 13))
        try value.setActivity(on: date(10, 15), kind: .stretching, isPlanned: true, now: date(10, 13))
        let after = value.entries(program: program, history: [], now: date(10, 13))
        XCTAssertEqual(after.map(\.isTraining), before.map(\.isTraining))
        XCTAssertEqual(after.compactMap(\.session), before.compactMap(\.session))
        XCTAssertTrue(after.flatMap(\.workouts).isEmpty)
        XCTAssertEqual(after[0].activities.first?.isCompleted, true)
        XCTAssertEqual(after[2].activities.count, 2)
        XCTAssertFalse(after[2].isTraining)
        XCTAssertNil(after[2].session)
        XCTAssertEqual(program.nextSession(history: [], now: date(10, 13))?.id, "a")
    }

    func testActivityEditsAreUniqueBoundedAndAtomic() throws {
        var value = plan()
        try value.setActivity(on: date(10, 15), kind: .inclineWalking, isPlanned: true, now: date(10, 13))
        try value.setActivity(on: date(10, 15), kind: .inclineWalking, isPlanned: true, durationMinutes: 30, now: date(10, 13))
        XCTAssertEqual(value.activities.count, 1)
        XCTAssertEqual(value.activities.first?.durationMinutes, 30)
        let original = value
        for minutes in [0, 4, 121, Int.max] {
            XCTAssertThrowsError(try value.setActivity(on: date(10, 15), kind: .inclineWalking, isPlanned: true,
                                                      durationMinutes: minutes, now: date(10, 13)))
            XCTAssertEqual(value, original)
        }
        for invalidDate in [date(10, 12), date(12, 8), Date(timeIntervalSince1970: .infinity)] {
            XCTAssertThrowsError(try value.setActivity(on: invalidDate, kind: .stretching, isPlanned: true, now: date(10, 13)))
            XCTAssertEqual(value, original)
        }
        XCTAssertThrowsError(try value.setActivity(on: date(10, 15), kind: .stretching, isPlanned: true, now: date(10, 16)))
        XCTAssertEqual(value, original)
        try value.setActivity(on: date(10, 15), kind: .inclineWalking, isPlanned: false, now: date(10, 13))
        XCTAssertTrue(value.activities.isEmpty)
    }

    func testAbsCannotBeScheduledOnConsecutiveCivilDaysIncludingDST() throws {
        var value = plan()
        try value.setActivity(on: date(10, 25), kind: .abs, isPlanned: true, now: date(10, 13))
        let original = value
        for neighbor in [24, 26] {
            XCTAssertThrowsError(try value.setActivity(on: date(10, neighbor), kind: .abs, isPlanned: true, now: date(10, 13)))
            XCTAssertEqual(value, original)
        }
        try value.setActivity(on: date(10, 27), kind: .abs, isPlanned: true, now: date(10, 13))
        try value.setActivityCompleted(on: date(10, 25), kind: .abs, isCompleted: true, now: date(10, 25))
        let completed = value
        XCTAssertThrowsError(try value.setActivity(on: date(10, 26), kind: .abs, isPlanned: true, now: date(10, 25)))
        XCTAssertEqual(value, completed)
        // Gentle recovery options remain available on neighboring dates.
        try value.setActivity(on: date(10, 26), kind: .stretching, isPlanned: true, now: date(10, 25))
        try value.setActivity(on: date(10, 26), kind: .inclineWalking, isPlanned: true, now: date(10, 25))
    }

    func testCompletionIsTodayOnlyAndMustBeUndoneBeforeEditing() throws {
        var value = plan()
        try value.setActivity(on: date(10, 15), kind: .stretching, isPlanned: true, now: date(10, 13))
        let scheduled = value
        XCTAssertThrowsError(try value.setActivityCompleted(on: date(10, 15), kind: .stretching, isCompleted: true, now: date(10, 13)))
        XCTAssertEqual(value, scheduled)
        XCTAssertThrowsError(try value.setActivityCompleted(on: date(10, 13), kind: .abs, isCompleted: true, now: date(10, 13)))
        XCTAssertEqual(value, scheduled)
        try value.setActivityCompleted(on: date(10, 15), kind: .stretching, isCompleted: true, now: date(10, 15))
        let completed = value
        XCTAssertThrowsError(try value.setActivity(on: date(10, 15), kind: .stretching, isPlanned: false, now: date(10, 15)))
        XCTAssertThrowsError(try value.setActivity(on: date(10, 15), kind: .stretching, isPlanned: true, durationMinutes: 15, now: date(10, 15)))
        XCTAssertEqual(value, completed)
        XCTAssertThrowsError(try value.setActivityCompleted(on: date(10, 15), kind: .stretching, isCompleted: false, now: date(10, 16)))
        XCTAssertEqual(value, completed)
        try value.setActivityCompleted(on: date(10, 15), kind: .stretching, isCompleted: false, now: date(10, 15))
        XCTAssertEqual(value, scheduled)
        try value.setActivity(on: date(10, 15), kind: .stretching, isPlanned: true, durationMinutes: 15, now: date(10, 15))
        XCTAssertEqual(value.activities.first?.durationMinutes, 15)
    }

    func testReconfigurationKeepsIndividualDatesAndRejectsSilentLossOrCompletedStartChange() throws {
        var value = TrainingCalendarPlan(startDate: date(10, 17), cycleAnchorDate: date(10, 17), timeZone: timeZone)
        try value.setTrainingDay(on: date(10, 19), isTraining: true, now: date(10, 10))
        try value.setActivity(on: date(10, 20), kind: .inclineWalking, isPlanned: true, now: date(10, 10))
        let moved = try value.reconfigured(startDate: date(10, 13), cycleAnchorDate: date(10, 17),
                                          trainingCycleDays: value.trainingCycleDays, prefersUpperLower: false)
        XCTAssertTrue(moved.isTrainingDay(on: date(10, 19)))
        XCTAssertEqual(moved.dayOverrides, [.init(dayOffset: 6, isTraining: true)])
        XCTAssertEqual(moved.activities.first?.dayOffset, 7)
        XCTAssertEqual(moved.activities(on: date(10, 20)).first?.durationMinutes, 20)
        XCTAssertFalse(moved.prefersUpperLower)
        XCTAssertThrowsError(try value.reconfigured(startDate: date(10, 21), cycleAnchorDate: date(10, 17),
                                                    trainingCycleDays: value.trainingCycleDays, prefersUpperLower: true))
        try value.setActivityCompleted(on: date(10, 20), kind: .inclineWalking, isCompleted: true, now: date(10, 20))
        XCTAssertThrowsError(try value.reconfigured(startDate: date(10, 13), cycleAnchorDate: date(10, 17),
                                                    trainingCycleDays: value.trainingCycleDays, prefersUpperLower: true))
        let same = try value.reconfigured(startDate: value.startDate, cycleAnchorDate: value.cycleAnchorDate,
                                         trainingCycleDays: value.trainingCycleDays, prefersUpperLower: true)
        XCTAssertEqual(same, value)
    }

    func testMalformedActivitiesCannotBeValidatedOrProjected() throws {
        let invalidActivities: [[CalendarActivity]] = [
            [.init(dayOffset: -1, kind: .stretching)],
            [.init(dayOffset: 56, kind: .inclineWalking)],
            [.init(dayOffset: 0, kind: .abs, durationMinutes: 31)],
            [.init(dayOffset: 0, kind: .stretching), .init(dayOffset: 0, kind: .stretching)],
            [.init(dayOffset: 0, kind: .abs), .init(dayOffset: 1, kind: .abs)]
        ]
        for activities in invalidActivities {
            var value = plan()
            value.activities = activities
            XCTAssertThrowsError(try value.validate())
            XCTAssertTrue(value.entries(program: nil, history: [], now: date(10, 13)).isEmpty)
        }
    }

    func testLaterNonoverlappingBlockStartsFreshEvenAfterOptionalCompletions() throws {
        var value = plan()
        try value.setActivity(on: date(10, 13), kind: .inclineWalking, isPlanned: true, now: date(10, 13))
        try value.setActivityCompleted(on: date(10, 13), kind: .inclineWalking, isCompleted: true, now: date(10, 13))
        let next = try value.reconfigured(startDate: value.reviewDate, cycleAnchorDate: value.cycleAnchorDate,
                                         trainingCycleDays: value.trainingCycleDays, prefersUpperLower: value.prefersUpperLower)
        try next.validate()
        XCTAssertEqual(next.startDate, value.reviewDate)
        XCTAssertEqual(next.cycleAnchorDate, value.cycleAnchorDate)
        XCTAssertTrue(next.activities.isEmpty)
        XCTAssertTrue(next.dayOverrides.isEmpty)
        XCTAssertEqual(value.activities.first?.isCompleted, true)
    }
}
