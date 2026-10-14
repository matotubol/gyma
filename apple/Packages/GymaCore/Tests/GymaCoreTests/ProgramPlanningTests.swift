import XCTest
@testable import GymaCore

final class ProgramPlanningTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let catalog = ExerciseCatalog.builtIn
    private var checkIn: SessionCheckIn { .init(shift: .night, energy: .good, timeMinutes: 60) }
    private var target: ExerciseTarget {
        .init(sets: 3, repsMin: 6, repsMax: 10, loadKg: 60, restSeconds: 90, targetEffort: .challenging)
    }
    private var program: TrainingProgram {
        .init(id: "recurring-program", title: "Upper / lower", goal: "Build strength", sessions: [
            .init(id: "upper", title: "Upper", exercises: [.init(exerciseID: "bench_press", target: target)]),
            .init(id: "lower", title: "Lower", exercises: [.init(exerciseID: "squat", target: target)])
        ], createdAt: now.addingTimeInterval(-86400), updatedAt: now)
    }
    private var exercise: [String: Any] {
        ["exerciseID": "bench_press", "sets": 3, "repsMin": 6, "repsMax": 10,
         "loadKg": 60, "restSeconds": 90, "reason": "Use a comfortable working load.", "targetEffort": "challenging"]
    }
    private func response(_ proposal: [String: Any]) throws -> Data {
        let content = String(decoding: try JSONSerialization.data(withJSONObject: proposal), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
            ["type": "message", "content": [["type": "output_text", "text": content]]]
        ]])
    }
    private func planningState() throws -> GymaState {
        var state = GymaState()
        state.trainingCalendar = .init(startDate: now, cycleAnchorDate: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        var conversation = CoachConversation.programPlanning()
        conversation.proposedProgram = program
        try state.saveCoachConversation(conversation)
        return state
    }

    func testLegacyConversationAndBackupKeepDailyCheckInBehavior() throws {
        var state = GymaState()
        let plan = WorkoutPlan(title: "Today's workout", exercises: program.sessions[0].exercises, checkIn: checkIn, createdAt: now)
        state.coachConversation = .init(checkIn: checkIn, plan: plan)
        let encoded = try NativeBackup.encode(state)
        let restored = try NativeBackup.decode(encoded)
        XCTAssertNil(restored.coachConversation?.purpose)
        XCTAssertFalse(try XCTUnwrap(restored.coachConversation).isProgramPlanning)
        XCTAssertEqual(restored.coachConversation?.plan, plan)
        let request = try CoachAPI.requestBody(conversation: XCTUnwrap(restored.coachConversation), catalog: catalog, history: [])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request) as? [String: Any])
        XCTAssertTrue((body["input"] as? [[String: String]])?.first?["content"]?.contains("Current check-in:") == true)
    }

    func testProgramRequestNeverSendsPlaceholderReadinessAndRestrictsResponseToPrograms() throws {
        var conversation = CoachConversation.programPlanning(existingProgram: program)
        conversation.checkIn = .init(shift: .night, energy: .poor, timeMinutes: 10, sleepHours: 2,
                                     notes: "PLACEHOLDER_NOT_REPORTED", painNote: "PLACEHOLDER_PAIN_NOT_REPORTED", soreness: [.legs: .high])
        let profile = AthleteProfile(goalNotes: "CONFIRMED_LONG_TERM_GOAL", usualSessionMinutes: 90, updatedAt: now)
        let calendar = TrainingCalendarPlan(startDate: now, cycleAnchorDate: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        let data = try CoachAPI.requestBody(conversation: conversation, catalog: catalog, history: [], profile: profile,
                                           program: program, now: now, trainingCalendar: calendar)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let context = try XCTUnwrap((body["input"] as? [[String: String]])?.first?["content"])
        XCTAssertFalse(context.contains("Current check-in:"))
        XCTAssertFalse(context.contains("Current proposed plan:"))
        XCTAssertFalse(context.contains("PLACEHOLDER_NOT_REPORTED"))
        XCTAssertFalse(context.contains("PLACEHOLDER_PAIN_NOT_REPORTED"))
        XCTAssertTrue(context.contains("CONFIRMED_LONG_TERM_GOAL"))
        XCTAssertTrue(context.contains("recurring-program"))
        XCTAssertTrue(context.contains("5 sessions per 10 days, NOT per week"))
        let instructions = try XCTUnwrap(body["instructions"] as? String)
        XCTAssertTrue(instructions.contains("do not ask for today's energy, sleep, soreness or readiness"))
        XCTAssertTrue(instructions.contains("Even if an accepted program exists"))
        let format = try XCTUnwrap((body["text"] as? [String: Any])?["format"] as? [String: Any])
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual((properties["plan"] as? [String: Any])?["type"] as? String, "null")
        XCTAssertNotNil((properties["program"] as? [String: Any])?["anyOf"])
    }

    func testProgramResponseRejectsDailyWorkoutsButAllowsProfileQuestionsAndProgramRevisions() throws {
        let workout = try response(["message": "Today's plan", "plan": ["title": "Upper", "exercises": [exercise]], "program": NSNull()])
        XCTAssertThrowsError(try CoachAPI.parseResponse(workout, checkIn: checkIn, catalog: catalog, isProgramPlanning: true))
        XCTAssertNotNil(try CoachAPI.parseResponse(workout, checkIn: checkIn, catalog: catalog).plan)
        let question = try response(["message": "Which equipment is available?", "plan": NSNull(), "program": NSNull()])
        let questionReply = try CoachAPI.parseResponse(question, checkIn: checkIn, catalog: catalog, isProgramPlanning: true)
        XCTAssertNil(questionReply.plan)
        XCTAssertNil(questionReply.program)
        let proposal = try response(["message": "Review this recurring program.", "plan": NSNull(), "program": [
            "id": "model-cannot-set-identity", "revision": 999, "title": "Recurring upper", "goal": "Build strength",
            "rationale": "Repeat the main lifts and progress from recorded training.", "loadIncrementKg": 2.5,
            "successfulExposuresRequired": 2,
            "sessions": [["sessionID": "upper", "title": "Upper", "exercises": [exercise]]]
        ]])
        let revision = try CoachAPI.parseResponse(proposal, checkIn: checkIn, catalog: catalog, now: now,
                                                 existingProgram: program, isProgramPlanning: true)
        XCTAssertNil(revision.plan)
        XCTAssertEqual(revision.program?.id, program.id)
        XCTAssertEqual(revision.program?.revision, program.revision + 1)
        XCTAssertEqual(revision.program?.sessions[0].id, "upper")
    }

    func testProgramAcceptancePopulatesCalendarWithoutCreatingOrStartingDailyWorkout() throws {
        var state = try planningState()
        // Even these compatibility values cannot shorten the template or create today's prescription.
        state.coachConversation?.checkIn = .init(shift: .off, energy: .poor, timeMinutes: 10,
                                                 painNote: "NOT_REPORTED_READINESS", soreness: [.chest: .high])
        let savedCalendar = state.trainingCalendar
        try state.acceptProgramProposal(programID: program.id, now: now)
        XCTAssertEqual(state.trainingProgram, program)
        XCTAssertEqual(state.trainingCalendar, savedCalendar)
        XCTAssertEqual(state.coachConversation?.acceptedProgramID, program.id)
        XCTAssertNil(state.coachConversation?.proposedProgram)
        XCTAssertNil(state.coachConversation?.plan)
        XCTAssertNil(state.coachConversation?.startedWorkoutID)
        XCTAssertTrue(state.workouts.isEmpty)
        let entries = try XCTUnwrap(state.trainingCalendar).entries(program: state.trainingProgram, history: state.workouts, now: now)
        XCTAssertEqual(Array(entries.filter(\.isTraining).prefix(4).compactMap { $0.session?.id }), ["upper", "lower", "upper", "lower"])
        let restored = try NativeBackup.decode(NativeBackup.encode(state))
        XCTAssertEqual(restored, state)
        XCTAssertTrue(restored.coachConversation?.isProgramPlanning == true)
    }

    func testFreshDailyCheckInAdjustsSessionWithoutChangingAcceptedProgram() throws {
        var state = try planningState()
        try state.acceptProgramProposal(programID: program.id, now: now)
        let saved = state.trainingProgram
        let readiness = SessionCheckIn(shift: .morning, energy: .poor, timeMinutes: 15, painNote: "New discomfort today")
        let dailyPlan = try state.nextProgramPlan(checkIn: readiness, now: now.addingTimeInterval(86400))
        XCTAssertEqual(dailyPlan.checkIn, readiness)
        XCTAssertNil(dailyPlan.exercises[0].target?.loadKg)
        XCTAssertTrue(dailyPlan.exercises[0].target?.reason.contains("Readiness needs review today") == true)
        XCTAssertEqual(state.trainingProgram, saved)
        XCTAssertNil(state.coachConversation?.plan)
        XCTAssertTrue(state.workouts.isEmpty)
    }

    func testProgramAcceptanceStillRejectsEquipmentConflictsWithoutPartialMutation() throws {
        var state = try planningState()
        state.athleteProfile = .init(equipment: [.barbell], loadIncrements: [.init(equipment: .barbell, incrementKg: 5)], updatedAt: now)
        let original = state
        XCTAssertThrowsError(try state.acceptProgramProposal(programID: program.id, now: now))
        XCTAssertEqual(state, original)
        state.athleteProfile = .init(equipment: [.dumbbells], updatedAt: now)
        let incompatible = state
        XCTAssertThrowsError(try state.acceptProgramProposal(programID: program.id, now: now))
        XCTAssertEqual(state, incompatible)
    }

    func testProgramConversationCannotContainDailyPlanOrStartedWorkout() throws {
        var conversation = CoachConversation.programPlanning()
        conversation.plan = .init(title: "Today", exercises: program.sessions[0].exercises, checkIn: conversation.checkIn, createdAt: now)
        XCTAssertThrowsError(try conversation.validate(catalog: catalog))
        conversation.plan = nil
        conversation.startedWorkoutID = "workout"
        XCTAssertThrowsError(try conversation.validate(catalog: catalog))
        conversation.startedWorkoutID = nil
        XCTAssertNoThrow(try conversation.validate(catalog: catalog))
        conversation.acceptedProgramID = program.id
        conversation.proposedProgram = program
        XCTAssertThrowsError(try conversation.validate(catalog: catalog))
    }
}
