import XCTest
@testable import GymaCore

final class CalendarWorkoutEditingTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return value
    }
    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }
    private var target: ExerciseTarget { .init(sets: 3, repsMin: 8, repsMax: 12, loadKg: 25) }
    private var changed: [WorkoutExercise] {
        [.init(exerciseID: "squat", target: target), .init(exerciseID: "bench_press", target: target)]
    }
    private func state() throws -> GymaState {
        var state = GymaState()
        state.trainingProgram = .init(id: "program", title: "Training", goal: "Consistency", sessions: [
            .init(id: "upper", title: "Upper", exercises: [.init(exerciseID: "bench_press", target: target)]),
            .init(id: "lower", title: "Lower", exercises: [.init(exerciseID: "squat", target: target)])
        ], createdAt: date(10), updatedAt: date(10))
        try state.saveTrainingCalendar(.defaultPlan(now: date(10), timeZone: calendar.timeZone), now: date(10))
        return state
    }

    func testOneDateChangesPreviewPhonePreparationAndWatchStartWithoutChangingProgram() throws {
        var state = try state()
        let program = state.trainingProgram
        try state.setCalendarWorkout(on: date(13), exercises: changed, now: date(13))
        let calendarPlan = try XCTUnwrap(state.trainingCalendar)
        let days = calendarPlan.entries(program: state.trainingProgram, history: [], now: date(13))
        XCTAssertEqual(days[0].session?.exercises, changed)
        XCTAssertEqual(days[1].session?.exercises, program?.sessions[1].exercises)
        let prepared = try state.nextProgramPlan(checkIn: .init(shift: .off, energy: .good, timeMinutes: 90), now: date(13))
        XCTAssertEqual(prepared.exercises, changed)
        XCTAssertEqual(prepared.programSessionID, "upper")
        let ready = try XCTUnwrap(state.readyProgramPlan(now: date(13), calendar: calendar))
        XCTAssertEqual(ready.exerciseCount, 2)
        let command = WatchCommand(storeID: state.storeID, workoutID: ready.id, basedOnRevision: state.revision,
                                   createdAt: date(13), action: .startAcceptedPlan(planID: ready.id,
                                       readiness: .init(energy: .good, soreness: Soreness.allNone, recordedAt: date(13))))
        XCTAssertEqual(GymaReducer.apply(command, to: &state, now: date(13), calendar: calendar).status, .applied)
        XCTAssertEqual(state.activeWorkout?.exercises, changed)
        XCTAssertEqual(state.trainingProgram, program)
        try state.validate()
    }

    func testOverridesSurviveBackupMoveAndSetupAndCanBeReset() throws {
        var state = try state()
        try state.setCalendarWorkout(on: date(14), exercises: changed, now: date(13))
        XCTAssertEqual(try NativeBackup.decode(NativeBackup.encode(state)), state)
        try state.moveCalendarTrainingDay(from: date(14), to: date(15), now: date(13))
        XCTAssertNil(state.trainingCalendar?.workoutOverride(on: date(14)))
        XCTAssertEqual(state.trainingCalendar?.workoutOverride(on: date(15))?.exercises, changed)
        let plan = try XCTUnwrap(state.trainingCalendar)
        let setup = try plan.reconfigured(startDate: plan.startDate, cycleAnchorDate: plan.cycleAnchorDate,
                                          trainingCycleDays: plan.trainingCycleDays, prefersUpperLower: false)
        try state.saveTrainingCalendar(setup, now: date(13))
        XCTAssertEqual(state.trainingCalendar?.workoutOverride(on: date(15))?.exercises, changed)
        try state.setCalendarWorkout(on: date(15), exercises: nil, now: date(13))
        XCTAssertNil(state.trainingCalendar?.workoutOverride(on: date(15)))
    }

    func testInvalidOrRecordedDayEditsAreAtomic() throws {
        var state = try state()
        let before = state
        XCTAssertThrowsError(try state.setCalendarWorkout(on: date(15), exercises: changed, now: date(13)))
        XCTAssertThrowsError(try state.setCalendarWorkout(on: date(13), exercises: [], now: date(13)))
        XCTAssertThrowsError(try state.setCalendarWorkout(on: date(13), exercises: changed + changed, now: date(13)))
        XCTAssertThrowsError(try state.setCalendarWorkout(on: date(13), exercises: changed, now: date(14)))
        var logged = changed
        logged[0].sets = [.init(kg: 25, reps: 8, isWarmup: false)]
        XCTAssertThrowsError(try state.setCalendarWorkout(on: date(13), exercises: logged, now: date(13)))
        XCTAssertEqual(state, before)
        state.workouts = [.init(start: date(13), end: date(13).addingTimeInterval(30), exercises: logged)]
        let recorded = state
        XCTAssertThrowsError(try state.setCalendarWorkout(on: date(13), exercises: changed, now: date(13)))
        XCTAssertEqual(state, recorded)
    }

    func testLegacyCalendarAndInvalidBackupOverride() throws {
        let state = try state()
        let backup = try NativeBackup.encode(state)
        let decoded = try NativeBackup.decode(backup)
        XCTAssertNil(decoded.trainingCalendar?.workoutOverrides)
        var invalid = state
        invalid.trainingCalendar?.workoutOverrides = [.init(dayOffset: 0, exercises: [.init(exerciseID: "missing", target: target)])]
        XCTAssertThrowsError(try invalid.validate())
        invalid.trainingCalendar?.workoutOverrides = [.init(dayOffset: 56, exercises: changed)]
        XCTAssertThrowsError(try invalid.validate())
    }

    func testCoachDateEditsPreviewApplyAndRejectStaleProposals() throws {
        var state = try state()
        let proposal = try CoachAppChangeProposal(changes: [.init(kind: .setCalendarWorkout, date: date(14), exercises: changed)], state: state, now: date(13))
        XCTAssertTrue(proposal.summaries[0].contains("2026-10-14"))
        XCTAssertNil(state.trainingCalendar?.workoutOverride(on: date(14)))
        let program = state.trainingProgram
        try state.applyCoachAppChanges(proposal, now: date(13))
        XCTAssertEqual(state.trainingCalendar?.workoutOverride(on: date(14))?.exercises, changed)
        XCTAssertEqual(state.trainingProgram, program)
        XCTAssertThrowsError(try state.applyCoachAppChanges(proposal, now: date(13)))
        let reset = try CoachAppChangeProposal(changes: [.init(kind: .resetCalendarWorkout, date: date(14))], state: state, now: date(13))
        try state.applyCoachAppChanges(reset, now: date(13))
        XCTAssertNil(state.trainingCalendar?.workoutOverride(on: date(14)))
    }

    func testCoachCanReadExactProjectedDayAndSubmitStrictSchema() throws {
        let state = try state()
        let query: [String: Any] = ["entity": "calendarDays", "ids": NSNull(), "exerciseID": NSNull(),
                                    "fromDate": "2026-10-14", "toDate": "2026-10-14", "offset": 0, "limit": 10]
        let reply = try CoachTools.read(JSONSerialization.data(withJSONObject: query), state: state, now: date(13))
        XCTAssertTrue(reply.contains("lower"))
        XCTAssertTrue(reply.contains("squat"))
        let args: [String: Any] = ["changes": [["kind": "setCalendarWorkout", "date": ISO8601DateFormatter().string(from: date(14)),
                                               "exercises": [["exerciseID": "bench_press", "sets": [], "target": [
                                                "sets": 2, "repsMin": 8, "repsMax": 10, "loadKg": NSNull(),
                                                "restSeconds": 90, "reason": "For this date", "targetEffort": NSNull()]]]]]]
        let changes = try CoachTools.decodeChanges(JSONSerialization.data(withJSONObject: args))
        XCTAssertEqual(changes.first?.kind, .setCalendarWorkout)
        XCTAssertEqual(changes.first?.exercises?.first?.target?.sets, 2)
    }
}
