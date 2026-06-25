import Foundation
import Security

/// Stores API keys in the macOS login Keychain as generic-password items.
/// Keys never touch disk in plaintext or UserDefaults.
enum KeychainStore {
    private static let service = "sh.koifish.Koifish"

    static func setKey(_ value: String, for provider: ProviderKind) {
        let account = provider.rawValue
        if value.isEmpty {
            deleteKey(for: provider)
            return
        }
        let data = Data(value.utf8)

        // Update if present, else add.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                Log.error("Couldn't save the \(provider.displayName) API key to Keychain — \(reason(addStatus))")
            }
        } else if status != errSecSuccess {
            Log.error("Couldn't update the \(provider.displayName) API key in Keychain — \(reason(status))")
        }
    }

    static func key(for provider: ProviderKind) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        // No key stored yet is the normal case for a fresh install — stay quiet.
        if status == errSecItemNotFound { return nil }
        // Any other failure means a key the user *did* set is now unreadable
        // (Keychain locked, access denied, item corrupt…). Without a message,
        // callers just see "no key" and blame the user. Name the real reason.
        guard status == errSecSuccess, let data = item as? Data else {
            Log.error("Couldn't read the \(provider.displayName) API key from Keychain — \(reason(status)). It's stored but unreadable, so requests will fail until this clears.")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func hasKey(for provider: ProviderKind) -> Bool {
        (key(for: provider)?.isEmpty == false)
    }

    static func deleteKey(for provider: ProviderKind) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Turn a Keychain OSStatus into a human-readable reason, e.g.
    /// "User interaction is not allowed. (-25308)". Falls back to the raw
    /// code when the system has no message for it.
    private static func reason(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(message) (\(status))"
        }
        return "OSStatus \(status)"
    }
}
