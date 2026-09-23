import CryptoKit
import Foundation

enum DeviceIdentityError: Error {
    case invalidKey
    case alreadyExists
}

protocol DeviceKeyProviding: Sendable {
    func load() throws -> Curve25519.Signing.PrivateKey?
    func create() throws -> Curve25519.Signing.PrivateKey
}

/// 设备签名私钥只进出钥匙串，不进用户默认配置，也不进登记文档。
struct DeviceIdentityStore: DeviceKeyProviding {
    private let keychain: KeychainPasswordStore

    init(keychain: KeychainPasswordStore = KeychainPasswordStore(
        service: AppConfig.keychainService,
        account: AppConfig.deviceKeyAccount
    )) {
        self.keychain = keychain
    }

    func load() throws -> Curve25519.Signing.PrivateKey? {
        guard let data = keychain.load() else { return nil }
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
            throw DeviceIdentityError.invalidKey
        }
        return key
    }

    func create() throws -> Curve25519.Signing.PrivateKey {
        if try load() != nil {
            throw DeviceIdentityError.alreadyExists
        }
        let key = Curve25519.Signing.PrivateKey()
        try keychain.save(key.rawRepresentation)
        return key
    }
}

protocol ServerLedgerStoring: Sendable {
    func load() -> AuthorizationLedger?
    func save(_ ledger: AuthorizationLedger)
}

struct UserDefaultsLedgerStore: ServerLedgerStoring {
    private let storage: LocalStorage
    private let key: String

    init(storage: LocalStorage = .shared, key: String = AppConfig.privateServerLedgerKey) {
        self.storage = storage
        self.key = key
    }

    func load() -> AuthorizationLedger? {
        storage.get(AuthorizationLedger.self, forKey: key)
    }

    func save(_ ledger: AuthorizationLedger) {
        storage.set(ledger, forKey: key)
    }
}
