import XCTest
@testable import GymaCore

final class CoachAPITests: XCTestCase {
    private let checkIn = SessionCheckIn(shift: .off, energy: .good)
    private let catalog = ExerciseCatalog.builtIn

    private func response(_ proposal: [String: Any], status: String = "completed") throws -> Data {
        let text = String(decoding: try JSONSerialization.data(withJSONObject: proposal), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["status": status, "output": [
            ["type": "reasoning", "summary": []],
            ["type": "message", "content": [["type": "output_text", "text": text]]]
        ]])
    }
    private var exercise: [String: Any] {
        ["exerciseID": "bench_press", "sets": 3, "repsMin": 8, "repsMax": 10,
         "loadKg": NSNull(), "restSeconds": 90, "reason": "Review your working load."]
    }

    func testStructuredPlanCreatesUnacceptedAppOwnedIdentityAndTargets() throws {
        let data = try response(["message": "Here is your draft.", "plan": ["title": "Upper body", "exercises": [exercise]]])
        let reply = try CoachAPI.parseResponse(data, checkIn: checkIn, catalog: catalog)
        let plan = try XCTUnwrap(reply.plan)
        XCTAssertEqual(plan.exercises.first?.target?.restSeconds, 90)
        XCTAssertNil(plan.exercises.first?.target?.loadKg)
        XCTAssertEqual(plan.checkIn, checkIn)
        XCTAssertNil(plan.acceptedAt)
        XCTAssertFalse(plan.id.isEmpty)
        XCTAssertTrue(plan.exercises.allSatisfy { $0.sets.isEmpty })
    }

    func testCoachCanAskQuestionWithoutFabricatingPlan() throws {
        let reply = try CoachAPI.parseResponse(response(["message": "What equipment do you have?", "plan": NSNull()]), checkIn: checkIn, catalog: catalog)
        XCTAssertNil(reply.plan)
        XCTAssertEqual(reply.message, "What equipment do you have?")
    }

    func testMalformedIncompleteRefusedAndInvalidPlansCannotBeAccepted() throws {
        var unknown = exercise; unknown["exerciseID"] = "not-in-library"
        var invalidRest = exercise; invalidRest["restSeconds"] = 0
        var invalidRange = exercise; invalidRange["repsMax"] = 2
        for entries in [[unknown], [invalidRest], [invalidRange], [exercise, exercise], []] {
            let data = try response(["message": "Draft", "plan": ["title": "Session", "exercises": entries]])
            XCTAssertThrowsError(try CoachAPI.parseResponse(data, checkIn: checkIn, catalog: catalog))
        }
        XCTAssertThrowsError(try CoachAPI.parseResponse(Data("invalid".utf8), checkIn: checkIn, catalog: catalog))
        XCTAssertThrowsError(try CoachAPI.parseResponse(response(["message": "Draft", "plan": NSNull()], status: "incomplete"), checkIn: checkIn, catalog: catalog))
        let refusal = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "content": [["type": "refusal", "refusal": "No"]]]]])
        XCTAssertThrowsError(try CoachAPI.parseResponse(refusal, checkIn: checkIn, catalog: catalog))
    }

    func testRequestUsesLunaSchemaAndBoundedContextWithoutPrivateHistoryNotes() throws {
        let messages = (0..<50).map { CoachMessage(role: .user, content: "Question \($0)") }
        let conversation = CoachConversation(checkIn: checkIn, messages: messages)
        let privateCheckIn = SessionCheckIn(shift: .off, energy: .good, notes: "OLD_PRIVATE_NOTE")
        let history = (0..<12).map { index in
            Workout(id: "history-\(index)", start: Date(timeIntervalSince1970: Double(index)), end: Date(), checkIn: privateCheckIn,
                    exercises: [.init(exerciseID: "bench_press", sets: [.init(kg: 40, reps: 8, isWarmup: false)])])
        }
        let data = try CoachAPI.requestBody(conversation: conversation, catalog: catalog, history: history)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(body["store"] as? Bool, false)
        let input = try XCTUnwrap(body["input"] as? [[String: String]])
        XCTAssertEqual(input.count, 41)
        XCTAssertEqual(input[1]["content"], "Question 10")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("OLD_PRIVATE_NOTE"))
        let format = try XCTUnwrap((body["text"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
    }
}
