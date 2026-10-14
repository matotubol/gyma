import Foundation
import Security
import GymaCore

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
