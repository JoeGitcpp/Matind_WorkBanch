import Foundation
import MatindCore

/// 登录会话。和旧的单条访问令牌分开存。
struct SessionCredentialStore: Sendable {
    private let store: KeychainPasswordStore

    init(store: KeychainPasswordStore = KeychainPasswordStore(
        service: AppConfig.keychainService,
        account: AppConfig.sessionAccount
    )) {
        self.store = store
    }

    func load() -> SessionTokens? {
        guard let data = store.load() else { return nil }
        return try? JSONDecoder().decode(SessionTokens.self, from: data)
    }

    func save(_ session: SessionTokens) throws {
        let data = try JSONEncoder().encode(session)
        try store.save(data)
    }

    func clear() {
        store.clear()
    }
}
