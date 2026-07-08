import Foundation
import Security

// ---------------------------------------------------------------------------
// Keychain wrapper
//
// I token JWT DEVONO essere salvati nel Keychain, mai in UserDefaults.
// Il Keychain è cifrato e non accessibile da altri processi o app.
// ---------------------------------------------------------------------------

struct KeychainService {

    // MARK: - Save

    /// Salva (o sovrascrive) un valore nel Keychain per la chiave specificata.
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Elimina eventuali voci precedenti con la stessa chiave
        delete(key: key)

        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.karttiming",
            kSecAttrAccount as String: key,
            kSecValueData   as String: data,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Load

    /// Legge il valore associato alla chiave dal Keychain.
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.karttiming",
            kSecAttrAccount as String: key,
            kSecReturnData  as String: true,
            kSecMatchLimit  as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    // MARK: - Delete

    /// Rimuove la voce dal Keychain per la chiave specificata.
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.karttiming",
            kSecAttrAccount as String: key,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
