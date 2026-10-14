import Foundation
import GymaCore

enum OpenAICoachService {
    static let model = CoachAPI.model

    static func reply(conversation: CoachConversation, state: GymaState, apiKey: String,
                      pendingAppChanges: CoachAppChangeProposal? = nil) async throws -> CoachReply {
        var session = try CoachToolSession(conversation: conversation, state: state, pendingAppChanges: pendingAppChanges)
        do {
            for _ in 0...CoachToolSession.maximumToolRounds {
                try Task.checkCancellation()
                let data = try await request(body: session.requestBody, apiKey: apiKey)
                if let reply = try session.consume(data) { return reply }
            }
            throw GymaError.invalid("The coach reached its lookup limit. Ask about fewer changes at once.")
        }
        catch is CancellationError { throw CancellationError() }
        catch let error as GymaError { throw error }
        catch { throw unreadableReply }
    }

    static func workoutReply(workout: Workout, storeID: String, revision: Int, restTimer: RestTimer?,
                             state: GymaState, apiKey: String) async throws -> WorkoutCoachReply {
        let body = try WorkoutCoachAPI.requestBody(workout: workout, storeID: storeID, revision: revision,
                                                  restTimer: restTimer, catalog: state.catalog, history: state.workouts,
                                                  profile: state.athleteProfile, program: state.trainingProgram,
                                                  reviews: state.workoutReviews ?? [], feedback: state.workoutFeedback ?? [], priorPrograms: state.programHistory ?? [], trainingCalendar: state.trainingCalendar,
                                                  trainingCalendarHistory: state.trainingCalendarHistory ?? [])
        let data = try await request(body: body, apiKey: apiKey)
        do { return try WorkoutCoachAPI.parseResponse(data, workout: workout, storeID: storeID, revision: revision, catalog: state.catalog, profile: state.athleteProfile) }
        catch let error as GymaError { throw error }
        catch { throw unreadableReply }
    }

    private static var unreadableReply: GymaError {
        .invalid("The coach reply could not be read. Your saved workout is unchanged. Try again.")
    }

    private static func request(body: Data, apiKey: String) async throws -> Data {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GymaError.invalid("Add your OpenAI API key in Settings to talk with the coach.") }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        // Ephemeral networking keeps API responses and authorization out of on-disk URL caches.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw GymaError.invalid("The coach could not connect. Try again.") }
        switch response.statusCode {
        case 200...299: break
        case 401: throw GymaError.invalid("OpenAI did not accept the API key. Update it in Settings.")
        case 403, 404: throw GymaError.invalid("This API project cannot use GPT-6.1 Sol. Check your OpenAI project’s model access.")
        case 429: throw GymaError.invalid("OpenAI's usage or rate limit was reached. Check your API billing or try again later.")
        default: throw GymaError.invalid("The coach request failed (HTTP \(response.statusCode)). Your saved workout is unchanged. Try again.")
        }
        return data
    }
}
