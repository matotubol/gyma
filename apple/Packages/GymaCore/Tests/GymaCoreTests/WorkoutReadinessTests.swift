import XCTest
@testable import GymaCore

final class WorkoutReadinessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func plannedState(scheduledFor: Date? = nil, accepted: Bool = true, createdAt: Date? = nil) throws -> GymaState {
        var state = GymaState()
        let checkIn = SessionCheckIn(shift: .off, energy: .great, notes: "Private planning note", soreness: [.legs: .moderate])
        let plan = WorkoutPlan(id: "ready-plan", title: "Today's strength workout", exercises: [
            .init(exerciseID: "bench_press", target: .init(sets: 2, repsMin: 8, repsMax: 10, loadKg: 40, restSeconds: 90))
        ], checkIn: checkIn, createdAt: createdAt ?? now, scheduledFor: scheduledFor)
        try state.saveCoachConversation(.init(checkIn: checkIn, messages: [.init(role: .assistant, content: "Private planning discussion")], plan: plan))
        if accepted { try state.acceptCoachPlan(planID: plan.id, now: now) }
        return state
    }
    private func command(_ state: GymaState, at date: Date? = nil, readiness: WorkoutReadiness? = nil) -> WatchCommand {
        let date = date ?? now
        return WatchCommand(id: "watch-start", storeID: state.storeID, workoutID: "ready-plan", basedOnRevision: state.revision,
                            createdAt: date, action: .startAcceptedPlan(planID: "ready-plan", readiness: readiness ?? .init(energy: .good, recordedAt: date)))
    }
    func testReadySnapshotOnlyContainsAcceptedTodayPlanAndPublicBaseline() throws {
        let state = try plannedState()
        let snapshot = CompanionSnapshot(state: state, now: now, calendar: calendar)
        let ready = try XCTUnwrap(snapshot.readyPlan)
        XCTAssertEqual(ready.id, "ready-plan")
        XCTAssertEqual(ready.energy, .great)
        XCTAssertEqual(ready.soreness[.legs], .moderate)
        XCTAssertEqual(ready.soreness[.arms], Soreness.none)
        XCTAssertEqual(Set(ready.soreness.keys), Set(Muscle.allCases))
        XCTAssertTrue(ready.isAvailable(at: now))
        XCTAssertFalse(ready.isAvailable(at: ready.expiresAt))
        try ready.validate()
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertLessThan(data.count, 48 * 1024)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Private"))
        XCTAssertNil(CompanionSnapshot(state: try plannedState(accepted: false), now: now, calendar: calendar).readyPlan)
        for offset in [-86400.0, 86400.0] {
            XCTAssertNil(CompanionSnapshot(state: try plannedState(scheduledFor: now.addingTimeInterval(offset)), now: now, calendar: calendar).readyPlan)
        }
    }
    func testReadyPlanExpiresAtCalendarMidnightAcrossDaylightSaving() throws {
        var amsterdam = calendar
        amsterdam.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Amsterdam"))
        let springDay = try XCTUnwrap(amsterdam.date(from: .init(year: 2027, month: 3, day: 28, hour: 12)))
        var state = try plannedState()
        state.coachConversation?.plan?.scheduledFor = springDay
        let ready = try XCTUnwrap(CompanionSnapshot(state: state, now: springDay, calendar: amsterdam).readyPlan)
        XCTAssertEqual(ready.expiresAt.timeIntervalSince(ready.availableFrom), 23 * 3600)
        XCTAssertFalse(ready.isAvailable(at: ready.expiresAt))
    }
    func testWatchStartCapturesFreshReadinessAndReplayCannotCreateAnotherWorkout() throws {
        var state = try plannedState()
        var soreness = Soreness.allNone; soreness[.back] = .high
        let readiness = WorkoutReadiness(energy: .poor, soreness: soreness, recordedAt: now)
        let event = command(state, readiness: readiness)
        XCTAssertEqual(GymaReducer.apply(event, to: &state, now: now.addingTimeInterval(30), calendar: calendar).status, .applied)
        let workout = try XCTUnwrap(state.activeWorkout)
        XCTAssertEqual(workout.start, now.addingTimeInterval(30))
        XCTAssertEqual(workout.readiness, readiness)
        XCTAssertEqual(workout.energy, .poor)
        XCTAssertEqual(workout.checkIn?.energy, .great)
        XCTAssertEqual(workout.coachConversation?.messages.first?.content, "Private planning discussion")
        XCTAssertNil(CompanionSnapshot(state: state, now: now, calendar: calendar).readyPlan)
        XCTAssertNil(CompanionSnapshot(state: state, now: now, calendar: calendar).activeWorkout?.coachConversation)
        let persistedCommand = try JSONDecoder().decode(WatchCommand.self, from: JSONEncoder().encode(event))
        var reloaded = try NativeBackup.decode(NativeBackup.encode(state))
        XCTAssertEqual(GymaReducer.apply(persistedCommand, to: &reloaded, now: now.addingTimeInterval(60), calendar: calendar).status, .duplicate)
        XCTAssertEqual(reloaded.workouts.count, 1)
        XCTAssertEqual(reloaded.activeWorkout?.id, workout.id)
        XCTAssertEqual(reloaded.activeWorkout?.readiness, readiness)
    }
    func testReadinessPayloadEncodingIsStableAcrossDictionaryOrderAndRoundTrip() throws {
        var first = WorkoutReadiness(energy: .good, recordedAt: now)
        first.soreness[.chest] = .mild
        var second = first
        second.soreness = Dictionary(uniqueKeysWithValues: Muscle.allCases.reversed().map { ($0, first.soreness(for: $0)) })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(first), try encoder.encode(second))
        let decoded = try JSONDecoder().decode(WorkoutReadiness.self, from: encoder.encode(first))
        XCTAssertEqual(try encoder.encode(first), try encoder.encode(decoded))
        XCTAssertNotNil((try JSONSerialization.jsonObject(with: encoder.encode(first)) as? [String: Any])?["soreness"] as? [String: String])
    }
    func testStartRequiresFreshCompleteReadinessAndLatestState() throws {
        for scenario in ["stale-revision", "wrong-store", "missing-revision", "old-request", "old-readiness", "missing-muscle", "wrong-plan"] {
            var state = try plannedState()
            var readiness = WorkoutReadiness(energy: .good, recordedAt: now)
            if scenario == "old-readiness" { readiness.recordedAt = now.addingTimeInterval(-301) }
            if scenario == "missing-muscle" { readiness.soreness.removeValue(forKey: .legs) }
            var event = command(state, readiness: readiness)
            if scenario == "stale-revision" { event.basedOnRevision = state.revision - 1 }
            if scenario == "wrong-store" { event.storeID = "old-store" }
            if scenario == "missing-revision" { event.basedOnRevision = nil }
            if scenario == "wrong-plan" { event.workoutID = "different-plan" }
            let receivedAt = scenario == "old-request" ? now.addingTimeInterval(301) : now
            XCTAssertEqual(GymaReducer.apply(event, to: &state, now: receivedAt, calendar: calendar).status, .rejected, scenario)
            XCTAssertNil(state.activeWorkout, scenario)
            XCTAssertNotNil(state.coachConversation?.plan?.acceptedAt, scenario)
        }
    }
    func testStartRejectsYesterdayTomorrowAndUnacceptedPlans() throws {
        for state in [try plannedState(scheduledFor: now.addingTimeInterval(-86400)),
                      try plannedState(scheduledFor: now.addingTimeInterval(86400)), try plannedState(accepted: false)] {
            var state = state
            XCTAssertEqual(GymaReducer.apply(command(state), to: &state, now: now, calendar: calendar).status, .rejected)
            XCTAssertNil(state.activeWorkout)
        }
    }
    func testQueuedStartCrossingMidnightIsRejectedEvenWithinFiveMinutes() throws {
        let dayStart = calendar.startOfDay(for: now)
        let tappedAt = dayStart.addingTimeInterval(86400 - 10)
        var state = try plannedState()
        let event = command(state, at: tappedAt)
        XCTAssertEqual(GymaReducer.apply(event, to: &state, now: tappedAt.addingTimeInterval(20), calendar: calendar).status, .rejected)
        XCTAssertNil(state.activeWorkout)
    }
    func testSecondStartCommandCannotReplaceAnExistingWorkout() throws {
        var state = try plannedState()
        let event = command(state)
        XCTAssertEqual(GymaReducer.apply(event, to: &state, now: now, calendar: calendar).status, .applied)
        let workoutID = state.activeWorkout?.id
        var second = event; second.id = "another-start"; second.basedOnRevision = state.revision
        XCTAssertEqual(GymaReducer.apply(second, to: &state, now: now, calendar: calendar).status, .rejected)
        XCTAssertEqual(state.workouts.count, 1)
        XCTAssertEqual(state.activeWorkout?.id, workoutID)
    }
    func testReadinessSurvivesEditingPlanningCheckInFinishDeleteRestoreAndBackup() throws {
        var state = try plannedState()
        let readiness = WorkoutReadiness(energy: .medium, recordedAt: now)
        let workoutID = try state.startAcceptedPlan(planID: "ready-plan", readiness: readiness, now: now, calendar: calendar)
        try state.updateCheckIn(.init(shift: .night, energy: .great), workoutID: workoutID)
        XCTAssertEqual(state.activeWorkout?.energy, .medium)
        try state.finishWorkout(workoutID, at: now.addingTimeInterval(100))
        try state.deleteWorkout(workoutID)
        XCTAssertEqual(state.deletedWorkouts.first?.readiness, readiness)
        state = try NativeBackup.decode(NativeBackup.encode(state))
        try state.restoreWorkout(workoutID)
        XCTAssertEqual(state.workouts.first?.readiness, readiness)
    }
    func testLegacyPlanAndWorkoutDecodeWithoutInventingRecordedReadiness() throws {
        var state = try plannedState()
        let originalCreated = try XCTUnwrap(state.coachConversation?.plan?.createdAt)
        let roundTripped = try NativeBackup.decode(NativeBackup.encode(state))
        XCTAssertNil(roundTripped.coachConversation?.plan?.scheduledFor)
        XCTAssertEqual(roundTripped.coachConversation?.plan?.scheduledDate, originalCreated)
        let checkIn = SessionCheckIn(shift: .off, energy: .good)
        let legacyCheckIn = try JSONDecoder().decode(SessionCheckIn.self, from: JSONEncoder().encode(checkIn))
        XCTAssertNil(legacyCheckIn.soreness)
        XCTAssertEqual(legacyCheckIn.soreness(for: .legs), .none)
        try state.startAcceptedPlan(planID: "ready-plan", now: now, calendar: calendar)
        let legacyWorkout = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(XCTUnwrap(state.activeWorkout)))
        XCTAssertNil(legacyWorkout.readiness)
    }
}
