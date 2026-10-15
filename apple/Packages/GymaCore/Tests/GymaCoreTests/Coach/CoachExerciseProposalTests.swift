import XCTest
@testable import GymaCore

final class CoachExerciseProposalTests: XCTestCase {
    private let catalog = ExerciseCatalog.builtIn
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var checkIn: SessionCheckIn { .init(shift: .off, energy: .good) }
    private var addition: [String: Any] {
        ["name": "Chest-supported plate-loaded row", "muscle": "back", "primaryMuscles": ["upperBack", "lats"],
         "secondaryMuscles": ["biceps", "rearDelts"], "equipment": "machines", "measurement": "repetitions",
         "loadConvention": "unknown", "explanation": "Sit with your chest against the pad and pull the handles toward you. Keep this plate-loaded machine separate from the cable row; confirm how its load is recorded."]
    }
    private var program: TrainingProgram {
        .init(id: "program", title: "Recurring upper", goal: "Build strength", sessions: [
            .init(id: "upper", title: "Upper", exercises: [
                .init(exerciseID: "bench_press", target: .init(sets: 3, repsMin: 6, repsMax: 10))
            ])
        ], createdAt: now, updatedAt: now)
    }
    private func response(_ body: [String: Any]) throws -> Data {
        let content = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
            ["type": "message", "content": [["type": "output_text", "text": content]]]
        ]])
    }
    private func reply(_ additions: [[String: Any]]) throws -> CoachReply {
        try CoachAPI.parseResponse(response(["message": "Review these exercise entries before I continue your program.",
                                            "plan": NSNull(), "program": NSNull(), "proposedExercises": additions]),
                                   checkIn: checkIn, catalog: catalog, isProgramPlanning: true)
    }
    private func stateWithProposal() throws -> GymaState {
        var state = GymaState()
        state.trainingProgram = program
        state.trainingCalendar = .init(startDate: now, cycleAnchorDate: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        var conversation = CoachConversation.programPlanning(existingProgram: program)
        let parsed = try reply([addition])
        conversation.messages.append(.init(role: .assistant, content: parsed.message))
        conversation.proposedExercises = parsed.proposedExercises
        try state.saveCoachConversation(conversation)
        return state
    }

    func testCoachProposesAppOwnedExerciseIdentityAndUnknownLoadMeaningWithoutSavingIt() throws {
        var item = addition
        item["id"] = "bench_press"
        item["exerciseID"] = "model-chosen-id"
        item["custom"] = false
        let parsed = try reply([item])
        let proposal = try XCTUnwrap(parsed.proposedExercises.first)
        XCTAssertEqual(proposal.id, proposal.exercise.id)
        XCTAssertTrue(proposal.id.hasPrefix("custom_"))
        XCTAssertNotEqual(proposal.id, "bench_press")
        XCTAssertNotEqual(proposal.id, "model-chosen-id")
        XCTAssertNotEqual(proposal.id, try XCTUnwrap(reply([item]).proposedExercises.first).id)
        XCTAssertTrue(proposal.exercise.custom)
        XCTAssertEqual(proposal.exercise.metadata?.loadConvention, .unknown)
        XCTAssertEqual(proposal.exercise.metadata?.equipment, .machines)
        XCTAssertNil(parsed.plan)
        XCTAssertNil(parsed.program)
        XCTAssertFalse(GymaState().catalog.contains { $0.id == proposal.id })
    }

    func testMalformedDuplicateAndTimedExerciseSuggestionsAreRejected() throws {
        var duplicate = addition; duplicate["name"] = "  BENCH   PRESS \n"
        var timed = addition; timed["measurement"] = "seconds"
        var unsupportedEquipment = addition; unsupportedEquipment["equipment"] = "madeUpMachine"
        var noMuscles = addition; noMuscles["primaryMuscles"] = [String]()
        var overlap = addition; overlap["secondaryMuscles"] = ["lats"]
        var duplicateMuscle = addition; duplicateMuscle["primaryMuscles"] = ["lats", "lats"]
        var noName = addition; noName["name"] = " \n "
        var noExplanation = addition; noExplanation["explanation"] = " \n "
        var longName = addition; longName["name"] = String(repeating: "x", count: 201)
        for item in [duplicate, timed, unsupportedEquipment, noMuscles, overlap, duplicateMuscle, noName, noExplanation, longName] {
            XCTAssertThrowsError(try reply([item]))
        }
        XCTAssertThrowsError(try reply([addition, addition]))
        let tooMany = (0..<7).map { index -> [String: Any] in
            var item = addition; item["name"] = "Identified machine variant \(index)"; return item
        }
        XCTAssertThrowsError(try reply(tooMany))
    }

    func testExerciseAdditionsCannotAlsoProposeAWorkoutOrProgram() throws {
        let target: [String: Any] = ["exerciseID": "bench_press", "sets": 3, "repsMin": 6, "repsMax": 10,
                                     "loadKg": NSNull(), "restSeconds": 90, "reason": "Start conservatively."]
        let workout: [String: Any] = ["title": "Upper", "exercises": [target]]
        let recurring: [String: Any] = ["title": "Upper", "goal": "Build strength", "rationale": "Repeatable sessions",
                                        "loadIncrementKg": 2.5, "successfulExposuresRequired": 2,
                                        "sessions": [["title": "Upper", "sessionID": NSNull(), "exercises": [target]]]]
        for pair in [(workout as Any, NSNull() as Any), (NSNull() as Any, recurring as Any)] {
            let data = try response(["message": "Review", "plan": pair.0, "program": pair.1, "proposedExercises": [addition]])
            XCTAssertThrowsError(try CoachAPI.parseResponse(data, checkIn: checkIn, catalog: catalog))
        }
    }

    func testAcceptedEntriesPersistWithOriginalIDsAndBecomeAvailableToNextCoachRequest() throws {
        var state = try stateWithProposal()
        let proposals = try XCTUnwrap(state.coachConversation?.proposedExercises)
        let existingProgram = state.trainingProgram
        let existingCalendar = state.trainingCalendar
        let originalCatalog = state.catalog
        try state.acceptCoachExerciseProposals(proposals)
        XCTAssertEqual(state.customExercises, proposals.map(\.exercise))
        XCTAssertEqual(Array(state.catalog.prefix(originalCatalog.count)), originalCatalog)
        XCTAssertEqual(state.trainingProgram, existingProgram)
        XCTAssertEqual(state.trainingCalendar, existingCalendar)
        XCTAssertTrue(state.workouts.isEmpty)
        XCTAssertNil(state.coachConversation?.proposedExercises)
        XCTAssertNil(state.coachConversation?.proposedProgram)
        XCTAssertNil(state.coachConversation?.plan)
        XCTAssertNil(state.coachConversation?.acceptedProgramID)
        XCTAssertEqual(state.coachConversation?.messages.last?.role, .user)
        XCTAssertTrue(state.coachConversation?.messages.last?.content.contains(proposals[0].id) == true)
        XCTAssertEqual(try NativeBackup.decode(NativeBackup.encode(state)), state)
        let request = try CoachAPI.requestBody(conversation: XCTUnwrap(state.coachConversation), catalog: state.catalog,
                                               history: [], program: state.trainingProgram, now: now, trainingCalendar: state.trainingCalendar)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request) as? [String: Any])
        let text = try XCTUnwrap((body["input"] as? [[String: String]])?.first?["content"])
        XCTAssertTrue(text.contains(proposals[0].id))
        let format = try XCTUnwrap((body["text"] as? [String: Any])?["format"] as? [String: Any])
        let schemaText = String(decoding: try JSONSerialization.data(withJSONObject: XCTUnwrap(format["schema"])), as: UTF8.self)
        XCTAssertTrue(schemaText.contains(proposals[0].id))
        let accepted = state
        XCTAssertThrowsError(try state.acceptCoachExerciseProposals(proposals))
        XCTAssertEqual(state, accepted)
    }

    func testAcceptanceRejectsStaleEditedOrInvalidProposalWithoutPartialLibraryChanges() throws {
        var state = try stateWithProposal()
        var edited = try XCTUnwrap(state.coachConversation?.proposedExercises)
        edited[0].explanation = "A different movement description"
        var before = state
        XCTAssertThrowsError(try state.acceptCoachExerciseProposals(edited))
        XCTAssertEqual(state, before)
        let pending = try XCTUnwrap(state.coachConversation?.proposedExercises)
        state.coachConversation?.messages.append(.init(role: .user, content: "That is not the machine I meant."))
        before = state
        XCTAssertThrowsError(try state.acceptCoachExerciseProposals(pending))
        XCTAssertEqual(state, before)

        state = try stateWithProposal()
        var invalid = try XCTUnwrap(state.coachConversation?.proposedExercises)
        var second = invalid[0]
        second.exercise.id = "custom_second"
        invalid.append(second)
        state.coachConversation?.proposedExercises = invalid
        before = state
        XCTAssertThrowsError(try state.acceptCoachExerciseProposals(invalid))
        XCTAssertEqual(state, before)
        XCTAssertTrue(state.customExercises.isEmpty)
    }

    func testManualLibraryAdditionClearsStaleSuggestionsAndDistinctVariantsStaySeparate() throws {
        var state = try stateWithProposal()
        let sameName = try XCTUnwrap(state.coachConversation?.proposedExercises?.first?.exercise)
        var manuallySaved = sameName
        manuallySaved.id = "custom_manual"
        try state.addCustomExercise(manuallySaved)
        XCTAssertNil(state.coachConversation?.proposedExercises)
        XCTAssertNoThrow(try state.validate())

        var otherVariant = addition
        otherVariant["name"] = "Chest-supported cable row"
        otherVariant["equipment"] = "cables"
        otherVariant["loadConvention"] = "machineStack"
        let variants = try reply([addition, otherVariant]).proposedExercises
        XCTAssertEqual(variants.count, 2)
        XCTAssertNotEqual(variants[0].id, variants[1].id)
        XCTAssertNotEqual(variants[0].exercise.metadata?.equipment, variants[1].exercise.metadata?.equipment)
    }

    func testPendingProposalsRoundTripAndLegacyResponsesAndConversationsRemainValid() throws {
        let state = try stateWithProposal()
        XCTAssertEqual(try NativeBackup.decode(NativeBackup.encode(state)), state)
        let legacyResponse = try response(["message": "What equipment is available?", "plan": NSNull()])
        XCTAssertTrue(try CoachAPI.parseResponse(legacyResponse, checkIn: checkIn, catalog: catalog).proposedExercises.isEmpty)
        let legacy = CoachConversation(checkIn: checkIn)
        let restored = try JSONDecoder().decode(CoachConversation.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(restored.proposedExercises)
        XCTAssertNoThrow(try restored.validate(catalog: catalog))
        var mixed = try XCTUnwrap(state.coachConversation)
        mixed.proposedProgram = program
        XCTAssertThrowsError(try mixed.validate(catalog: catalog))
    }

    func testRequestIncludesBoundedExerciseProposalSchemaAndClarificationInstructions() throws {
        let data = try CoachAPI.requestBody(conversation: .programPlanning(), catalog: catalog, history: [])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let instructions = try XCTUnwrap(body["instructions"] as? String)
        XCTAssertTrue(instructions.contains("do not need to know exercise names"))
        XCTAssertTrue(instructions.contains("never invent a machine model"))
        XCTAssertTrue(instructions.contains("Use an existing catalog ID"))
        let format = try XCTUnwrap((body["text"] as? [String: Any])?["format"] as? [String: Any])
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let additions = try XCTUnwrap(properties["proposedExercises"] as? [String: Any])
        XCTAssertEqual(additions["maxItems"] as? Int, 6)
        let item = try XCTUnwrap(additions["items"] as? [String: Any])
        let fields = try XCTUnwrap(item["properties"] as? [String: Any])
        XCTAssertNil(fields["id"])
        XCTAssertNil(fields["exerciseID"])
        XCTAssertEqual((fields["measurement"] as? [String: Any])?["enum"] as? [String], ["repetitions"])
    }
}
