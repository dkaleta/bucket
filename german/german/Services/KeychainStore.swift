import Foundation
import Security

@MainActor final class KeychainStore: CredentialStoring {
    private let service = "com.skylinevision.german.api-keys"

    private func query(_ provider: APIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }

    func read(_ provider: APIProvider) throws -> String {
        var request = query(provider)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw PracticeError(message: "Could not read the \(provider.rawValue) key from Keychain (\(status)).")
        }
        return value
    }

    func save(_ key: String, for provider: APIProvider) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = query(provider)
        if value.isEmpty {
            let status = SecItemDelete(request as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw PracticeError(message: "Could not remove the \(provider.rawValue) key (\(status)).")
            }
            return
        }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = request.merging(attributes) { _, new in new }
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(newItem as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw PracticeError(message: "Could not save the \(provider.rawValue) key in Keychain (\(status)).")
        }
    }
}
