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

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Add first, fall back to update on duplicate. The create path runs
        // unconditionally on a fresh keychain, so the very first save can't be
        // lost: the old "update, then add on errSecItemNotFound" order silently
        // skipped the add whenever a missing item reported any status other than
        // errSecItemNotFound (e.g. a stale item this signature can't match).
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            if updateStatus != errSecSuccess {
                Log.error("Keychain update failed: \(updateStatus)")
            }
        } else if addStatus != errSecSuccess {
            Log.error("Keychain add failed: \(addStatus)")
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
        guard status == errSecSuccess, let data = item as? Data else { return nil }
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
}
