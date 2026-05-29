import Foundation
import Security

// MARK: - KeychainClient

/// Thin wrapper around SecItem* that stores OAuth and API key credentials in iCloud Keychain.
/// kSecAttrSynchronizable = true means tokens sync across all devices signed into the same Apple ID.
enum KeychainClient {
    enum TokenKey: String {
        case accessToken  = "access"
        case refreshToken = "refresh"
        case expiresAt    = "expires"   // stored as Unix timestamp string
        case apiKey       = "api_key"
    }

    private static let service = "com.lyra.basn.oauth"

    // MARK: - Save / Load / Delete

    static func save(_ value: String, toolID: String, key: TokenKey) throws {
        let account = "\(toolID)_\(key.rawValue)"
        let data = Data(value.utf8)

        var query = baseQuery(account: account)

        let existing = SecItemCopyMatching(query as CFDictionary, nil)
        if existing == errSecSuccess {
            let update: [CFString: Any] = [
                kSecValueData: data,
                kSecAttrSynchronizable: kCFBooleanTrue!,
            ]
            let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if status != errSecSuccess {
                throw KeychainError.updateFailed(status)
            }
        } else {
            query[kSecValueData] = data
            let status = SecItemAdd(query as CFDictionary, nil)
            if status != errSecSuccess {
                throw KeychainError.saveFailed(status)
            }
        }
    }

    static func load(toolID: String, key: TokenKey) -> String? {
        var query = baseQuery(account: "\(toolID)_\(key.rawValue)")
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(toolID: String, key: TokenKey) {
        let query = baseQuery(account: "\(toolID)_\(key.rawValue)")
        SecItemDelete(query as CFDictionary)
    }

    /// Deletes all keychain items for a given tool (call on disconnect).
    static func deleteAll(toolID: String) {
        for key in TokenKey.allCases {
            delete(toolID: toolID, key: key)
        }
    }

    // MARK: - Expiry Helpers

    static func saveExpiry(_ date: Date, toolID: String) throws {
        try save(String(date.timeIntervalSince1970), toolID: toolID, key: .expiresAt)
    }

    static func loadExpiry(toolID: String) -> Date? {
        guard let raw = load(toolID: toolID, key: .expiresAt),
              let ts = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    // MARK: - Private

    private static func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass:               kSecClassGenericPassword,
            kSecAttrService:         service,
            kSecAttrAccount:         account,
            kSecAttrSynchronizable:  kCFBooleanTrue!,
            kSecAttrAccessible:      kSecAttrAccessibleAfterFirstUnlock,
        ]
    }

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        case updateFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let s):   return "Keychain save failed: \(s)"
            case .updateFailed(let s): return "Keychain update failed: \(s)"
            }
        }
    }
}

extension KeychainClient.TokenKey: CaseIterable {}
