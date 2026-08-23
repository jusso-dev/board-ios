import Foundation
import Security

struct StoredCredentials: Codable, Equatable, Sendable {
    let token: String
    let serverID: UUID
}

protocol CredentialStore: Sendable {
    func load() async throws -> StoredCredentials?
    func save(_ credentials: StoredCredentials) async throws
    func clear() async throws
}

enum KeychainStoreError: LocalizedError, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus:
            "The secure credential store is unavailable."
        case .invalidData:
            "The saved server link is invalid."
        }
    }
}

actor KeychainCredentialStore: CredentialStore {
    private let service: String
    private let account = "linked-server"

    init(service: String = "com.example.board.credentials") {
        self.service = service
    }

    func load() throws -> StoredCredentials? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainStoreError.invalidData
            }
            do {
                return try JSONDecoder().decode(StoredCredentials.self, from: data)
            } catch {
                throw KeychainStoreError.invalidData
            }
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    func save(_ credentials: StoredCredentials) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(credentials)
        } catch {
            throw KeychainStoreError.invalidData
        }

        let lookup = baseQuery()
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = lookup
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
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

actor MemoryCredentialStore: CredentialStore {
    private var value: StoredCredentials?

    init(value: StoredCredentials? = nil) {
        self.value = value
    }

    func load() -> StoredCredentials? { value }
    func save(_ credentials: StoredCredentials) { value = credentials }
    func clear() { value = nil }
}
