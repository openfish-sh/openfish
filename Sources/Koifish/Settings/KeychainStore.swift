import Foundation
import Security

/// Stores API keys in the macOS login Keychain as generic-password items.
/// Keys never touch disk in plaintext or UserDefaults.
enum KeychainStore {
    private static let service = "sh.koifish.Koifish"

    static func setKey(_ value: String, for provider: ProviderKind) {
        let account = provider.rawValue
        let trimmed = sanitized(value)
        // A blank (or whitespace-only) value means "clear the key", not "store a
        // silently broken one": otherwise hasKey() would report true and the first
        // reply 401s instead of honestly saying "no key set" up front.
        if trimmed.isEmpty {
            deleteKey(for: provider)
            return
        }
        let data = Data(trimmed.utf8)

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
        guard status == errSecSuccess, let data = item as? Data,
              let raw = String(data: data, encoding: .utf8) else { return nil }
        // Clean keys stored before sanitizing existed (or written by any other path),
        // so a stray newline can't ride into the auth header and 401 the first reply.
        // A value that's all whitespace reads as no key — keeping hasKey() honest.
        let trimmed = sanitized(raw)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Strip the copy/paste noise (leading/trailing spaces, a trailing newline) a key
    /// picks up from the clipboard. Such noise would ride into the `x-api-key` /
    /// `Authorization` header verbatim and turn a correct key into a 401 on the first
    /// reply, so it's cleaned at the store boundary regardless of which caller wrote it.
    private static func sanitized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
