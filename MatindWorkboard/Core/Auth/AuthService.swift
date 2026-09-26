import Foundation

enum AuthServiceError: Error {
    case keychainError(OSStatus)
    case dataConversionError
}

struct AuthService {
    private let store: KeychainPasswordStore

    init(store: KeychainPasswordStore = KeychainPasswordStore(
        service: AppConfig.keychainService,
        account: AppConfig.keychainAccount
    )) {
        self.store = store
    }

    func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw AuthServiceError.dataConversionError
        }
        do {
            try store.save(data)
        } catch let KeychainStoreError.keychain(status) {
            throw AuthServiceError.keychainError(status)
        }
    }

    func loadToken() -> String? {
        guard let data = store.load() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clearToken() {
        store.clear()
    }
}
