import XCTest
@testable import GymaCore

final class CalendarActivityIntegrationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return value
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func configuredState() throws -> GymaState {
        var state = GymaState()
        let target = ExerciseTarget(sets: 2, repsMin: 8, repsMax: 12, loadKg: 20)
        state.trainingProgram = .init(id: "activity-program", title: "Upper / lower", goal: "Consistent training", sessions: [
            .init(id: "upper", title: "Upper", exercises: [.init(exerciseID: "bench_press", target: target)]),
            .init(id: "lower", title: "Lower", exercises: [.init(exerciseID: "squat", target: target)])
        ], createdAt: date(10), updatedAt: date(10))
        try state.saveTrainingCalendar(.defaultPlan(now: date(10), timeZone: calendar.timeZone), now: date(10))
        return state
    }

    func testOptionalCompletionDoesNotConsumeStrengthSessionOrWatchStart() throws {
        var state = try configuredState()
        XCTAssertNil(state.readyProgramPlan(now: date(12), calendar: calendar))
        let before = try XCTUnwrap(state.readyProgramPlan(now: date(13), calendar: calendar))
        XCTAssertEqual(before.programSessionID, "upper")
        try state.setCalendarActivity(on: date(13), kind: .inclineWalking, isPlanned: true, durationMinutes: 20, now: date(13))
        try state.setCalendarActivityCompleted(on: date(13), kind: .inclineWalking, isCompleted: true, now: date(13))
        let after = try XCTUnwrap(state.readyProgramPlan(now: date(13), calendar: calendar))
        XCTAssertEqual(after.programSessionID, before.programSessionID)
        XCTAssertTrue(state.workouts.isEmpty)
        XCTAssertEqual(state.trainingProgram?.nextSession(history: state.workouts, now: date(13))?.id, "upper")
        let plan = try XCTUnwrap(state.trainingCalendar)
        let entries = plan.entries(program: state.trainingProgram, history: state.workouts, now: date(13))
        XCTAssertEqual(entries[0].session?.id, "upper")
        XCTAssertEqual(entries[1].session?.id, "lower")
        XCTAssertTrue(entries[0].activities.first?.isCompleted == true)
        XCTAssertTrue(entries[0].workouts.isEmpty)
        XCTAssertNil(state.readyProgramPlan(now: date(15), calendar: calendar))
        let snapshot = CompanionSnapshot(state: state, now: date(13), calendar: calendar)
        XCTAssertEqual(snapshot.readyPlan?.programSessionID, "upper")
        let wire = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(wire.contains("inclineWalking"))
        XCTAssertFalse(wire.contains("trainingCalendarHistory"))
        try state.validate()
    }

    func testActivityBackupRoundTripAndLegacyCalendarDecode() throws {
        var state = try configuredState()
        try state.setCalendarActivity(on: date(13), kind: .stretching, isPlanned: true, durationMinutes: 10, now: date(13))
        try state.setCalendarActivityCompleted(on: date(13), kind: .stretching, isCompleted: true, now: date(13))
        try state.setCalendarActivity(on: date(15), kind: .inclineWalking, isPlanned: true, durationMinutes: 25, now: date(13))
        let data = try NativeBackup.encode(state)
        XCTAssertEqual(try NativeBackup.decode(data), state)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var savedCalendar = try XCTUnwrap(legacy["trainingCalendar"] as? [String: Any])
        savedCalendar.removeValue(forKey: "activities")
        legacy["trainingCalendar"] = savedCalendar
        let restored = try NativeBackup.decode(JSONSerialization.data(withJSONObject: legacy))
        var expected = state
        expected.trainingCalendar?.activities = []
        XCTAssertEqual(restored, expected)
    }

    func testFutureCompletionAndPastActivityEditsRejectAtomically() throws {
        var state = try configuredState()
        try state.setCalendarActivity(on: date(15), kind: .stretching, isPlanned: true, durationMinutes: 10, now: date(13))
        let before = state
        XCTAssertThrowsError(try state.setCalendarActivityCompleted(on: date(15), kind: .stretching, isCompleted: true, now: date(13)))
        XCTAssertEqual(state, before)
        XCTAssertThrowsError(try state.setCalendarActivity(on: date(15), kind: .stretching, isPlanned: false, now: date(16)))
        XCTAssertEqual(state, before)
    }

    func testOptionalActivityCanBeRecordedAfterStrengthWithoutChangingWorkout() throws {
        var state = try configuredState()
        let workout = Workout(id: "strength", start: date(13, hour: 9), end: date(13, hour: 10), exercises: [
            .init(exerciseID: "bench_press", sets: [.init(kg: 20, reps: 10, effort: .easy, isWarmup: false)])
        ], programID: "activity-program", programSessionID: "upper", programRevision: 1)
        state.workouts = [workout]
        try state.setCalendarActivity(on: date(13), kind: .stretching, isPlanned: true, durationMinutes: 10, now: date(13))
        try state.setCalendarActivityCompleted(on: date(13), kind: .stretching, isCompleted: true, now: date(13))
        XCTAssertEqual(state.workouts, [workout])
        XCTAssertEqual(state.trainingProgram?.nextSession(history: state.workouts, now: date(13))?.id, "lower")
        XCTAssertNil(state.readyProgramPlan(now: date(13), calendar: calendar))
        XCTAssertEqual(state.readyProgramPlan(now: date(14), calendar: calendar)?.programSessionID, "lower")
        try state.validate()
    }

    func testActivityChangeInvalidatesDraftButPreservesConversationAndProgram() throws {
        var state = try configuredState()
        state.coachConversation = .init(messages: [.init(role: .user, content: "Keep my program and add an easy walk.")])
        state.coachConversation?.proposedProgram = state.trainingProgram
        let before = state
        try state.setCalendarActivity(on: date(15), kind: .inclineWalking, isPlanned: true, durationMinutes: 20, now: date(13))
        XCTAssertEqual(state.revision, before.revision + 1)
        XCTAssertNil(state.coachConversation?.proposedProgram)
        XCTAssertEqual(state.coachConversation?.messages, before.coachConversation?.messages)
        XCTAssertEqual(state.trainingProgram, before.trainingProgram)
        XCTAssertEqual(state.workouts, before.workouts)
        let unchanged = state
        try state.setCalendarActivity(on: date(15), kind: .inclineWalking, isPlanned: true, durationMinutes: 20, now: date(13))
        XCTAssertEqual(state, unchanged)
    }

    func testNextBlockArchivesCompletedActivitiesAndBackupPreservesBothBlocks() throws {
        var state = try configuredState()
        try state.setCalendarActivity(on: date(13), kind: .inclineWalking, isPlanned: true, durationMinutes: 20, now: date(13))
        try state.setCalendarActivityCompleted(on: date(13), kind: .inclineWalking, isCompleted: true, now: date(13))
        let previous = try XCTUnwrap(state.trainingCalendar)
        let next = try previous.reconfigured(startDate: previous.reviewDate, cycleAnchorDate: previous.cycleAnchorDate,
                                             trainingCycleDays: previous.trainingCycleDays, prefersUpperLower: previous.prefersUpperLower)
        XCTAssertTrue(next.activities.isEmpty)
        XCTAssertTrue(next.dayOverrides.isEmpty)
        try state.saveTrainingCalendar(next, now: next.startDate)
        XCTAssertEqual(state.trainingCalendar, next)
        XCTAssertEqual(state.trainingCalendarHistory, [previous])
        XCTAssertTrue(state.workouts.isEmpty)
        XCTAssertEqual(try NativeBackup.decode(NativeBackup.encode(state)), state)
        let saved = state
        try state.saveTrainingCalendar(next, now: next.startDate)
        XCTAssertEqual(state, saved, "Saving the same block must not archive it twice")
    }

    func testCompletedAbsAtPreviousBlockBoundaryStillRequireRecovery() throws {
        var state = try configuredState()
        let original = try XCTUnwrap(state.trainingCalendar)
        let lastDay = original.lastDate
        try state.setCalendarActivity(on: lastDay, kind: .abs, isPlanned: true, durationMinutes: 10, now: lastDay)
        try state.setCalendarActivityCompleted(on: lastDay, kind: .abs, isCompleted: true, now: lastDay)
        let previous = try XCTUnwrap(state.trainingCalendar)
        let next = try previous.reconfigured(startDate: previous.reviewDate, cycleAnchorDate: previous.cycleAnchorDate,
                                             trainingCycleDays: previous.trainingCycleDays, prefersUpperLower: previous.prefersUpperLower)
        try state.saveTrainingCalendar(next, now: next.startDate)
        let saved = state
        XCTAssertThrowsError(try state.setCalendarActivity(on: next.startDate, kind: .abs, isPlanned: true, now: next.startDate))
        XCTAssertEqual(state, saved)
        let restedDay = try XCTUnwrap(next.date(at: 1))
        try state.setCalendarActivity(on: restedDay, kind: .abs, isPlanned: true, now: next.startDate)
        try state.validate()
    }
}
