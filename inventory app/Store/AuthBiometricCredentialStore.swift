import Foundation
import Security

struct AuthBiometricCredential: Codable, Hashable {
    let email: String
    let password: String
}

struct AuthBiometricCredentialStore {
    let service: String
    private let account = "primary"

    func save(email: String, password: String) -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, !normalizedPassword.isEmpty else {
            return false
        }

        let credential = AuthBiometricCredential(email: normalizedEmail, password: normalizedPassword)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(credential) else {
            return false
        }

        let query = baseQuery()
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            return false
        }

        var createQuery = query
        createQuery[kSecValueData as String] = data
        createQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let createStatus = SecItemAdd(createQuery as CFDictionary, nil)
        return createStatus == errSecSuccess
    }

    func load() -> AuthBiometricCredential? {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(AuthBiometricCredential.self, from: data)
    }

    func remove() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
