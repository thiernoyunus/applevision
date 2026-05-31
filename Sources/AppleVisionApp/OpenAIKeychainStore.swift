import Foundation
import Security

enum OpenAIKeychainError: LocalizedError {
    case unexpectedData
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "The saved OpenAI API key could not be read from Keychain."
        case .unhandled(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}

struct OpenAIKeychainStore {
    private let service = "com.thiernodiallo.AppleVisionApp.openai"
    private let account = "default"

    func loadAPIKey() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let key = String(data: data, encoding: .utf8)
            else {
                throw OpenAIKeychainError.unexpectedData
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw OpenAIKeychainError.unhandled(status)
        }
    }

    func save(apiKey: String) throws {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(normalizedKey.utf8)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(baseQuery() as CFDictionary, updateAttributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insertQuery = baseQuery()
            insertQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw OpenAIKeychainError.unhandled(addStatus)
            }
        default:
            throw OpenAIKeychainError.unhandled(status)
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAIKeychainError.unhandled(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
