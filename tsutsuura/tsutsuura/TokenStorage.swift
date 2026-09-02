import Foundation
import Security

protocol TokenStoring: Sendable {
    func readToken() async throws -> String?
    func writeToken(_ token: String) async throws
    func clearToken() async throws
}

enum KeychainTokenStoreError: Error, Equatable {
    case invalidTokenData
    case unexpectedStatus(OSStatus)
}

extension KeychainTokenStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidTokenData:
            return "ログイン情報を読み取れませんでした。もう一度ログインしてください。"
        case .unexpectedStatus:
            return "ログイン情報を安全に保存できませんでした。端末を再起動してもう一度お試しください。"
        }
    }
}

enum MutationProtectionKeyError: Error, Equatable, Sendable {
    case invalidKeyData
    case randomGenerationFailed(OSStatus)
    case unexpectedStatus(OSStatus)
}

extension MutationProtectionKeyError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidKeyData:
            return "再試行情報を保護する鍵を読み取れませんでした。端末を再起動してもう一度お試しください。"
        case .randomGenerationFailed, .unexpectedStatus:
            return "再試行情報を安全に保存できませんでした。端末を再起動してもう一度お試しください。"
        }
    }
}

/// Loads the per-install key used to make persisted mutation receipts opaque.
/// The key never leaves the device Keychain and is not synchronized or backed
/// up to another device.
enum KeychainMutationProtectionKey {
    static let byteCount = 32

    static func loadOrCreate(
        service: String = Bundle.main.bundleIdentifier
            ?? "link.toshizo.tsutsuura",
        account: String = "mutation-receipt-protection-key-v1",
        accessGroup: String? = nil
    ) throws -> Data {
        var query = baseQuery(
            service: service,
            account: account,
            accessGroup: accessGroup
        )
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let readStatus = SecItemCopyMatching(query as CFDictionary, &item)
        switch readStatus {
        case errSecSuccess:
            guard let data = item as? Data, data.count == byteCount else {
                throw MutationProtectionKeyError.invalidKeyData
            }
            return data
        case errSecItemNotFound:
            break
        default:
            throw MutationProtectionKeyError.unexpectedStatus(readStatus)
        }

        var bytes = [UInt8](repeating: 0, count: byteCount)
        let randomStatus = SecRandomCopyBytes(
            kSecRandomDefault,
            byteCount,
            &bytes
        )
        guard randomStatus == errSecSuccess else {
            throw MutationProtectionKeyError.randomGenerationFailed(
                randomStatus
            )
        }
        let data = Data(bytes)
        var addQuery = baseQuery(
            service: service,
            account: account,
            accessGroup: accessGroup
        )
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return data
        }
        // Another process may have won the create race. Read its key rather
        // than replacing it, because existing encrypted receipts depend on it.
        if addStatus == errSecDuplicateItem {
            var retryQuery = baseQuery(
                service: service,
                account: account,
                accessGroup: accessGroup
            )
            retryQuery[kSecReturnData as String] = true
            retryQuery[kSecMatchLimit as String] = kSecMatchLimitOne
            var retryItem: CFTypeRef?
            let retryStatus = SecItemCopyMatching(
                retryQuery as CFDictionary,
                &retryItem
            )
            guard retryStatus == errSecSuccess,
                  let retryData = retryItem as? Data,
                  retryData.count == byteCount else {
                throw MutationProtectionKeyError.unexpectedStatus(
                    retryStatus
                )
            }
            return retryData
        }
        throw MutationProtectionKeyError.unexpectedStatus(addStatus)
    }

    private static func baseQuery(
        service: String,
        account: String,
        accessGroup: String?
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

actor KeychainTokenStore: TokenStoring {
    private let service: String
    private let account: String
    private let accessGroup: String?

    init(
        service: String = Bundle.main.bundleIdentifier ?? "link.toshizo.tsutsuura",
        account: String = "api-access-token",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    func readToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                throw KeychainTokenStoreError.invalidTokenData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
    }

    func writeToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainTokenStoreError.invalidTokenData
        }

        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] =
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainTokenStoreError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainTokenStoreError.unexpectedStatus(updateStatus)
        }
    }

    func clearToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

actor InMemoryTokenStore: TokenStoring {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func readToken() -> String? {
        token
    }

    func writeToken(_ token: String) {
        self.token = token
    }

    func clearToken() {
        token = nil
    }
}
