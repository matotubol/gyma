import Foundation
import Security
import GymaCore

enum OpenAICoachService {
    static let model = CoachAPI.model

    static func reply(conversation: CoachConversation, catalog: [ExerciseDefinition], history: [Workout], apiKey: String) async throws -> CoachReply {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GymaError.invalid("Add your OpenAI API key in Settings to talk with the coach.") }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try CoachAPI.requestBody(conversation: conversation, catalog: catalog, history: history)
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
        case 403, 404: throw GymaError.invalid("This API project cannot use GPT Luna. Check your OpenAI project’s model access.")
        case 429: throw GymaError.invalid("OpenAI's usage or rate limit was reached. Check your API billing or try again later.")
        default: throw GymaError.invalid("The coach request failed (HTTP \(response.statusCode)). Your saved plan is unchanged. Try again.")
        }
        do { return try CoachAPI.parseResponse(data, checkIn: conversation.checkIn, catalog: catalog) }
        catch let error as GymaError { throw error }
        catch { throw GymaError.invalid("The coach reply could not be read. Your saved plan is unchanged. Try again.") }
    }
}

/// Personal, user-supplied API credential. Never included in workouts, backups or Watch snapshots.
enum CoachCredentials {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.mato.gyma.openai",
         kSecAttrAccount as String: "personal-api-key"]
    }

    static func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw credentialError }
        return key
    }

    static func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 1000, !trimmed.contains(where: \.isWhitespace) else {
            throw GymaError.invalid("Enter a valid OpenAI API key without spaces.")
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(trimmed.utf8),
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes) { _, value in value } as CFDictionary, nil)
            guard added == errSecSuccess else { throw credentialError }
        } else if status != errSecSuccess { throw credentialError }
    }

    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw credentialError }
    }

    private static var credentialError: GymaError { .invalid("The API key could not be accessed securely. Unlock your iPhone and try again.") }
}
