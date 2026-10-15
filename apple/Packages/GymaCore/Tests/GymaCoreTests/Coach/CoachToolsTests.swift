import XCTest
@testable import GymaCore

final class CoachToolsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-12T12:00:00Z")!
    private let conversation = CoachConversation.programPlanning()

    private func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func call(_ name: String, _ arguments: [String: Any], id: String = "call-1") throws -> [String: Any] {
        ["type": "function_call", "call_id": id, "name": name, "arguments": String(decoding: try data(arguments), as: UTF8.self)]
    }
    private func response(_ output: [[String: Any]]) throws -> Data { try data(["status": "completed", "output": output]) }
    private func finalResponse() throws -> Data {
        let reply: [String: Any] = ["message": "The changes are ready to apply.", "plan": NSNull(), "program": NSNull(), "proposedExercises": []]
        return try response([["type": "message", "content": [["type": "output_text", "text": String(decoding: data(reply), as: UTF8.self)]]]])
    }
    private func query(_ entity: String, ids: [String]? = nil, from: String? = nil, to: String? = nil,
                       offset: Int = 0, limit: Int = 10) -> [String: Any] {
        ["entity": entity, "ids": ids as Any? ?? NSNull(), "exerciseID": NSNull(), "fromDate": from as Any? ?? NSNull(),
         "toDate": to as Any? ?? NSNull(), "offset": offset, "limit": limit]
    }
    private func results(_ session: CoachToolSession) throws -> [[String: Any]] {
        try XCTUnwrap(object(session.requestBody)["input"] as? [[String: Any]])
            .filter { $0["type"] as? String == "function_call_output" }
    }
    private func result(_ session: CoachToolSession) throws -> [String: Any] {
        let text = try XCTUnwrap(results(session).last?["output"] as? String)
        return try object(Data(text.utf8))
    }

    func testToolDefinitionsAreStrictClosedAndCoverEveryOperation() throws {
        func check(_ schema: [String: Any]) throws {
            if schema["type"] as? String == "object" {
                let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
                XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
                XCTAssertEqual(Set(schema["required"] as? [String] ?? []), Set(properties.keys))
                for child in properties.values { try check(child) }
            }
            if let item = schema["items"] as? [String: Any] { try check(item) }
            for child in schema["anyOf"] as? [[String: Any]] ?? [] { try check(child) }
        }
        for tool in CoachTools.definitions {
            XCTAssertEqual(tool["strict"] as? Bool, true)
            try check(XCTUnwrap(tool["parameters"] as? [String: Any]))
        }
        let encoded = String(decoding: try data(CoachTools.definitions), as: UTF8.self)
        for kind in CoachAppChange.Kind.allCases { XCTAssertTrue(encoded.contains("\"\(kind.rawValue)\"")) }
    }

    func testSpecificOldLocalDayReturnsEverySetAndExactIdentity() throws {
        var state = GymaState()
        state.trainingCalendar = .init(startDate: now, cycleAnchorDate: now, timeZone: TimeZone(identifier: "Europe/Amsterdam")!)
        let old = ISO8601DateFormatter().date(from: "2026-06-01T22:30:00Z")!
        state.workouts = [.init(id: "old-workout", start: old, end: old.addingTimeInterval(3600),
                                exercises: [.init(exerciseID: "bench_press", sets: (0..<21).map {
                                    .init(id: "old-set-\($0)", kg: 40, reps: 8, isWarmup: false)
                                })])]
        let payload = try CoachTools.read(data(query("workouts", from: "2026-06-02", to: "2026-06-02")), state: state, now: now)
        let page = try object(Data(payload.utf8))
        XCTAssertEqual(page["totalMatches"] as? Int, 1)
        XCTAssertTrue(payload.contains("old-set-0"))
        XCTAssertTrue(payload.contains("old-set-20"))
        XCTAssertTrue(payload.contains("old-workout"))
        let empty = try CoachTools.read(data(query("workouts", from: "2026-06-01", to: "2026-06-01")), state: state, now: now)
        XCTAssertEqual(try object(Data(empty.utf8))["totalMatches"] as? Int, 0)
    }

    func testPaginationAndDeletedHistoryRemainAccessible() throws {
        var state = GymaState()
        state.deletedWorkouts = (0..<4).map { .init(id: "deleted-\($0)", start: now.addingTimeInterval(Double($0)), end: now.addingTimeInterval(60)) }
        let first = try object(Data(CoachTools.read(data(query("deletedWorkouts", limit: 2)), state: state, now: now).utf8))
        XCTAssertEqual(first["nextOffset"] as? Int, 2)
        XCTAssertEqual(first["totalMatches"] as? Int, 4)
        let last = try object(Data(CoachTools.read(data(query("deletedWorkouts", offset: 2, limit: 2)), state: state, now: now).utf8))
        XCTAssertTrue(last["nextOffset"] is NSNull)
        XCTAssertEqual((last["items"] as? [[String: Any]])?.count, 2)
    }

    func testReadRejectsInvalidDatesNegativePaginationAndUnknownFields() throws {
        var unknown = query("workouts"); unknown["secret"] = true
        var fractional = query("workouts"); fractional["limit"] = 1.5
        var boolean = query("workouts"); boolean["limit"] = true
        for arguments in [query("workouts", from: "2026-02-30"), query("workouts", from: "2026-06-02", to: "2026-06-01"),
                          query("workouts", offset: -1), query("workouts", limit: 31), unknown, fractional, boolean] {
            XCTAssertThrowsError(try CoachTools.read(data(arguments), state: GymaState(), now: now))
        }
    }

    func testEveryCallGetsOutputAndReasoningIsRetainedWithoutSavedStateMutation() throws {
        let state = GymaState()
        var session = try CoachToolSession(conversation: conversation, state: state, now: now)
        let reasoning: [String: Any] = ["type": "reasoning", "id": "reason-1", "summary": [], "encrypted_content": "opaque"]
        XCTAssertNil(try session.consume(response([reasoning, call("read_training_data", query("overview")),
                                                   call("unknown_tool", [:], id: "call-2")])))
        let items = try XCTUnwrap(object(session.requestBody)["input"] as? [[String: Any]])
        XCTAssertEqual(items.first(where: { $0["type"] as? String == "reasoning" })?["encrypted_content"] as? String, "opaque")
        XCTAssertEqual(try results(session).count, 2)
        XCTAssertEqual(try result(session)["status"] as? String, "error")
        XCTAssertNil(state.trainingProgram)
        XCTAssertEqual(state.revision, 0)
    }

    func testChangesArePendingOnlyUntilExplicitApplyAndHaveAppOwnedRevision() throws {
        let state = GymaState()
        var session = try CoachToolSession(conversation: conversation, state: state, now: now)
        let arguments: [String: Any] = ["changes": [["kind": "setRestEnabled", "enabled": false]]]
        XCTAssertNil(try session.consume(response([call("propose_app_changes", arguments)])))
        XCTAssertEqual(try result(session)["status"] as? String, "pending_user_apply")
        let reply = try XCTUnwrap(session.consume(finalResponse()))
        let proposal = try XCTUnwrap(reply.appChanges)
        XCTAssertEqual(proposal.baseStoreID, state.storeID)
        XCTAssertEqual(proposal.baseRevision, state.revision)
        XCTAssertFalse(proposal.summaries.isEmpty)
        XCTAssertTrue(state.restEnabled)
        var accepted = state
        try accepted.applyCoachAppChanges(proposal, now: now)
        XCTAssertFalse(accepted.restEnabled)
    }

    func testInvalidReplacementClearsEarlierPendingBatchAndCanBeRepaired() throws {
        var session = try CoachToolSession(conversation: conversation, state: GymaState(), now: now)
        let valid: [String: Any] = ["changes": [["kind": "setRestEnabled", "enabled": false]]]
        XCTAssertNil(try session.consume(response([call("propose_app_changes", valid)])))
        XCTAssertNotNil(session.appChanges)
        let invalid: [String: Any] = ["changes": [["kind": "deleteProgram", "programID": "unknown"]]]
        XCTAssertNil(try session.consume(response([call("propose_app_changes", invalid, id: "call-2")])))
        XCTAssertNil(session.appChanges)
        XCTAssertEqual(try result(session)["status"] as? String, "error")
        XCTAssertNil(try session.consume(response([call("propose_app_changes", valid, id: "call-3")])))
        XCTAssertNotNil(session.appChanges)
    }

    func testToolLoopIsBoundedAndRequestsFinalReplyWithToolsDisabled() throws {
        var session = try CoachToolSession(conversation: conversation, state: GymaState(), now: now)
        for index in 0..<CoachToolSession.maximumToolRounds {
            XCTAssertNil(try session.consume(response([call("read_training_data", query("overview"), id: "call-\(index)")])))
        }
        XCTAssertEqual(try object(session.requestBody)["tool_choice"] as? String, "none")
        XCTAssertThrowsError(try session.consume(response([call("read_training_data", query("overview"), id: "extra")])))
    }

    func testHiddenProgramExerciseDoesNotBlockChatButCannotEnterNewDraft() throws {
        var state = GymaState()
        let target = ExerciseTarget(sets: 2, repsMin: 6, repsMax: 8)
        state.trainingProgram = .init(title: "Upper", goal: "Strength", sessions: [.init(title: "Upper", exercises: [.init(exerciseID: "bench_press", target: target)])], createdAt: now, updatedAt: now)
        state.hiddenExerciseIDs = ["bench_press"]
        let session = try CoachToolSession(conversation: conversation, state: state, now: now)
        XCTAssertFalse(session.requestBody.isEmpty)
        let catalog = try CoachTools.read(data(query("catalog", ids: ["bench_press"])), state: state, now: now)
        XCTAssertTrue(catalog.contains("\"hidden\":true"))
        let draft: [String: Any] = ["message": "Draft", "plan": ["title": "Upper", "programSessionID": NSNull(), "exercises": [[
            "exerciseID": "bench_press", "sets": 2, "repsMin": 6, "repsMax": 8, "loadKg": NSNull(), "restSeconds": 90, "reason": "Target", "targetEffort": NSNull()
        ]]]]
        let response = try self.response([["type": "message", "content": [["type": "output_text", "text": String(decoding: data(draft), as: UTF8.self)]]]])
        XCTAssertThrowsError(try CoachAPI.parseResponse(response, checkIn: conversation.checkIn, catalog: state.catalog, availableExerciseIDs: Set(state.availableExercises.map(\.id))))
    }

    func testPendingStructuredDraftIsSuppliedAsUnsavedRevisionContext() throws {
        let state = GymaState()
        let pending = CoachAppChangeProposal(baseStoreID: state.storeID, baseRevision: 0, changes: [.init(kind: .setRestEnabled, enabled: false)])
        let session = try CoachToolSession(conversation: conversation, state: state, now: now, pendingAppChanges: pending)
        let input = try XCTUnwrap(object(session.requestBody)["input"] as? [[String: Any]])
        let text = input.compactMap { $0["content"] as? String }.joined()
        XCTAssertTrue(text.contains("NOT been applied"))
        XCTAssertTrue(text.contains("setRestEnabled"))
        XCTAssertNil(session.appChanges)
    }

    func testSetCorrectionAndTargetRemovalSchemasExecute() throws {
        var state = GymaState()
        state.workouts = [.init(id: "workout", start: now.addingTimeInterval(-3600), end: now,
                                exercises: [.init(exerciseID: "bench_press", sets: [.init(id: "set", kg: 40, reps: 8, isWarmup: false)],
                                                  target: .init(sets: 3, repsMin: 8, repsMax: 10))])]
        let batch: [String: Any] = ["changes": [
            ["kind": "correctSet", "workoutID": "workout", "exerciseID": "bench_press", "setID": "set",
             "set": ["id": "set", "kg": 42.5, "reps": 9, "effort": "challenging", "isWarmup": false]],
            ["kind": "setWorkoutTarget", "workoutID": "workout", "exerciseID": "bench_press", "target": NSNull()]
        ]]
        let changes = try CoachTools.decodeChanges(data(batch))
        let proposal = CoachAppChangeProposal(baseStoreID: state.storeID, baseRevision: state.revision, changes: changes)
        let preview = try state.previewCoachAppChanges(proposal, now: now)
        XCTAssertEqual(preview.state.workouts[0].exercises[0].sets[0].kg, 42.5)
        XCTAssertNil(preview.state.workouts[0].exercises[0].target)
    }

    func testComplexProgramProfileCalendarAndExercisePayloadsDecodeAndPreview() throws {
        let state = GymaState()
        let target = ExerciseTarget(sets: 3, repsMin: 8, repsMax: 10, loadKg: 40, targetEffort: .challenging)
        let program = TrainingProgram(id: "new-program", title: "Upper", goal: "Strength", sessions: [
            .init(id: "upper", title: "Upper", exercises: [.init(exerciseID: "my-press", target: target)])
        ], progressionRule: .init(exerciseIncrements: ["my-press": 1.25]), createdAt: now, updatedAt: now)
        var programJSON = try object(Data(CoachTools.json(program).utf8))
        var rule = try XCTUnwrap(programJSON["progressionRule"] as? [String: Any])
        rule["exerciseIncrements"] = [["exerciseID": "my-press", "incrementKg": 1.25]]
        programJSON["progressionRule"] = rule
        let profile = AthleteProfile(primaryGoal: .strength, heightCM: 180, updatedAt: now)
        let calendar = TrainingCalendarPlan(startDate: now, cycleAnchorDate: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        let exercise = ExerciseDefinition(id: "my-press", name: "My press", muscle: .chest, custom: true,
                                          metadata: .init(primaryMuscles: [.chest], equipment: .machines, loadConvention: .machineStack))
        let batch: [String: Any] = ["changes": [
            ["kind": "upsertExercise", "exercise": try object(Data(CoachTools.json(exercise).utf8))],
            ["kind": "replaceProgram", "program": programJSON],
            ["kind": "updateProfile", "profile": try object(Data(CoachTools.json(profile).utf8))],
            ["kind": "configureCalendar", "calendar": try object(Data(CoachTools.json(calendar).utf8))]
        ]]
        let changes = try CoachTools.decodeChanges(data(batch))
        XCTAssertEqual(changes[1].program?.progressionRule.exerciseIncrements["my-press"], 1.25)
        let proposal = CoachAppChangeProposal(baseStoreID: state.storeID, baseRevision: 0, changes: changes)
        let preview = try state.previewCoachAppChanges(proposal, now: now)
        XCTAssertEqual(preview.summaries.count, 4)
        XCTAssertEqual(preview.state.trainingProgram?.sessions[0].exercises[0].exerciseID, "my-press")
        XCTAssertEqual(preview.state.athleteProfile?.heightCM, 180)
        XCTAssertNotNil(preview.state.trainingCalendar)
    }

    func testEmptyCatalogStillAllowsGeneralCoachRequest() throws {
        XCTAssertNoThrow(try CoachAPI.requestBody(conversation: conversation, catalog: [], history: [], now: now))
    }
}
