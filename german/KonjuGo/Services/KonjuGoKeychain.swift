import Foundation
import Security

@MainActor final class KonjuGoKeychain: KonjuGoCredentials {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.skylinevision.KonjuGo.api-keys",
         kSecAttrAccount as String: "OpenAI"]
    }
    func load() throws -> String {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw LookupError("Could not read your OpenAI key from Keychain (\(status)).")
        }
        return key
    }
    func save(_ key: String) throws {
        if key.trimmed.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw LookupError("Could not remove the saved key (\(status)).")
            }
            return
        }
        let attributes = [kSecValueData as String: Data(key.trimmed.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LookupError("Could not save your OpenAI key (\(status)).") }
    }
}
