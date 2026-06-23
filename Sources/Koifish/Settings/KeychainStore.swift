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
                Log.error("Keychain add failed: \(addStatus)")
            }
        } else if status != errSecSuccess {
            Log.error("Keychain update failed: \(status)")
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
