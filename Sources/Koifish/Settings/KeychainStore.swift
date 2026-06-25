import Foundation
import Security

/// Stores API keys in the macOS Keychain as generic-password items. Keys never touch
/// disk in plaintext or UserDefaults.
///
/// Primary store is the **data-protection keychain**, which scopes items to this app's
/// signing identity and — unlike the legacy file keychain — never shows the recurring
/// "[App] wants to use your confidential information" prompt when the app reads its own
/// key. Reads transparently fall back to (and migrate) any key still in the legacy
/// keychain, so existing keys keep working; writes fall back to the legacy keychain if
/// the data-protection one is unavailable (e.g. a build without the keychain
/// entitlement), so a key always saves somewhere.
enum KeychainStore {
    private static let service = "sh.koifish.Koifish"
    private static let accessGroup = "sh.koifish.Koifish"

    static func setKey(_ value: String, for provider: ProviderKind) {
        let trimmed = sanitized(value)
        // A blank value means "clear the key", not "store a silently broken one":
        // otherwise hasKey() reports true and the first reply 401s instead of saying
        // "no key set" up front.
        if trimmed.isEmpty {
            deleteKey(for: provider)
            return
        }
        let data = Data(trimmed.utf8)
        // Prefer the prompt-free data-protection keychain; fall back to legacy so a key
        // always saves even on a build that can't use it.
        _ = write(data, for: provider, modern: true) || write(data, for: provider, modern: false)
    }

    static func key(for provider: ProviderKind) -> String? {
        if let value = read(for: provider, modern: true) { return value }
        // Not in the data-protection keychain — check the legacy one and, if found,
        // migrate it across so future reads stop prompting. The legacy copy is left in
        // place (deleting it can itself prompt); the modern copy now wins on read.
        guard let value = read(for: provider, modern: false) else { return nil }
        _ = write(Data(value.utf8), for: provider, modern: true)
        return value
    }

    static func hasKey(for provider: ProviderKind) -> Bool {
        key(for: provider) != nil
    }

    static func deleteKey(for provider: ProviderKind) {
        // Both stores, so a cleared key can't be resurrected from the legacy copy by a
        // later migrating read.
        SecItemDelete(baseQuery(for: provider, modern: true) as CFDictionary)
        SecItemDelete(baseQuery(for: provider, modern: false) as CFDictionary)
    }

    // MARK: Keychain plumbing

    private static func baseQuery(for provider: ProviderKind, modern: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        if modern {
            q[kSecUseDataProtectionKeychain as String] = true
            q[kSecAttrAccessGroup as String] = accessGroup
        }
        return q
    }

    /// Add the item, falling back to update on duplicate. Returns false (so the caller
    /// can fall back to the other store) on a missing-entitlement build or any failure.
    private static func write(_ data: Data, for provider: ProviderKind, modern: Bool) -> Bool {
        var add = baseQuery(for: provider, modern: modern)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecDuplicateItem:
            let update = SecItemUpdate(baseQuery(for: provider, modern: modern) as CFDictionary,
                                       [kSecValueData as String: data] as CFDictionary)
            if update != errSecSuccess { Log.error("Keychain update failed (modern=\(modern)): \(update)") }
            return update == errSecSuccess
        case errSecMissingEntitlement where modern:
            return false  // expected on builds without the keychain entitlement → caller falls back
        default:
            Log.error("Keychain add failed (modern=\(modern)): \(status)")
            return false
        }
    }

    private static func read(for provider: ProviderKind, modern: Bool) -> String? {
        var q = baseQuery(for: provider, modern: modern)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let raw = String(data: data, encoding: .utf8) else { return nil }
        // Clean keys stored before sanitizing existed, so a stray newline can't ride
        // into the auth header and 401 the first reply. All-whitespace reads as no key.
        let trimmed = sanitized(raw)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Strip the copy/paste noise (leading/trailing spaces, a trailing newline) a key
    /// picks up from the clipboard — it would otherwise ride into the `x-api-key` /
    /// `Authorization` header verbatim and turn a correct key into a 401.
    private static func sanitized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
