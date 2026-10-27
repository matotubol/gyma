import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct APIError: Error, LocalizedError, Sendable {
    public let status: Int
    public let code: String?
    public let message: String

    public var errorDescription: String? { message }
    public var isUnauthorized: Bool { status == 401 }
    public var isConflict: Bool { status == 409 }
}

/// Client for the gym-web Worker (`/api/v1`). Authenticates with the owner bearer token,
/// which the Worker accepts for every operation without browser cookies or an Origin header.
public struct GymAPI: Sendable {
    public static let defaultServer = URL(string: "https://gym-api.matotubol.workers.dev")!

    public let server: URL
    let token: String
    let session: URLSession

    public init(server: URL, token: String, session: URLSession = .shared) {
        self.server = server; self.token = token; self.session = session
    }

    // MARK: System

    /// Authenticated readiness check. Throws `APIError` 401 for a wrong key.
    public func status() async throws {
        let _: Ignored = try await send("GET", "/status")
    }

    // MARK: Calendar and plans

    public func days(month: String) async throws -> [CalendarDay] {
        try await send("GET", "/calendar/days", query: ["month": month])
    }

    public func plan(date: String) async throws -> WorkoutPlan {
        try await send("GET", "/calendar/days/\(date)/workout")
    }

    public func savePlan(date: String, _ plan: SaveWorkoutPlan) async throws -> WorkoutPlan {
        try await send("PUT", "/calendar/days/\(date)/workout", body: plan)
    }

    // MARK: Exercise library

    public func searchExercises(_ query: String, limit: Int = 20, offset: Int = 0) async throws -> [LibraryExercise] {
        try await send("GET", "/exercises", query: ["q": query, "limit": String(limit), "offset": String(offset)])
    }

    public func createExercise(_ exercise: CreateExercise) async throws -> LibraryExercise {
        try await send("POST", "/exercises", body: exercise)
    }

    public func progress(exerciseId: String, limit: Int = 100) async throws -> ExerciseProgress {
        try await send("GET", "/exercises/\(exerciseId)/progress", query: ["limit": String(limit)])
    }

    public func history(exerciseId: String, before date: String) async throws -> ExerciseHistory? {
        try await send("GET", "/exercises/\(exerciseId)/history", query: ["before": date])
    }

    // MARK: Performed workout

    public func session(date: String) async throws -> WorkoutSession? {
        try await send("GET", sessionPath(date))
    }

    public func startSession(date: String, planVersion: Int) async throws -> WorkoutSession {
        try await send("POST", sessionPath(date), body: StartSessionBody(expectedPlanVersion: planVersion))
    }

    public func startSet(date: String, setId: String, position: Int, version: Int) async throws -> WorkoutSession {
        try await send("POST", sessionPath(date) + "/sets/start", body: StartSetBody(setId: setId, exercisePosition: position, expectedVersion: version))
    }

    public func confirmSet(date: String, setId: String, kg: Double, reps: Int, version: Int) async throws -> WorkoutSession {
        try await send("POST", sessionPath(date) + "/sets/\(setId)/confirm", body: ConfirmSetBody(actualKg: roundKg(kg), actualReps: reps, expectedVersion: version))
    }

    public func cancelSet(date: String, setId: String, version: Int) async throws -> WorkoutSession {
        try await send("POST", sessionPath(date) + "/sets/\(setId)/cancel", body: VersionBody(expectedVersion: version))
    }

    public func finish(date: String, version: Int) async throws -> WorkoutSession {
        try await send("POST", sessionPath(date) + "/finish", body: VersionBody(expectedVersion: version))
    }

    public func reopen(date: String, version: Int) async throws -> WorkoutSession {
        try await send("POST", sessionPath(date) + "/reopen", body: VersionBody(expectedVersion: version))
    }

    public func addExercise(date: String, entryId: String, targets: ExerciseTargets, version: Int) async throws -> WorkoutSession {
        try await send("POST", sessionPath(date) + "/exercises", body: AddExerciseBody(
            exerciseId: targets.exerciseId, plannedSets: targets.plannedSets, plannedReps: targets.plannedReps,
            plannedKg: targets.plannedKg, expectedVersion: version, entryId: entryId))
    }

    public func editExercise(date: String, position: Int, targets: ExerciseTargets, allowReassign: Bool, version: Int) async throws -> WorkoutSession {
        try await send("PUT", sessionPath(date) + "/exercises/\(position)", body: EditExerciseBody(
            exerciseId: targets.exerciseId, plannedSets: targets.plannedSets, plannedReps: targets.plannedReps,
            plannedKg: targets.plannedKg, expectedVersion: version, allowReassign: allowReassign))
    }

    public func removeExercise(date: String, position: Int, version: Int) async throws -> WorkoutSession {
        try await send("POST", sessionPath(date) + "/exercises/\(position)/remove", body: VersionBody(expectedVersion: version))
    }

    public func logSet(date: String, setId: String, position: Int, kg: Double, reps: Int, version: Int) async throws -> WorkoutSession {
        try await send("POST", sessionPath(date) + "/sets/log", body: LogSetBody(
            actualKg: roundKg(kg), actualReps: reps, expectedVersion: version, setId: setId, exercisePosition: position))
    }

    public func editSet(date: String, setId: String, kg: Double, reps: Int, version: Int) async throws -> WorkoutSession {
        try await send("PATCH", sessionPath(date) + "/sets/\(setId)", body: ConfirmSetBody(actualKg: roundKg(kg), actualReps: reps, expectedVersion: version))
    }

    public func removeSet(date: String, setId: String, version: Int) async throws -> WorkoutSession {
        try await send("POST", sessionPath(date) + "/sets/\(setId)/remove", body: VersionBody(expectedVersion: version))
    }

    // MARK: Transport

    private func sessionPath(_ date: String) -> String { "/calendar/days/\(date)/session" }

    func makeRequest(_ method: String, _ path: String, query: [String: String] = [:], body: (any Encodable)? = nil) throws -> URLRequest {
        let root = server.absoluteString.hasSuffix("/") ? String(server.absoluteString.dropLast()) : server.absoluteString
        guard var components = URLComponents(string: root + "/api/v1" + path) else { throw URLError(.badURL) }
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            // URLComponents leaves "+" alone, but the server decodes it as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    func send<Response: Decodable>(_ method: String, _ path: String, query: [String: String] = [:], body: (any Encodable)? = nil) async throws -> Response {
        let request = try makeRequest(method, path, query: query, body: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try Self.decode(data, status: status)
    }

    static func decode<Response: Decodable>(_ data: Data, status: Int) throws -> Response {
        guard (200..<300).contains(status) else {
            let failure = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw APIError(status: status, code: failure?.error.code, message: failure?.error.message ?? "Something went wrong. Please try again.")
        }
        return try JSONDecoder().decode(Envelope<Response>.self, from: data).data
    }
}

struct Envelope<Value: Decodable>: Decodable { let data: Value }
struct ErrorEnvelope: Decodable {
    struct Body: Decodable { let code: String; let message: String }
    let error: Body
}
struct Ignored: Decodable { init(from decoder: Decoder) throws {} }
