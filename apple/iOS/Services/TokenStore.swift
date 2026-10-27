import Foundation
import Security
import GymaCore

/// The owner access key lives in the Keychain; the server address in user defaults.
enum TokenStore {
    private static let service = "com.mato.gyma"
    private static let account = "api-token"
    private static let serverKey = "serverURL"

    static var token: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(token: String) throws {
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func clearToken() { SecItemDelete(baseQuery as CFDictionary) }

    static var server: URL {
        get { UserDefaults.standard.string(forKey: serverKey).flatMap { URL(string: $0) } ?? GymAPI.defaultServer }
        set { UserDefaults.standard.set(newValue.absoluteString, forKey: serverKey) }
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
