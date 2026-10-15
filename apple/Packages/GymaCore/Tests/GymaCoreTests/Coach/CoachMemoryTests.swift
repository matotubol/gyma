import XCTest
@testable import GymaCore

final class CoachMemoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let catalog = ExerciseCatalog.builtIn
    private var checkIn: SessionCheckIn { .init(shift: .off, energy: .good) }
    private var profile: AthleteProfile {
        .init(primaryGoal: .strength, goalNotes: "PERSISTENT_GOAL_DETAIL", experience: .intermediate,
              daysPerWeek: 3, usualSessionMinutes: 45, scheduleNotes: "PERSISTENT_SHIFT_PATTERN",
              equipment: [.barbell], loadIncrements: [.init(equipment: .barbell, incrementKg: 1.25)],
              ongoingLimitations: "PERSISTENT_RESTRICTION", updatedAt: now)
    }
    private func exercise(_ id: String = "bench_press") -> [String: Any] {
        ["exerciseID": id, "sets": 2, "repsMin": 8, "repsMax": 10, "loadKg": 60,
         "restSeconds": 90, "reason": "Repeat a comparable load", "targetEffort": "challenging"]
    }
    private func programJSON(sessionID: Any = NSNull()) -> [String: Any] {
        ["title": "Stable program", "goal": "Build strength", "rationale": "Repeat and review",
         "sessions": [["sessionID": sessionID, "title": "Full body", "exercises": [exercise()]]],
         "loadIncrementKg": 2.5, "successfulExposuresRequired": 2]
    }
    private func planJSON(exerciseID: String = "bench_press", sessionID: Any = NSNull()) -> [String: Any] {
        ["title": "Repeatable session", "programSessionID": sessionID, "exercises": [exercise(exerciseID)]]
    }
    private func envelope(_ payload: [String: Any]) throws -> Data {
        let text = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
            ["type": "message", "content": [["type": "output_text", "text": text]]]
        ]])
    }
    private func context(_ data: Data) throws -> String {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap((json["input"] as? [[String: String]])?.first?["content"])
    }

    func testProfileAndRelevantOlderTrainingReachBothCoachModesWithoutRawPrivateNotes() throws {
        let conversation = CoachConversation(checkIn: checkIn, messages: [.init(role: .user, content: "Review my squat progress.")])
        let recent: [Workout] = (0..<6).map { index in
            Workout(id: "recent-\(index)", start: now.addingTimeInterval(-Double(index + 1) * 86400 - 3600), end: now.addingTimeInterval(-Double(index + 1) * 86400),
                    exercises: [.init(exerciseID: "bench_press", sets: [.init(kg: 40, reps: 8, effort: .challenging, isWarmup: false)])])
        }
        let old = Workout(id: "OLDER_SQUAT_EXPOSURE", start: now.addingTimeInterval(-20 * 86400 - 3600), end: now.addingTimeInterval(-20 * 86400),
                          checkIn: .init(shift: .off, energy: .good, notes: "PRIVATE_OLD_CHAT_NOTE"),
                          exercises: [.init(exerciseID: "squat", sets: [.init(kg: 73.25, reps: 8, isWarmup: false)])])
        let history = recent + [old]
        let planning = try context(CoachAPI.requestBody(conversation: conversation, catalog: catalog, history: history, profile: profile, now: now))
        let active = Workout(id: "active", start: now, coachConversation: .init(messages: [.init(role: .user, content: "How is my squat going?")]),
                             exercises: [.init(exerciseID: "squat")])
        let during = try context(WorkoutCoachAPI.requestBody(workout: active, storeID: "store", revision: 1, restTimer: nil,
                                                             catalog: catalog, history: history, now: now, profile: profile))
        for text in [planning, during] {
            for fact in ["PERSISTENT_GOAL_DETAIL", "PERSISTENT_SHIFT_PATTERN", "PERSISTENT_RESTRICTION", "OLDER_SQUAT_EXPOSURE", "73.25"] {
                XCTAssertTrue(text.contains(fact), "Missing \(fact)")
            }
            XCTAssertFalse(text.contains("PRIVATE_OLD_CHAT_NOTE"))
            XCTAssertTrue(text.contains("unknownEffortSets"))
        }
    }

    func testBodyweightContextIsBoundedWithoutChangingSavedHistory() throws {
        var value = profile
        value.bodyweightHistory = (0..<101).map { index in
            .init(id: "measurement-\(index)-end", recordedAt: now.addingTimeInterval(Double(index - 101) * 86400), kg: 80)
        }
        let text = try CoachContext.text(profile: value, program: nil, history: [], catalog: catalog, now: now)
        XCTAssertTrue(text.contains("measurement-100-end"))
        XCTAssertTrue(text.contains("measurement-11-end"))
        XCTAssertFalse(text.contains("measurement-10-end"))
        XCTAssertFalse(text.contains("measurement-0-end"))
        XCTAssertEqual(value.bodyweightHistory.count, 101)
    }

    func testNewProgramUsesAppIdentitiesAndProfileLoadIncrements() throws {
        var proposal = programJSON()
        proposal["id"] = "UNTRUSTED_MODEL_ID"
        proposal["revision"] = 500
        let reply = try CoachAPI.parseResponse(envelope(["message": "Review this recurring program", "plan": NSNull(), "program": proposal]),
                                              checkIn: checkIn, catalog: catalog, now: now, profile: profile)
        let parsed = try XCTUnwrap(reply.program)
        XCTAssertNil(reply.plan)
        XCTAssertNotEqual(parsed.id, "UNTRUSTED_MODEL_ID")
        XCTAssertFalse(parsed.id.isEmpty)
        XCTAssertEqual(parsed.revision, 1)
        XCTAssertEqual(parsed.createdAt, now)
        XCTAssertFalse(try XCTUnwrap(parsed.sessions.first?.id).isEmpty)
        XCTAssertEqual(parsed.progressionRule.exerciseIncrements["bench_press"], 1.25)
        XCTAssertEqual(parsed.sessions.first?.exercises.first?.target?.targetEffort, .challenging)
        try parsed.validate(catalog: catalog)
    }

    func testProgramRevisionPreservesKnownSessionIdentityAndRejectsInventedIdentity() throws {
        let existing = TrainingProgram(id: "saved-program", title: "Original", goal: "Strength", sessions: [
            .init(id: "retained-session", title: "Full body", exercises: [.init(exerciseID: "bench_press", target: .init(sets: 2, repsMin: 8, repsMax: 10))])
        ], revision: 3, createdAt: now.addingTimeInterval(-86400), updatedAt: now.addingTimeInterval(-86400))
        let data = try envelope(["message": "Revised program", "plan": NSNull(), "program": programJSON(sessionID: "retained-session")])
        let revised = try XCTUnwrap(CoachAPI.parseResponse(data, checkIn: checkIn, catalog: catalog, now: now, existingProgram: existing).program)
        XCTAssertEqual(revised.id, existing.id)
        XCTAssertEqual(revised.revision, 4)
        XCTAssertEqual(revised.createdAt, existing.createdAt)
        XCTAssertEqual(revised.sessions[0].id, "retained-session")
        let invented = try envelope(["message": "Revised", "plan": NSNull(), "program": programJSON(sessionID: "invented")])
        XCTAssertThrowsError(try CoachAPI.parseResponse(invented, checkIn: checkIn, catalog: catalog, now: now, existingProgram: existing))
        let invalidLink = try envelope(["message": "Session", "plan": planJSON(sessionID: "invented"), "program": NSNull()])
        XCTAssertThrowsError(try CoachAPI.parseResponse(invalidLink, checkIn: checkIn, catalog: catalog, now: now, existingProgram: existing))
        let validLink = try envelope(["message": "Session", "plan": planJSON(sessionID: "retained-session"), "program": NSNull()])
        let plan = try XCTUnwrap(CoachAPI.parseResponse(validLink, checkIn: checkIn, catalog: catalog, now: now, existingProgram: existing).plan)
        XCTAssertEqual(plan.programID, existing.id)
        XCTAssertEqual(plan.programRevision, 3)
        XCTAssertEqual(plan.programSessionID, "retained-session")
        XCTAssertNil(plan.acceptedAt)
    }

    func testMutuallyExclusiveProgramAndPlanAndDuplicateProgramSessionsAreRejected() throws {
        let both = try envelope(["message": "Two proposals", "plan": planJSON(), "program": programJSON()])
        XCTAssertThrowsError(try CoachAPI.parseResponse(both, checkIn: checkIn, catalog: catalog, now: now))
        let existing = TrainingProgram(id: "program", title: "Existing", goal: "Strength", sessions: [
            .init(id: "one", title: "One", exercises: [.init(exerciseID: "bench_press", target: .init(sets: 2, repsMin: 8, repsMax: 10))])
        ], createdAt: now, updatedAt: now)
        var duplicate = programJSON(sessionID: "one")
        let session = try XCTUnwrap((duplicate["sessions"] as? [[String: Any]])?.first)
        duplicate["sessions"] = [session, session]
        let data = try envelope(["message": "Duplicate", "plan": NSNull(), "program": duplicate])
        XCTAssertThrowsError(try CoachAPI.parseResponse(data, checkIn: checkIn, catalog: catalog, now: now, existingProgram: existing))
    }

    func testProfileExclusionsAreEnforcedForPlansProgramsAndLiveChanges() throws {
        var noBarbell = profile; noBarbell.equipment = [.dumbbells]; noBarbell.loadIncrements = []
        var avoided = profile; avoided.avoidedExercises = [" Bench press "]
        for value in [noBarbell, avoided] {
            let plan = try envelope(["message": "Bench", "plan": planJSON(), "program": NSNull()])
            let recurring = try envelope(["message": "Bench", "plan": NSNull(), "program": programJSON()])
            XCTAssertThrowsError(try CoachAPI.parseResponse(plan, checkIn: checkIn, catalog: catalog, now: now, profile: value))
            XCTAssertThrowsError(try CoachAPI.parseResponse(recurring, checkIn: checkIn, catalog: catalog, now: now, profile: value))
            let active = Workout(id: "active", start: now, exercises: [.init(exerciseID: "bench_press")])
            var change = exercise(); change["replacementExerciseID"] = NSNull()
            XCTAssertThrowsError(try WorkoutCoachAPI.parseResponse(envelope(["message": "Change", "change": change]), workout: active,
                                                                   storeID: "store", revision: 0, catalog: catalog, profile: value))
        }
    }

    func testTimedCustomExercisesCannotEnterRepetitionBasedPlanOrLiveChange() throws {
        let timed = ExerciseDefinition(id: "custom_hold", name: "Custom hold", muscle: .core, custom: true,
                                       metadata: .init(primaryMuscles: [.abdominals], equipment: .bodyweight, measurement: .seconds))
        let extended = catalog + [timed]
        let plan = try envelope(["message": "Hold", "plan": planJSON(exerciseID: timed.id), "program": NSNull()])
        XCTAssertThrowsError(try CoachAPI.parseResponse(plan, checkIn: checkIn, catalog: extended, now: now))
        let active = Workout(id: "active", start: now, exercises: [.init(exerciseID: "bench_press")])
        var change = exercise(); change["replacementExerciseID"] = timed.id
        XCTAssertThrowsError(try WorkoutCoachAPI.parseResponse(envelope(["message": "Swap", "change": change]), workout: active,
                                                               storeID: "store", revision: 0, catalog: extended))
    }

    func testCompletedWorkoutRequestAllowsReviewResponseButRejectsChanges() throws {
        let completed = Workout(id: "completed", start: now.addingTimeInterval(-3600), end: now,
                                coachConversation: .init(messages: [.init(role: .user, content: "Review my workout")]),
                                exercises: [.init(exerciseID: "bench_press", sets: [.init(kg: 60, reps: 8, isWarmup: false)])])
        let text = try context(WorkoutCoachAPI.requestBody(workout: completed, storeID: "store", revision: 0, restTimer: nil,
                                                         catalog: catalog, history: [completed], now: now, profile: profile))
        XCTAssertTrue(text.contains("COMPLETED"))
        XCTAssertTrue(text.contains("PERSISTENT_RESTRICTION"))
        let advice = try WorkoutCoachAPI.parseResponse(envelope(["message": "Effort was missing; record it next session.", "change": NSNull()]),
                                                       workout: completed, storeID: "store", revision: 0, catalog: catalog)
        XCTAssertNil(advice.change)
        var change = exercise(); change["replacementExerciseID"] = NSNull()
        XCTAssertThrowsError(try WorkoutCoachAPI.parseResponse(envelope(["message": "Change the target", "change": change]), workout: completed,
                                                               storeID: "store", revision: 0, catalog: catalog))
    }

    func testSelectedHistoricalWorkoutKeepsItsReviewFeedbackAndProgramWithoutUnrelatedTimer() throws {
        let oldTarget = ExerciseTarget(sets: 2, repsMin: 8, repsMax: 10, loadKg: 60, targetEffort: .challenging)
        let oldProgram = TrainingProgram(id: "continuous-program", title: "HISTORICAL_PROGRAM_TEMPLATE", goal: "Strength", sessions: [
            .init(id: "session", title: "Original session", exercises: [.init(exerciseID: "bench_press", target: oldTarget)])
        ], createdAt: now.addingTimeInterval(-30 * 86400), updatedAt: now.addingTimeInterval(-25 * 86400))
        var currentProgram = oldProgram
        currentProgram.revision = 2; currentProgram.title = "Current program"; currentProgram.updatedAt = now
        let selected = Workout(id: "selected-old-workout", start: now.addingTimeInterval(-20 * 86400 - 3600), end: now.addingTimeInterval(-20 * 86400),
                               coachConversation: .init(messages: [.init(role: .user, content: "Explain this workout")]),
                               exercises: [.init(exerciseID: "bench_press", sets: [.init(kg: 60, reps: 8, effort: .challenging, isWarmup: false)], target: oldTarget)],
                               programID: oldProgram.id, programSessionID: "session", programRevision: 1)
        let newer: [Workout] = (0..<8).map { index in
            Workout(id: "newer-\(index)", start: now.addingTimeInterval(-Double(index + 1) * 86400 - 3600), end: now.addingTimeInterval(-Double(index + 1) * 86400),
                    exercises: [.init(exerciseID: "bench_press", sets: [.init(kg: 60, reps: 8, isWarmup: false)], target: oldTarget)],
                    programID: currentProgram.id, programSessionID: "session", programRevision: 2)
        }
        let history = newer + [selected]
        var oldReview = WorkoutReview.make(workout: selected, history: history, program: oldProgram, catalog: catalog, now: selected.end!)
        oldReview.summary = "SELECTED_REVIEW_OUTSIDE_RECENT_WINDOW"
        let reviews = newer.map { WorkoutReview.make(workout: $0, history: history, program: currentProgram, catalog: catalog, now: $0.end!) } + [oldReview]
        let feedback = newer.map { WorkoutFeedback(workoutID: $0.id, recordedAt: $0.end!, note: "Recent feedback") } + [
            WorkoutFeedback(workoutID: selected.id, recordedAt: selected.end!, note: "SELECTED_FEEDBACK_OUTSIDE_RECENT_WINDOW", painNote: "SELECTED_PAIN_DETAIL")
        ]
        let unrelatedTimer = RestTimer(id: "UNRELATED_TIMER_ID", workoutID: "another-live-workout", exerciseID: "squat", startedAt: now,
                                       endsAt: now.addingTimeInterval(120), sourceSetID: "unrelated-set")
        let text = try context(WorkoutCoachAPI.requestBody(workout: selected, storeID: "store", revision: 0, restTimer: unrelatedTimer,
                                                         catalog: catalog, history: history, now: now, program: currentProgram,
                                                         reviews: reviews, feedback: feedback, priorPrograms: [oldProgram]))
        XCTAssertTrue(text.contains("SELECTED_REVIEW_OUTSIDE_RECENT_WINDOW"))
        XCTAssertTrue(text.contains("SELECTED_FEEDBACK_OUTSIDE_RECENT_WINDOW"))
        XCTAssertTrue(text.contains("SELECTED_PAIN_DETAIL"))
        XCTAssertTrue(text.contains("HISTORICAL_PROGRAM_TEMPLATE"))
        XCTAssertFalse(text.contains("UNRELATED_TIMER_ID"))
        XCTAssertFalse(text.contains("another-live-workout"))
        XCTAssertTrue(text.contains("COMPLETED"))
    }
}
