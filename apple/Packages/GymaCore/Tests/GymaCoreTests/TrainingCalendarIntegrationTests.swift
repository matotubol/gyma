import XCTest
@testable import GymaCore

final class TrainingCalendarIntegrationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return value
    }
    private func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private var checkIn: SessionCheckIn { .init(shift: .morning, energy: .good, timeMinutes: 60) }
    private var target: ExerciseTarget {
        .init(sets: 2, repsMin: 6, repsMax: 10, loadKg: 60, restSeconds: 90, targetEffort: .challenging)
    }
    private var program: TrainingProgram {
        .init(id: "calendar-program", title: "Upper / lower", goal: "Build strength", sessions: [
            .init(id: "upper", title: "Upper", exercises: [.init(exerciseID: "bench_press", target: target)]),
            .init(id: "lower", title: "Lower", exercises: [.init(exerciseID: "squat", target: target)])
        ], createdAt: date(10, 1), updatedAt: date(10, 1))
    }
    private var trainingCalendar: TrainingCalendarPlan {
        .init(startDate: date(10, 17), cycleAnchorDate: date(10, 17), timeZone: calendar.timeZone)
    }
    private func completed(id: String = "previous", on start: Date) -> Workout {
        .init(id: id, start: start, end: start.addingTimeInterval(1800), checkIn: checkIn,
              exercises: [.init(exerciseID: "bench_press", sets: [
                .init(id: "set-\(id)", kg: 60, reps: 8, effort: .challenging, isWarmup: false)
              ], target: target)], programID: program.id, programSessionID: "upper", programRevision: program.revision)
    }
    private func stateWithCalendar() throws -> GymaState {
        var state = GymaState()
        state.trainingProgram = program
        state.workouts = [completed(on: date(10, 15))]
        try state.saveTrainingCalendar(trainingCalendar, now: date(10, 17))
        try state.validate()
        return state
    }
    private func stateWithDraft(proposedProgram: Bool = false) throws -> GymaState {
        var state = try stateWithCalendar()
        var conversation = CoachConversation(checkIn: checkIn, messages: [
            .init(role: .user, content: "Keep this discussion when I move training."),
            .init(role: .assistant, content: "Review the proposal.")
        ])
        if proposedProgram {
            var proposal = program
            proposal.revision += 1
            conversation.proposedProgram = proposal
            try state.saveCoachConversation(conversation)
        } else {
            let draft = try state.nextProgramPlan(checkIn: checkIn, now: date(10, 18))
            conversation.plan = draft
            try state.saveCoachConversation(conversation)
            try state.acceptCoachPlan(planID: draft.id, now: date(10, 18))
        }
        try state.validate()
        return state
    }
    private func context(_ data: Data) throws -> String {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap((object["input"] as? [[String: String]])?.first?["content"])
    }

    func testNativeBackupPreservesCalendarOverridesAndLegacyStateOmitsCalendar() throws {
        var state = try stateWithCalendar()
        try state.moveCalendarTrainingDay(from: date(10, 25), to: date(10, 23), now: date(10, 17))
        let data = try NativeBackup.encode(state)
        let restored = try NativeBackup.decode(data)
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.trainingCalendar?.timeZoneIdentifier, "Europe/Amsterdam")
        XCTAssertEqual(restored.trainingCalendar?.dayOverrides.count, 2)
        XCTAssertEqual(restored.trainingCalendar?.dates.count, 56)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "trainingCalendar")
        let oldBackup = try NativeBackup.decode(JSONSerialization.data(withJSONObject: legacy))
        var expected = state
        expected.trainingCalendar = nil
        XCTAssertEqual(oldBackup, expected)
        XCTAssertNil(oldBackup.trainingCalendar)
    }

    func testMalformedCalendarRejectsBothBackupImportAndExport() throws {
        let valid = try stateWithCalendar()
        var malformedPlans: [TrainingCalendarPlan] = []
        var malformed = trainingCalendar
        malformed.timeZoneIdentifier = "INVALID_PRIVATE_TIME_ZONE"
        malformedPlans.append(malformed)
        malformed = trainingCalendar
        malformed.trainingCycleDays = [2, 2, 5]
        malformedPlans.append(malformed)
        malformed = trainingCalendar
        malformed.dayOverrides = [.init(dayOffset: 56, isTraining: true)]
        malformedPlans.append(malformed)
        for plan in malformedPlans {
            var state = valid
            state.trainingCalendar = plan
            let raw = try JSONEncoder().encode(state)
            XCTAssertThrowsError(try NativeBackup.decode(raw))
            XCTAssertThrowsError(try NativeBackup.encode(state))
        }
    }

    func testWatchSnapshotExcludesCalendarAndCalendarEditsRemoveReadyDraft() throws {
        var state = try stateWithDraft()
        let ready = CompanionSnapshot(state: state, now: date(10, 18), calendar: calendar)
        XCTAssertNotNil(ready.readyPlan)
        let text = String(decoding: try JSONEncoder().encode(ready), as: UTF8.self)
        for field in ["trainingCalendar", "trainingCycleDays", "cycleAnchorDate", "dayOverrides", "Europe/Amsterdam"] {
            XCTAssertFalse(text.contains(field), "Watch snapshot leaked calendar field \(field)")
        }
        try state.setCalendarTrainingDay(on: date(10, 19), isTraining: true, now: date(10, 17))
        let refreshed = CompanionSnapshot(state: state, now: date(10, 18), calendar: calendar)
        XCTAssertNotEqual(refreshed.readyPlan?.id, ready.readyPlan?.id, "A calendar edit invalidates the accepted daily draft.")
        XCTAssertEqual(refreshed.readyPlan?.programID, program.id, "Today's saved program can still collect a fresh check-in.")
    }

    func testBothCoachModesReceiveCivilDatesFrequencyAndProjectionsWithoutRawPrivateHistory() throws {
        var prior = completed(on: date(10, 15))
        prior.checkIn?.notes = "PRIVATE_PREVIOUS_CHECK_IN"
        prior.coachConversation = .init(messages: [.init(role: .user, content: "PRIVATE_PREVIOUS_CONVERSATION")])
        let conversation = CoachConversation(checkIn: checkIn, messages: [.init(role: .user, content: "Review my schedule.")])
        let planning = try context(CoachAPI.requestBody(conversation: conversation, catalog: ExerciseCatalog.builtIn,
                                                       history: [prior], program: program, now: date(10, 17), trainingCalendar: trainingCalendar))
        let active = Workout(id: "active", start: date(10, 17),
                             coachConversation: .init(messages: [.init(role: .user, content: "How does this fit my schedule?")]),
                             exercises: [.init(exerciseID: "bench_press", target: target)])
        let during = try context(WorkoutCoachAPI.requestBody(workout: active, storeID: "store", revision: 1, restTimer: nil,
                                                             catalog: ExerciseCatalog.builtIn, history: [prior], now: date(10, 17),
                                                             program: program, trainingCalendar: trainingCalendar))
        for text in [planning, during] {
            for fact in ["5 sessions per 10 days, NOT per week", "Europe/Amsterdam", "2026-10-17 through 2026-12-11",
                         "review on 2026-12-12", "2026-10-18: Morning, Lower", "Upper/lower preference: Yes"] {
                XCTAssertTrue(text.contains(fact), "Missing calendar fact: \(fact)")
            }
            XCTAssertFalse(text.contains("PRIVATE_PREVIOUS_CHECK_IN"))
            XCTAssertFalse(text.contains("PRIVATE_PREVIOUS_CONVERSATION"))
            XCTAssertTrue(text.contains("Missed dates never add catch-up volume or advance the actual program"))
        }
    }

    func testAllCalendarMutationsInvalidateWorkoutAndProgramDraftsPreservingDiscussionAndHistory() throws {
        for hasProgramProposal in [false, true] {
            for operation in 0..<3 {
                var state = try stateWithDraft(proposedProgram: hasProgramProposal)
                let previous = state
                let oldPlanID = state.coachConversation?.plan?.id
                switch operation {
                case 0:
                    var changed = trainingCalendar
                    changed.trainingCycleDays = [2, 5, 8, 10]
                    try state.saveTrainingCalendar(changed, now: date(10, 17))
                case 1:
                    try state.setCalendarTrainingDay(on: date(10, 19), isTraining: true, now: date(10, 17))
                default:
                    try state.moveCalendarTrainingDay(from: date(10, 18), to: date(10, 19), now: date(10, 17))
                }
                XCTAssertEqual(state.revision, previous.revision + 1)
                XCTAssertEqual(state.coachConversation?.messages, previous.coachConversation?.messages)
                XCTAssertEqual(state.coachConversation?.checkIn, previous.coachConversation?.checkIn)
                XCTAssertNil(state.coachConversation?.plan)
                XCTAssertNil(state.coachConversation?.proposedProgram)
                XCTAssertEqual(state.workouts, previous.workouts)
                XCTAssertEqual(state.deletedWorkouts, previous.deletedWorkouts)
                XCTAssertEqual(state.trainingProgram, previous.trainingProgram)
                if let oldPlanID {
                    XCTAssertThrowsError(try state.acceptCoachPlan(planID: oldPlanID, now: date(10, 17)))
                } else {
                    XCTAssertThrowsError(try state.acceptProgramProposal(programID: program.id, now: date(10, 17)))
                }
                try state.validate()
            }
        }
    }

    func testNoOpCalendarSaveAndToggleKeepAcceptanceAndRevision() throws {
        var state = try stateWithDraft()
        let previous = state
        try state.saveTrainingCalendar(trainingCalendar, now: date(10, 17))
        XCTAssertEqual(state, previous)
        try state.setCalendarTrainingDay(on: date(10, 18), isTraining: true, now: date(10, 17))
        XCTAssertEqual(state, previous)
    }

    func testRecordedAndPastDayEditsRejectAtomically() throws {
        for active in [false, true] {
            var state = try stateWithCalendar()
            var recorded = completed(id: "recorded", on: date(10, 21, hour: 9))
            if active { recorded.end = nil }
            state.workouts.insert(recorded, at: 0)
            try state.validate()
            let previous = state
            XCTAssertThrowsError(try state.setCalendarTrainingDay(on: date(10, 21), isTraining: false, now: date(10, 21)))
            XCTAssertEqual(state, previous)
            XCTAssertThrowsError(try state.moveCalendarTrainingDay(from: date(10, 21), to: date(10, 22), now: date(10, 21)))
            XCTAssertEqual(state, previous)
            XCTAssertThrowsError(try state.setCalendarTrainingDay(on: date(10, 18), isTraining: false, now: date(10, 21)))
            XCTAssertEqual(state, previous)
            XCTAssertThrowsError(try state.moveCalendarTrainingDay(from: date(10, 24), to: date(10, 20), now: date(10, 21)))
            XCTAssertEqual(state, previous)
        }

        var state = try stateWithCalendar()
        state.workouts.insert(completed(id: "rest-day-workout", on: date(10, 23, hour: 9)), at: 0)
        let previous = state
        XCTAssertThrowsError(try state.moveCalendarTrainingDay(from: date(10, 24), to: date(10, 23), now: date(10, 23)))
        XCTAssertEqual(state, previous)
    }

    func testMoveChangesFutureOpportunityWhilePreservingHistoryAndActualRotation() throws {
        var state = try stateWithCalendar()
        let previous = state
        let nextBefore = state.trainingProgram?.nextSession(history: state.workouts, now: date(10, 17))
        try state.moveCalendarTrainingDay(from: date(10, 18), to: date(10, 19), now: date(10, 17))
        XCTAssertEqual(state.workouts, previous.workouts)
        XCTAssertEqual(state.trainingProgram, previous.trainingProgram)
        XCTAssertEqual(state.trainingProgram?.nextSession(history: state.workouts, now: date(10, 17)), nextBefore)
        let plan = try XCTUnwrap(state.trainingCalendar)
        let entries = plan.entries(program: state.trainingProgram, history: state.workouts, now: date(10, 17))
        XCTAssertNil(entries[1].session)
        XCTAssertEqual(entries[2].session?.id, "lower")
        XCTAssertEqual(entries[4].session?.id, "upper")
        XCTAssertEqual(entries.filter(\.isTraining).count, 27)
        XCTAssertEqual(state.revision, previous.revision + 1)
    }

    func testSavingReplacementCalendarCannotReclassifyRecordedToday() throws {
        var state = try stateWithCalendar()
        state.workouts.insert(completed(id: "today", on: date(10, 17, hour: 9)), at: 0)
        try state.validate()
        let previous = state
        var changed = trainingCalendar
        changed.trainingCycleDays = [1, 2, 5, 8, 9, 10]
        XCTAssertThrowsError(try state.saveTrainingCalendar(changed, now: date(10, 17)))
        XCTAssertEqual(state, previous)
        changed = trainingCalendar
        changed.cycleAnchorDate = date(10, 16, hour: 0)
        // Both are morning/recovery days, but the recorded first morning must not become the second.
        changed.trainingCycleDays = [1, 5, 8, 9, 10]
        XCTAssertEqual(changed.shift(on: date(10, 17)), trainingCalendar.shift(on: date(10, 17)))
        XCTAssertEqual(changed.isTrainingDay(on: date(10, 17)), trainingCalendar.isTrainingDay(on: date(10, 17)))
        XCTAssertThrowsError(try state.saveTrainingCalendar(changed, now: date(10, 17)))
        XCTAssertEqual(state, previous)
    }

    func testNonfiniteEditDatesRejectBeforeCalendarInspection() throws {
        var state = try stateWithDraft()
        let previous = state
        let invalid = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try state.setCalendarTrainingDay(on: invalid, isTraining: true, now: date(10, 17)))
        XCTAssertEqual(state, previous)
        XCTAssertThrowsError(try state.moveCalendarTrainingDay(from: date(10, 18), to: invalid, now: date(10, 17)))
        XCTAssertEqual(state, previous)
        XCTAssertThrowsError(try state.moveCalendarTrainingDay(from: invalid, to: date(10, 19), now: date(10, 17)))
        XCTAssertEqual(state, previous)
    }

    func testStartedBlockRejectsPastReconfigurationButAcceptsOnlyFutureOverrides() throws {
        var state = try stateWithDraft()
        let previous = state
        var changed = trainingCalendar
        changed.trainingCycleDays = [5, 8, 9, 10]
        XCTAssertThrowsError(try state.saveTrainingCalendar(changed, now: date(10, 20)))
        XCTAssertEqual(state, previous)
        changed = trainingCalendar
        changed.cycleAnchorDate = date(10, 18, hour: 0)
        XCTAssertThrowsError(try state.saveTrainingCalendar(changed, now: date(10, 20)))
        XCTAssertEqual(state, previous)
        changed = trainingCalendar
        changed.startDate = date(10, 18, hour: 0)
        XCTAssertThrowsError(try state.saveTrainingCalendar(changed, now: date(10, 20)))
        XCTAssertEqual(state, previous)

        changed = trainingCalendar
        try changed.setTrainingDay(on: date(10, 22), isTraining: true, now: date(10, 20))
        try state.saveTrainingCalendar(changed, now: date(10, 20))
        XCTAssertEqual(state.trainingCalendar, changed)
        XCTAssertEqual(state.revision, previous.revision + 1)
        XCTAssertEqual(state.workouts, previous.workouts)
        for day in trainingCalendar.dates where day < date(10, 20, hour: 0) {
            XCTAssertEqual(state.trainingCalendar?.isTrainingDay(on: day), trainingCalendar.isTrainingDay(on: day))
            XCTAssertEqual(state.trainingCalendar?.shift(on: day), trainingCalendar.shift(on: day))
        }
        XCTAssertNil(state.coachConversation?.plan)
        try state.validate()
    }
}
