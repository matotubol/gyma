import XCTest
@testable import GymaCore

final class DailyTrainingEligibilityTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return value
    }
    private func date(_ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private var checkIn: SessionCheckIn { .init(shift: .off, energy: .good, timeMinutes: 60) }
    private var program: TrainingProgram {
        .init(id: "scheduled-program", title: "Upper / lower", goal: "Build strength", sessions: [
            .init(id: "upper", title: "Upper", exercises: [.init(exerciseID: "bench_press", target: .init(sets: 2, repsMin: 6, repsMax: 10, loadKg: 50, restSeconds: 90))]),
            .init(id: "lower", title: "Lower", exercises: [.init(exerciseID: "squat", target: .init(sets: 2, repsMin: 6, repsMax: 10, loadKg: 60, restSeconds: 90))])
        ], createdAt: date(1), updatedAt: date(1))
    }
    private func scheduledState() throws -> GymaState {
        var state = GymaState()
        state.trainingProgram = program
        try state.saveTrainingCalendar(.defaultPlan(now: date(10), timeZone: calendar.timeZone), now: date(10))
        return state
    }
    private func acceptStandalonePlan(in state: inout GymaState, scheduledFor: Date, createdAt: Date) throws -> WorkoutPlan {
        let plan = WorkoutPlan(title: "Reviewed workout", exercises: program.sessions[0].exercises,
                               checkIn: checkIn, createdAt: createdAt, scheduledFor: scheduledFor)
        try state.saveCoachConversation(.init(checkIn: checkIn, plan: plan))
        try state.acceptCoachPlan(planID: plan.id, now: createdAt)
        return try XCTUnwrap(state.coachConversation?.plan)
    }
    private func command(for state: GymaState, at now: Date, fallback: Calendar? = nil) throws -> WatchCommand {
        let ready = try XCTUnwrap(CompanionSnapshot(state: state, now: now, calendar: fallback ?? calendar).readyPlan)
        return .init(storeID: state.storeID, workoutID: ready.id, basedOnRevision: state.revision, createdAt: now,
                     action: .startAcceptedPlan(planID: ready.id, readiness: .init(energy: .good, recordedAt: now)))
    }

    func testOctober10CannotPrepareOrStartBeforeOctober13() throws {
        var state = try scheduledState()
        let before = state
        XCTAssertEqual(state.dailyTrainingStatus(now: date(10)), .beforeStart(date(13, hour: 0)))
        XCTAssertFalse(state.dailyTrainingStatus(now: date(10)).allowsWorkoutStart)
        XCTAssertThrowsError(try state.nextProgramPlan(checkIn: checkIn, now: date(10)))
        XCTAssertThrowsError(try state.startWorkout(.init(start: date(10))))
        XCTAssertNil(CompanionSnapshot(state: state, now: date(10)).readyPlan)
        XCTAssertEqual(state, before)
        XCTAssertEqual(state.trainingCalendar?.entries(program: program, history: [], now: date(10)).first?.session?.id, "upper")
    }

    func testOctober13StartsTodaysSessionWithoutConsumingOctober14Projection() throws {
        var state = try scheduledState()
        let original = state
        let now = date(13)
        let entries = try XCTUnwrap(state.trainingCalendar).entries(program: program, history: [], now: now)
        XCTAssertEqual(entries[0].session?.id, "upper")
        XCTAssertEqual(entries[1].session?.id, "lower")
        let draft = try state.nextProgramPlan(checkIn: checkIn, now: now)
        XCTAssertEqual(state, original, "Viewing and preparing a session cannot create history or advance rotation.")
        XCTAssertEqual(draft.programSessionID, "upper")
        XCTAssertEqual(state.dailyTrainingStatus(now: now), .trainingDay)
        let id = try state.startPreparedProgramPlan(draft, readiness: .init(energy: .good, recordedAt: now), now: now)
        XCTAssertEqual(state.workouts.count, 1)
        XCTAssertEqual(state.activeWorkout?.id, id)
        XCTAssertEqual(state.activeWorkout?.programSessionID, "upper")
        XCTAssertEqual(state.trainingProgram, original.trainingProgram)
        XCTAssertEqual(state.trainingCalendar, original.trainingCalendar)
    }

    func testCompletedTodayBlocksSecondStartAndOnlyActualWorkingSetsAdvanceTomorrow() throws {
        var state = try scheduledState()
        let now = date(13)
        let draft = try state.nextProgramPlan(checkIn: checkIn, now: now)
        let id = try state.startPreparedProgramPlan(draft, readiness: .init(energy: .good, recordedAt: now), now: now)
        try state.addSet(.init(kg: 50, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: id, now: now)
        try state.finishWorkout(id, at: now.addingTimeInterval(60))
        let before = state
        XCTAssertEqual(state.dailyTrainingStatus(now: now.addingTimeInterval(60)), .completedToday)
        XCTAssertThrowsError(try state.nextProgramPlan(checkIn: checkIn, now: now.addingTimeInterval(60)))
        XCTAssertThrowsError(try state.startPreparedProgramPlan(draft, readiness: .init(energy: .good, recordedAt: now), now: now.addingTimeInterval(60)))
        XCTAssertNil(CompanionSnapshot(state: state, now: now.addingTimeInterval(60)).readyPlan)
        XCTAssertEqual(state, before)
        XCTAssertEqual(try state.nextProgramPlan(checkIn: checkIn, now: date(14)).programSessionID, "lower")
        XCTAssertEqual(state.workouts.count, 1)
    }

    func testRestDayAndFinishedBlockCannotPrepareOrStartEvenWithAcceptedTodayPlan() throws {
        for now in [date(10), date(15), try XCTUnwrap(scheduledState().trainingCalendar).reviewDate] {
            var state = try scheduledState()
            let accepted = try acceptStandalonePlan(in: &state, scheduledFor: now, createdAt: now)
            let before = state
            XCTAssertFalse(state.dailyTrainingStatus(now: now).allowsWorkoutStart)
            XCTAssertThrowsError(try state.nextProgramPlan(checkIn: checkIn, now: now))
            XCTAssertFalse(state.canStartAcceptedPlan(accepted, now: now))
            XCTAssertNil(CompanionSnapshot(state: state, now: now).readyPlan)
            XCTAssertThrowsError(try state.startAcceptedPlan(planID: accepted.id, now: now))
            XCTAssertEqual(state, before)
        }
        let state = try scheduledState()
        XCTAssertEqual(state.dailyTrainingStatus(now: date(15)), .recoveryDay)
        XCTAssertEqual(state.dailyTrainingStatus(now: try XCTUnwrap(state.trainingCalendar).reviewDate), .blockComplete)
    }

    func testAcceptedIndependentPlanCannotRepeatCompletedTodayOrAdvanceAnEmptyWorkout() throws {
        var state = try scheduledState()
        let now = date(13)
        let draft = try state.nextProgramPlan(checkIn: checkIn, now: now)
        let id = try state.startPreparedProgramPlan(draft, readiness: .init(energy: .good, recordedAt: now), now: now)
        let later = now.addingTimeInterval(60)
        try state.finishWorkout(id, at: later)
        let accepted = try acceptStandalonePlan(in: &state, scheduledFor: later, createdAt: later)
        let before = state
        XCTAssertEqual(state.dailyTrainingStatus(now: later), .completedToday)
        XCTAssertFalse(state.canStartAcceptedPlan(accepted, now: later))
        XCTAssertThrowsError(try state.startAcceptedPlan(planID: accepted.id, now: later))
        XCTAssertNil(CompanionSnapshot(state: state, now: later).readyPlan)
        XCTAssertEqual(state, before)
        XCTAssertEqual(try state.nextProgramPlan(checkIn: checkIn, now: date(14)).programSessionID, "upper", "An empty completed workout blocks a duplicate today without inventing training progress.")
    }

    func testOptionalActivitiesRemainAvailableOnARecoveryDay() throws {
        var state = try scheduledState()
        let now = date(15)
        try state.setCalendarActivity(on: now, kind: .stretching, isPlanned: true, now: now)
        XCTAssertEqual(state.dailyTrainingStatus(now: now), .recoveryDay)
        try state.setCalendarActivityCompleted(on: now, kind: .stretching, isCompleted: true, now: now)
        XCTAssertTrue(state.trainingCalendar?.activities(on: now).first?.isCompleted == true)
        XCTAssertEqual(state.dailyTrainingStatus(now: now), .recoveryDay)
        XCTAssertThrowsError(try state.nextProgramPlan(checkIn: checkIn, now: now))
        XCTAssertTrue(state.workouts.isEmpty)
    }

    func testAcceptingRecurringProgramBeforeBlockOrOnRestDayStillSavesProgram() throws {
        for now in [date(10), date(15)] {
            var state = try scheduledState()
            state.trainingProgram = nil
            var conversation = CoachConversation(checkIn: checkIn)
            conversation.proposedProgram = program
            try state.saveCoachConversation(conversation)
            try state.acceptProgramProposal(programID: program.id, now: now)
            XCTAssertEqual(state.trainingProgram?.id, program.id)
            XCTAssertNil(state.coachConversation?.plan)
            XCTAssertNil(state.coachConversation?.proposedProgram)
            XCTAssertNil(state.activeWorkout)
            try state.validate()
        }
    }

    func testTomorrowAcceptedPlanCannotBeStartedTodayAndDoesNotBlockTodaysProgram() throws {
        var state = try scheduledState()
        let accepted = try acceptStandalonePlan(in: &state, scheduledFor: date(14), createdAt: date(13))
        let before = state
        XCTAssertFalse(state.canStartAcceptedPlan(accepted, now: date(13)))
        XCTAssertThrowsError(try state.startAcceptedPlan(planID: accepted.id, now: date(13)))
        XCTAssertNotEqual(CompanionSnapshot(state: state, now: date(13)).readyPlan?.id, accepted.id)
        XCTAssertNotNil(state.readyProgramPlan(now: date(13)))
        XCTAssertEqual(state, before)
        XCTAssertTrue(state.canStartAcceptedPlan(accepted, now: date(14)))
        XCTAssertEqual(CompanionSnapshot(state: state, now: date(14)).readyPlan?.id, accepted.id)
    }

    func testCachedPreparedPlanCannotBypassCalendarEdit() throws {
        var state = try scheduledState()
        let now = date(13)
        let draft = try state.nextProgramPlan(checkIn: checkIn, now: now)
        let watch = try command(for: state, at: now)
        try state.setCalendarTrainingDay(on: now, isTraining: false, now: now)
        let before = state
        XCTAssertThrowsError(try state.startPreparedProgramPlan(draft, readiness: .init(energy: .good, recordedAt: now), now: now))
        XCTAssertEqual(state, before)
        XCTAssertEqual(GymaReducer.apply(watch, to: &state, now: now).status, .rejected)
        XCTAssertNil(state.activeWorkout)
    }

    func testWatchAndPhoneRejectCrossingSavedMidnightEvenIfDeviceDateIsUnchanged() throws {
        var fallback = Calendar(identifier: .gregorian)
        fallback.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let tappedAt = date(13, hour: 23, minute: 59)
        let deliveredAt = date(14, hour: 0, minute: 1)
        XCTAssertTrue(fallback.isDate(tappedAt, inSameDayAs: deliveredAt))
        for acceptedStart in [false, true] {
            var state = try scheduledState()
            var draft = try state.nextProgramPlan(checkIn: checkIn, now: tappedAt)
            if acceptedStart {
                try state.saveCoachConversation(.init(checkIn: checkIn, plan: draft))
                try state.acceptCoachPlan(planID: draft.id, now: tappedAt)
                draft = try XCTUnwrap(state.coachConversation?.plan)
            }
            let watch = try command(for: state, at: tappedAt, fallback: fallback)
            let before = state
            if acceptedStart {
                XCTAssertThrowsError(try state.startAcceptedPlan(planID: draft.id, now: deliveredAt, calendar: fallback))
            } else {
                XCTAssertThrowsError(try state.startPreparedProgramPlan(draft, readiness: .init(energy: .good, recordedAt: tappedAt), now: deliveredAt, calendar: fallback))
            }
            XCTAssertEqual(state, before)
            XCTAssertEqual(GymaReducer.apply(watch, to: &state, now: deliveredAt, calendar: fallback).status, .rejected)
            XCTAssertNil(state.activeWorkout)
        }
    }

    func testSavedTimeZoneKeepsSameDayWatchStartAcrossDeviceMidnight() throws {
        var fallback = Calendar(identifier: .gregorian)
        fallback.timeZone = TimeZone(secondsFromGMT: 0)!
        let tappedAt = date(13, hour: 1, minute: 59)
        let deliveredAt = date(13, hour: 2, minute: 1)
        XCTAssertFalse(fallback.isDate(tappedAt, inSameDayAs: deliveredAt))
        for acceptedStart in [false, true] {
            var state = try scheduledState()
            if acceptedStart {
                _ = try acceptStandalonePlan(in: &state, scheduledFor: tappedAt, createdAt: tappedAt)
            }
            let ready = try XCTUnwrap(CompanionSnapshot(state: state, now: tappedAt, calendar: fallback).readyPlan)
            XCTAssertEqual(ready.availableFrom, date(13, hour: 0))
            XCTAssertEqual(ready.expiresAt, date(14, hour: 0))
            XCTAssertTrue(ready.isAvailable(at: deliveredAt))
            let watch = try command(for: state, at: tappedAt, fallback: fallback)
            XCTAssertEqual(GymaReducer.apply(watch, to: &state, now: deliveredAt, calendar: fallback).status, .applied)
            XCTAssertEqual(state.activeWorkout?.start, deliveredAt)
        }
    }

    func testActiveWorkoutRemainsAvailableOnRecoveryDayAndAfterBlock() throws {
        var state = try scheduledState()
        let now = date(13)
        let plan = try state.nextProgramPlan(checkIn: checkIn, now: now)
        let id = try state.startPreparedProgramPlan(plan, readiness: .init(energy: .good, recordedAt: now), now: now)
        for later in [date(15), try XCTUnwrap(state.trainingCalendar).reviewDate] {
            XCTAssertEqual(state.dailyTrainingStatus(now: later), .activeWorkout)
            let snapshot = CompanionSnapshot(state: state, now: later)
            XCTAssertEqual(snapshot.activeWorkout?.id, id)
            XCTAssertNil(snapshot.readyPlan)
        }
        try state.addSet(.init(kg: 50, reps: 8, isWarmup: false), exerciseID: "bench_press", workoutID: id, now: date(15))
        XCTAssertEqual(state.activeWorkout?.exercises.first?.sets.count, 1)
    }

    func testNoSavedCalendarPreservesStandaloneAndProgramPreparation() throws {
        var state = GymaState()
        state.trainingProgram = program
        XCTAssertEqual(state.dailyTrainingStatus(now: date(10)), .noCalendar)
        XCTAssertNoThrow(try state.nextProgramPlan(checkIn: checkIn, now: date(10)))
        let accepted = try acceptStandalonePlan(in: &state, scheduledFor: date(10), createdAt: date(10))
        XCTAssertTrue(state.canStartAcceptedPlan(accepted, now: date(10)))
        XCTAssertNoThrow(try state.startAcceptedPlan(planID: accepted.id, now: date(10)))
    }
}
