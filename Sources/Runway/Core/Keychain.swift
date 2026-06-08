import Foundation
import Security

/// Minimal read-only access to a macOS generic-password keychain item.
///
/// Reading another app's item triggers a one-time access prompt; clicking
/// "Always Allow" binds the grant to Runway's code signature. Callers must
/// cache the result in memory so the prompt is not re-triggered on every refresh.
enum Keychain {
    static func readGenericPassword(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
}
