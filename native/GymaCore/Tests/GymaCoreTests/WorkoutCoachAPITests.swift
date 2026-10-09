import XCTest
@testable import GymaCore

final class WorkoutCoachAPITests: XCTestCase {
    private let catalog = ExerciseCatalog.builtIn
    private let date = Date(timeIntervalSince1970: 1_780_000_000)
    private var workout: Workout {
        var soreness = Soreness.allNone; soreness[.legs] = .high
        return Workout(id: "active", start: date, energy: .medium,
                       checkIn: .init(shift: .off, energy: .great, notes: "CURRENT_CHECK_IN"),
                       readiness: .init(energy: .medium, soreness: soreness, recordedAt: date),
                       coachConversation: .init(messages: [.init(role: .user, content: "Adjust my load.")]),
                       exercises: [.init(exerciseID: "bench_press", sets: [.init(id: "set", kg: 40, reps: 7, effort: .challenging, isWarmup: false)],
                                          target: .init(sets: 3, repsMin: 8, repsMax: 10, loadKg: 40))])
    }
    private var change: [String: Any] {
        ["exerciseID": "bench_press", "replacementExerciseID": NSNull(), "sets": 3, "repsMin": 6,
         "repsMax": 8, "loadKg": 35, "restSeconds": 120, "reason": "Use a manageable load for the remaining sets."]
    }
    private func response(_ change: Any = NSNull(), message: String = "Here is a suggestion.", status: String = "completed") throws -> Data {
        let text = String(decoding: try JSONSerialization.data(withJSONObject: ["message": message, "change": change]), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["status": status, "output": [
            ["type": "reasoning", "summary": []], ["type": "message", "content": [["type": "output_text", "text": text]]]
        ]])
    }

    func testReplyUsesAppOwnedContextAndAdviceNeedsNoChange() throws {
        let reply = try WorkoutCoachAPI.parseResponse(response(change), workout: workout, storeID: "store", revision: 7, catalog: catalog)
        let proposal = try XCTUnwrap(reply.change)
        XCTAssertEqual(proposal.workoutID, "active")
        XCTAssertEqual(proposal.storeID, "store")
        XCTAssertEqual(proposal.basedOnRevision, 7)
        XCTAssertFalse(proposal.id.isEmpty)
        XCTAssertEqual(proposal.target.loadKg, 35)
        XCTAssertEqual(proposal.target.restSeconds, 120)
        XCTAssertNil(proposal.replacementExerciseID)
        let advice = try WorkoutCoachAPI.parseResponse(response(message: "You completed seven reps at 40kg."), workout: workout, storeID: "store", revision: 7, catalog: catalog)
        XCTAssertNil(advice.change)
    }

    func testMalformedIncompleteRefusedAndUnsafeChangesAreRejected() throws {
        var unknown = change; unknown["exerciseID"] = "unknown"
        var overwrite = change; overwrite["replacementExerciseID"] = "squat"
        var invalidRange = change; invalidRange["repsMax"] = 2
        var belowCompleted = change; belowCompleted["sets"] = 1
        var invalidRest = change; invalidRest["restSeconds"] = 0
        for item in [unknown, overwrite, invalidRange, belowCompleted, invalidRest] {
            XCTAssertThrowsError(try WorkoutCoachAPI.parseResponse(response(item), workout: workout, storeID: "store", revision: 7, catalog: catalog))
        }
        XCTAssertThrowsError(try WorkoutCoachAPI.parseResponse(Data("no JSON".utf8), workout: workout, storeID: "store", revision: 7, catalog: catalog))
        XCTAssertThrowsError(try WorkoutCoachAPI.parseResponse(response(status: "incomplete"), workout: workout, storeID: "store", revision: 7, catalog: catalog))
        XCTAssertThrowsError(try WorkoutCoachAPI.parseResponse(response(message: " "), workout: workout, storeID: "store", revision: 7, catalog: catalog))
        let refusal = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "content": [["type": "refusal"]]]]])
        XCTAssertThrowsError(try WorkoutCoachAPI.parseResponse(refusal, workout: workout, storeID: "store", revision: 7, catalog: catalog))
    }

    func testRequestIncludesLiveActualsSeparateReadinessAndBoundedHistory() throws {
        var active = workout
        active.coachConversation = .init(messages: (0..<50).map { .init(role: .user, content: "Question \($0)") })
        var previous = workout
        previous.id = "previous"; previous.end = date.addingTimeInterval(200)
        previous.checkIn?.notes = "PRIVATE_HISTORY_NOTE"
        previous.coachConversation = .init(messages: [.init(role: .user, content: "PRIVATE_HISTORY_CHAT")])
        let timer = RestTimer(workoutID: active.id, exerciseID: "bench_press", startedAt: date.addingTimeInterval(30),
                              endsAt: date.addingTimeInterval(120), sourceSetID: "set", plannedSeconds: 90)
        let data = try WorkoutCoachAPI.requestBody(workout: active, storeID: "store", revision: 7, restTimer: timer,
                                                   catalog: catalog, history: [previous], now: date.addingTimeInterval(60))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gpt-6.1-sol")
        XCTAssertEqual(body["store"] as? Bool, false)
        let input = try XCTUnwrap(body["input"] as? [[String: String]])
        XCTAssertEqual(input.count, 41)
        XCTAssertEqual(input[1]["content"], "Question 10")
        let context = try XCTUnwrap(input.first?["content"])
        for value in ["recentActualSets", "workingSetCount", "readiness", "soreness", "high", "CURRENT_CHECK_IN", "restTimer", "challenging"] {
            XCTAssertTrue(context.contains(value), "Missing live context: \(value)")
        }
        XCTAssertFalse(context.contains("PRIVATE_HISTORY_NOTE"))
        XCTAssertFalse(context.contains("PRIVATE_HISTORY_CHAT"))
        let format = try XCTUnwrap((body["text"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertEqual(format["type"] as? String, "json_schema")
    }

    func testPlanningHistoryIncludesActualReadinessWithoutInventingLegacyReadiness() throws {
        var measured = workout; measured.end = date.addingTimeInterval(200)
        var legacy = measured; legacy.id = "legacy"; legacy.start = date.addingTimeInterval(-86400); legacy.readiness = nil
        let json = try CoachAPI.historyContext([measured, legacy])
        let history = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let readiness = try XCTUnwrap(history[0]["readiness"] as? [String: Any])
        XCTAssertEqual(readiness["energy"] as? String, "medium")
        XCTAssertEqual((readiness["soreness"] as? [String: String])?["legs"], "high")
        XCTAssertNil(history[1]["readiness"])
        let exercises = try XCTUnwrap(history[0]["exercises"] as? [[String: Any]])
        XCTAssertEqual(exercises[0]["workingSetCount"] as? Int, 1)
        XCTAssertNotNil(exercises[0]["target"])
        XCTAssertNotNil(exercises[0]["sets"])
    }
}
