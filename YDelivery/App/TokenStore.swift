import Foundation
import Security

/// Keychain-backed storage for the one credential this app holds — the Yandex Delivery
/// OAuth token (`Design` → "The token lives in the Keychain").
///
/// `kSecClassGenericPassword`, accessible after first unlock so a future
/// `BGAppRefreshTask` can read it, and deliberately **not** synchronized to iCloud: the
/// token authorizes spending money and belongs to this device's owner, not to every device
/// on the Apple Account.
///
/// `nonisolated`: the project defaults new types onto the main actor
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION`), but this store has no UI affinity — the Keychain is
/// thread-safe, and background refresh will need to read it off the main actor.
nonisolated struct TokenStore: Sendable {
    /// Distinct per environment so previews and tests never touch the real credential.
    var service = "com.learnable.YDelivery.auth-token"

    struct UnexpectedStatus: Error {
        let status: OSStatus
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "oauth-token",
        ]
    }

    /// The stored token, or `nil` when none was saved. A read failure other than
    /// `errSecItemNotFound` also returns `nil`: on the read path an unreachable credential
    /// and an absent one both mean "not signed in".
    func read() -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces any stored token. Writing throws rather than degrading silently — a sign-in
    /// that did not persist is a state the user must see (CLAUDE.md rule 3).
    func write(_ token: String) throws {
        try delete()
        var attributes = query
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw UnexpectedStatus(status: status) }
    }

    /// Removes the stored token. Absence is success: deleting what is not there is the
    /// state the caller wanted.
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw UnexpectedStatus(status: status)
        }
    }
}
