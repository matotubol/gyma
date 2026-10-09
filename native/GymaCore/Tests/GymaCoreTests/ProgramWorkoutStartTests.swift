import XCTest
@testable import GymaCore

final class ProgramWorkoutStartTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var program: TrainingProgram {
        .init(id: "program", title: "Eight-week upper/lower", goal: "Build strength", sessions: [
            .init(id: "upper", title: "Upper", exercises: [
                .init(exerciseID: "bench_press", target: .init(sets: 3, repsMin: 6, repsMax: 10, loadKg: 50, restSeconds: 90))
            ]),
            .init(id: "lower", title: "Lower", exercises: [
                .init(exerciseID: "squat", target: .init(sets: 3, repsMin: 6, repsMax: 10, loadKg: 60, restSeconds: 90))
            ])
        ], createdAt: now.addingTimeInterval(-86400), updatedAt: now.addingTimeInterval(-86400))
    }
    private func programState() throws -> GymaState {
        var state = GymaState()
        state.athleteProfile = .init(usualSessionMinutes: 60, updatedAt: now.addingTimeInterval(-86400))
        var conversation = CoachConversation.programPlanning(profile: state.athleteProfile)
        conversation.proposedProgram = program
        try state.saveCoachConversation(conversation)
        try state.acceptProgramProposal(programID: program.id, now: now.addingTimeInterval(-60))
        return state
    }
    private func watchCommand(_ state: GymaState, readiness: WorkoutReadiness? = nil, at date: Date? = nil) throws -> WatchCommand {
        let date = date ?? now
        let ready = try XCTUnwrap(CompanionSnapshot(state: state, now: date, calendar: calendar).readyPlan)
        return .init(id: "program-start", storeID: state.storeID, workoutID: ready.id, basedOnRevision: state.revision,
                     createdAt: date, action: .startAcceptedPlan(planID: ready.id, readiness: readiness ?? .init(energy: .good, recordedAt: date)))
    }

    func testPhoneProgramStartPersistsFreshCheckInWithoutReplacingPlanningConversation() throws {
        var state = try programState()
        let savedConversation = state.coachConversation
        let savedProgram = state.trainingProgram
        XCTAssertNil(state.coachConversation?.plan)
        XCTAssertNil(state.activeWorkout)
        let checkIn = SessionCheckIn(shift: .night, energy: .medium, timeMinutes: 30, sleepHours: 6.5,
                                     notes: "Only today", soreness: [.legs: .mild])
        let plan = try state.nextProgramPlan(checkIn: checkIn, now: now)
        let readiness = WorkoutReadiness(energy: checkIn.energy, soreness: checkIn.allSoreness, recordedAt: now)
        let id = try state.startPreparedProgramPlan(plan, readiness: readiness, now: now, calendar: calendar)
        XCTAssertEqual(state.activeWorkout?.id, id)
        XCTAssertEqual(state.activeWorkout?.checkIn, checkIn)
        XCTAssertEqual(state.activeWorkout?.readiness, readiness)
        XCTAssertEqual(state.activeWorkout?.acceptedPlanID, plan.id)
        XCTAssertEqual(state.activeWorkout?.planAcceptedAt, now)
        XCTAssertEqual(state.activeWorkout?.programSessionID, "upper")
        XCTAssertEqual(state.coachConversation, savedConversation)
        XCTAssertEqual(state.trainingProgram, savedProgram)
        XCTAssertNil(state.activeWorkout?.coachConversation)
        XCTAssertEqual(try NativeBackup.decode(NativeBackup.encode(state)), state)
    }

    func testPhoneProgramStartRejectsStaleOrMismatchedReviewWithoutMutation() throws {
        for scenario in ["energy", "soreness", "old-readiness", "old-plan", "tomorrow", "no-program", "changed-program", "changed-profile", "active"] {
            var state = try programState()
            let checkIn = SessionCheckIn(shift: .off, energy: .good)
            var plan = try state.nextProgramPlan(checkIn: checkIn, now: now)
            var readiness = WorkoutReadiness(energy: .good, recordedAt: now)
            if scenario == "energy" { readiness.energy = .poor }
            if scenario == "soreness" { readiness.soreness[.back] = .high }
            if scenario == "old-readiness" { readiness.recordedAt = now.addingTimeInterval(-301) }
            if scenario == "old-plan" { plan.createdAt = now.addingTimeInterval(-301) }
            if scenario == "tomorrow" { plan.scheduledFor = now.addingTimeInterval(86400) }
            if scenario == "no-program" { plan.programID = nil; plan.programSessionID = nil; plan.programRevision = nil }
            if scenario == "changed-program" { state.trainingProgram?.revision += 1 }
            if scenario == "changed-profile" { state.athleteProfile?.updatedAt = now.addingTimeInterval(1) }
            if scenario == "active" { try state.startWorkout(.init(start: now)) }
            let before = state
            XCTAssertThrowsError(try state.startPreparedProgramPlan(plan, readiness: readiness, now: now, calendar: calendar), scenario)
            XCTAssertEqual(state, before, scenario)
        }
    }

    func testFreshProgramStartSupersedesOldUnstartedWorkoutDraft() throws {
        var state = try programState()
        let oldCheckIn = SessionCheckIn(shift: .morning, energy: .poor, sleepHours: 3, notes: "Old daily note")
        let oldPlan = try state.nextProgramPlan(checkIn: oldCheckIn, now: now.addingTimeInterval(-86400))
        try state.saveCoachConversation(.init(checkIn: oldCheckIn, plan: oldPlan))
        let fresh = SessionCheckIn(shift: .off, energy: .great, timeMinutes: 60, sleepHours: 8)
        let plan = try state.nextProgramPlan(checkIn: fresh, now: now)
        try state.startPreparedProgramPlan(plan, readiness: .init(energy: fresh.energy, recordedAt: now), now: now, calendar: calendar)
        XCTAssertEqual(state.activeWorkout?.checkIn, fresh)
        XCTAssertNil(state.coachConversation)
    }

    func testSavedProgramWatchSnapshotDoesNotReportPlanningReadinessOrPrivateNotes() throws {
        let state = try programState()
        let ready = try XCTUnwrap(CompanionSnapshot(state: state, now: now, calendar: calendar).readyPlan)
        XCTAssertEqual(ready.programID, program.id)
        XCTAssertEqual(ready.programSessionID, "upper")
        XCTAssertEqual(ready.programRevision, 1)
        XCTAssertEqual(ready.energy, .good)
        XCTAssertEqual(ready.soreness, Soreness.allNone)
        XCTAssertEqual(ready.exerciseCount, 1)
        XCTAssertEqual(ready, state.readyProgramPlan(now: now.addingTimeInterval(30), calendar: calendar))
        let text = String(decoding: try JSONEncoder().encode(ready), as: UTF8.self)
        XCTAssertFalse(text.contains("checkIn"))
        XCTAssertFalse(text.contains("recordedAt"))
        XCTAssertFalse(text.contains("loadKg"))
        XCTAssertFalse(ready.isAvailable(at: ready.expiresAt))
    }

    func testProgramWatchStartUsesFreshReadinessAndIsIdempotentAcrossPersistence() throws {
        var state = try programState()
        let conversation = state.coachConversation
        var soreness = Soreness.allNone; soreness[.back] = .high
        let readiness = WorkoutReadiness(energy: .poor, soreness: soreness, recordedAt: now)
        let command = try watchCommand(state, readiness: readiness)
        XCTAssertEqual(GymaReducer.apply(command, to: &state, now: now.addingTimeInterval(20), calendar: calendar).status, .applied)
        let workout = try XCTUnwrap(state.activeWorkout)
        XCTAssertEqual(workout.readiness, readiness)
        XCTAssertEqual(workout.checkIn?.energy, .poor)
        XCTAssertEqual(workout.checkIn?.allSoreness, soreness)
        XCTAssertEqual(workout.checkIn?.timeMinutes, 60)
        XCTAssertNil(workout.checkIn?.sleepHours)
        XCTAssertNil(workout.exercises.first?.target?.loadKg)
        XCTAssertEqual(state.coachConversation, conversation)
        state = try NativeBackup.decode(NativeBackup.encode(state))
        let reloadedCommand = try JSONDecoder().decode(WatchCommand.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(GymaReducer.apply(reloadedCommand, to: &state, now: now.addingTimeInterval(30), calendar: calendar).status, .duplicate)
        XCTAssertEqual(state.workouts.count, 1)
        XCTAssertEqual(state.activeWorkout?.id, workout.id)
    }

    func testProgramWatchStartRejectsStaleIdentityRevisionStoreAndReadiness() throws {
        for scenario in ["wrong-store", "stale-revision", "missing-revision", "old-request", "old-readiness", "missing-muscle", "wrong-plan", "changed-program"] {
            var state = try programState()
            var readiness = WorkoutReadiness(energy: .good, recordedAt: now)
            if scenario == "old-readiness" { readiness.recordedAt = now.addingTimeInterval(-301) }
            if scenario == "missing-muscle" { readiness.soreness.removeValue(forKey: .legs) }
            var command = try watchCommand(state, readiness: readiness)
            if scenario == "wrong-store" { command.storeID = "replaced-store" }
            if scenario == "stale-revision" { command.basedOnRevision = state.revision - 1 }
            if scenario == "missing-revision" { command.basedOnRevision = nil }
            if scenario == "wrong-plan" { command.workoutID = "other-plan" }
            if scenario == "changed-program" { state.trainingProgram?.revision += 1 }
            let receivedAt = scenario == "old-request" ? now.addingTimeInterval(301) : now
            XCTAssertEqual(GymaReducer.apply(command, to: &state, now: receivedAt, calendar: calendar).status, .rejected, scenario)
            XCTAssertNil(state.activeWorkout, scenario)
            XCTAssertNotNil(state.trainingProgram, scenario)
        }
    }

    func testProgramWatchStartExpiresAcrossMidnightAndAfterFinishingTodaysSlot() throws {
        var state = try programState()
        let tappedAt = calendar.startOfDay(for: now).addingTimeInterval(86400 - 10)
        let command = try watchCommand(state, at: tappedAt)
        XCTAssertEqual(GymaReducer.apply(command, to: &state, now: tappedAt.addingTimeInterval(20), calendar: calendar).status, .rejected)
        let freshCommand = try watchCommand(state)
        var fresh = freshCommand; fresh.id = "fresh-start"
        XCTAssertEqual(GymaReducer.apply(fresh, to: &state, now: now, calendar: calendar).status, .applied)
        let id = try XCTUnwrap(state.activeWorkout?.id)
        try state.finishWorkout(id, at: now.addingTimeInterval(60))
        XCTAssertNil(CompanionSnapshot(state: state, now: now.addingTimeInterval(60), calendar: calendar).readyPlan)
        XCTAssertNotNil(CompanionSnapshot(state: state, now: now.addingTimeInterval(86400), calendar: calendar).readyPlan)
    }

    func testProgramWatchAvailabilityFollowsCalendarWithoutCreatingFutureReadiness() throws {
        var state = try programState()
        state.trainingCalendar = .init(startDate: now, cycleAnchorDate: now, trainingCycleDays: [2], timeZone: calendar.timeZone)
        XCTAssertNil(CompanionSnapshot(state: state, now: now, calendar: calendar).readyPlan)
        let tomorrow = now.addingTimeInterval(86400)
        XCTAssertNotNil(CompanionSnapshot(state: state, now: tomorrow, calendar: calendar).readyPlan)
        XCTAssertNil(state.coachConversation?.plan)
        XCTAssertTrue(state.workouts.isEmpty)
        var command = try watchCommand(state, at: tomorrow)
        command.id = "calendar-start"
        XCTAssertEqual(GymaReducer.apply(command, to: &state, now: tomorrow, calendar: calendar).status, .applied)
        XCTAssertEqual(state.activeWorkout?.checkIn?.shift, .morning)
    }

    func testLegacyReadyPlanDecodesWithoutProgramMetadataAndKeepsItsIdentity() throws {
        let checkIn = SessionCheckIn(shift: .off, energy: .great)
        let plan = WorkoutPlan(id: "legacy-plan", title: "Legacy", exercises: program.sessions[0].exercises, checkIn: checkIn, createdAt: now)
        let ready = ReadyWorkoutPlan(plan: plan, calendar: calendar)
        let data = try JSONEncoder().encode(ready)
        let decoded = try JSONDecoder().decode(ReadyWorkoutPlan.self, from: data)
        XCTAssertEqual(decoded, ready)
        XCTAssertNil(decoded.programID)
        XCTAssertNil(decoded.programSessionID)
        XCTAssertNil(decoded.programRevision)
        XCTAssertEqual(decoded.id, "legacy-plan")
        try decoded.validate()
    }

    func testConsumedDailyCoachPlanDoesNotBlockNextProgramSessionOnWatch() throws {
        var state = try programState()
        let checkIn = SessionCheckIn(shift: .off, energy: .good)
        let plan = try state.nextProgramPlan(checkIn: checkIn, now: now)
        try state.saveCoachConversation(.init(checkIn: checkIn, plan: plan))
        try state.acceptCoachPlan(planID: plan.id, now: now)
        let workoutID = try state.startAcceptedPlan(planID: plan.id, readiness: .init(energy: .good, recordedAt: now), now: now, calendar: calendar)
        try state.finishWorkout(workoutID, at: now.addingTimeInterval(60))
        XCTAssertNil(CompanionSnapshot(state: state, now: now.addingTimeInterval(60), calendar: calendar).readyPlan)
        let next = try XCTUnwrap(CompanionSnapshot(state: state, now: now.addingTimeInterval(86400), calendar: calendar).readyPlan)
        XCTAssertEqual(next.programID, program.id)
        XCTAssertNotEqual(next.id, plan.id)
    }

    func testSaveConversationCannotForgeProgramAcceptanceAndEditsClearIt() throws {
        var state = GymaState()
        var forged = CoachConversation.programPlanning()
        forged.acceptedProgramID = "unaccepted"
        try state.saveCoachConversation(forged)
        XCTAssertNil(state.coachConversation?.acceptedProgramID)
        state = try programState()
        let accepted = try XCTUnwrap(state.coachConversation)
        try state.saveCoachConversation(accepted)
        XCTAssertEqual(state.coachConversation?.acceptedProgramID, program.id)
        var edited = accepted
        edited.messages.append(.init(role: .user, content: "Please revise this program."))
        try state.saveCoachConversation(edited)
        XCTAssertNil(state.coachConversation?.acceptedProgramID)
    }

    func testAcceptedDailyCoachAdjustmentKeepsCheckInAndTargetsAndRequiresFreshReadiness() throws {
        var state = try programState()
        let savedProgram = state.trainingProgram
        let checkIn = SessionCheckIn(shift: .night, energy: .medium, timeMinutes: 40, sleepHours: 6,
                                     painNote: "Shoulder discomfort", soreness: [.chest: .moderate])
        let originalReadiness = WorkoutReadiness(energy: checkIn.energy, soreness: checkIn.allSoreness, recordedAt: now)
        var adjusted = try state.nextProgramPlan(checkIn: checkIn, now: now)
        adjusted.exercises[0].target?.sets = 1
        adjusted.exercises[0].target?.reason = "Today's reviewed adjustment."
        var conversation = CoachConversation(checkIn: checkIn, messages: [
            .init(role: .user, content: "Adjust today's workout using my check-in."),
            .init(role: .assistant, content: "Review this daily adjustment.")
        ], plan: adjusted)
        conversation.purpose = .workout
        try state.saveCoachConversation(conversation)
        let acceptedAt = now.addingTimeInterval(360)
        try state.acceptCoachPlan(planID: adjusted.id, now: acceptedAt)
        XCTAssertThrowsError(try state.startAcceptedPlan(planID: adjusted.id, readiness: originalReadiness, now: acceptedAt, calendar: calendar))
        XCTAssertNil(state.activeWorkout)
        XCTAssertEqual(state.coachConversation?.plan?.exercises, adjusted.exercises)
        let confirmed = WorkoutReadiness(energy: checkIn.energy, soreness: checkIn.allSoreness, recordedAt: acceptedAt)
        try state.startAcceptedPlan(planID: adjusted.id, readiness: confirmed, now: acceptedAt, calendar: calendar)
        XCTAssertEqual(state.activeWorkout?.checkIn, checkIn)
        XCTAssertEqual(state.activeWorkout?.readiness, confirmed)
        XCTAssertEqual(state.activeWorkout?.exercises, adjusted.exercises)
        XCTAssertEqual(state.activeWorkout?.coachConversation?.messages, conversation.messages)
        XCTAssertEqual(state.trainingProgram, savedProgram)
    }
}
