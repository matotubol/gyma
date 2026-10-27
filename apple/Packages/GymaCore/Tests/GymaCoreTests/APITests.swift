import XCTest
@testable import GymaCore

final class APITests: XCTestCase {
    private let api = GymAPI(server: URL(string: "https://example.workers.dev/")!, token: "secret")

    func testBuildsAuthenticatedRequests() throws {
        let request = try api.makeRequest("GET", "/exercises", query: ["q": "cable + rope", "limit": "20"])
        XCTAssertEqual(request.url?.absoluteString, "https://example.workers.dev/api/v1/exercises?limit=20&q=cable%20%2B%20rope")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertNil(request.value(forHTTPHeaderField: "Origin"))
    }

    func testSendsExplicitNulls() throws {
        let clear = try api.makeRequest("PUT", "/calendar/days/2026-10-27/workout", body: SaveWorkoutPlan(kind: nil, expectedVersion: 4, exercises: []))
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(clear.httpBody)) as? [String: Any]
        XCTAssertTrue(body?["kind"] is NSNull)
        XCTAssertEqual(body?["expectedVersion"] as? Int, 4)

        let create = try api.makeRequest("POST", "/exercises", body: CreateExercise(name: "Squat", equipment: .barbell, brand: .matrix))
        let created = try JSONSerialization.jsonObject(with: XCTUnwrap(create.httpBody)) as? [String: Any]
        XCTAssertTrue(created?["brand"] is NSNull, "Only machines and cables carry a brand")
    }

    func testDecodesEnvelopeAndNullData() throws {
        let none: WorkoutSession? = try GymAPI.decode(Data(#"{"data":null}"#.utf8), status: 200)
        XCTAssertNil(none)
        let plan: WorkoutPlan = try GymAPI.decode(Data(#"""
        {"data":{"date":"2026-10-27","kind":"training","version":2,"updatedAt":"2026-10-26T09:00:00.000Z",
          "exercises":[{"exerciseId":"0123456789abcdef0123456789abcdef","name":"Face Pull","equipment":"cable","brand":"Matrix","sets":3,"reps":12,"plannedKg":22.5}]}}
        """#.utf8), status: 200)
        XCTAssertEqual(plan.exercises.first?.brand, .matrix)
        XCTAssertEqual(plan.kind, .training)
    }

    func testDecodesErrors() {
        XCTAssertThrowsError(try GymAPI.decode(Data(#"{"error":{"code":"CONFLICT","message":"This workout changed.","requestId":"x"}}"#.utf8), status: 409) as Ignored) { error in
            let failure = error as? APIError
            XCTAssertEqual(failure?.isConflict, true)
            XCTAssertEqual(failure?.code, "CONFLICT")
            XCTAssertEqual(failure?.message, "This workout changed.")
        }
    }

    func testEntityIDsMatchServerPattern() {
        XCTAssertNotNil(newEntityID().range(of: "^[a-f0-9]{32}$", options: .regularExpression))
    }

    func testRoundsKilogramsToHundredths() {
        XCTAssertEqual(PlannedExerciseInput(exerciseId: "x", sets: 3, reps: 8, plannedKg: 82.499999).plannedKg, 82.5)
    }
}
