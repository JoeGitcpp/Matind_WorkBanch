import CryptoKit
import Foundation
import Testing
import MatindCore
@testable import MatindWorkboard

@Suite("本机服务器授权")
struct AuthorizationLedgerTests {
    private func ledger(owner: Int64 = 7) -> AuthorizationLedger {
        AuthorizationLedger(server: OwnedServer(ownerUserId: owner, deviceId: UUID()))
    }

    @Test("别人不能给这台服务器授权")
    func nonOwnerCannotPropose() {
        var book = ledger()
        let decision = book.propose(actorUserId: 8, workspaceId: 3, capabilities: [.blueprintRun])
        #expect(decision == .refused(.notOwner))
        #expect(book.activeRecords().isEmpty)
    }

    @Test("所有者授权后不能扩大，只能收窄")
    func narrowDoesNotExpand() {
        var book = ledger()
        let created = book.propose(
            actorUserId: 7,
            workspaceId: 3,
            capabilities: [.blueprintRun, .healthRead]
        )
        guard case .created(let authorization) = created else {
            Issue.record("应当创建授权")
            return
        }
        let expanded = book.propose(
            actorUserId: 7,
            workspaceId: 3,
            capabilities: [.blueprintRun, .healthRead, .auditRead]
        )
        #expect(expanded == .refused(.expansionForbidden))
        #expect(book.activeRecords().first?.version == 1)

        let narrowed = book.propose(actorUserId: 7, workspaceId: 3, capabilities: [.blueprintRun])
        guard case .narrowed(let updated) = narrowed else {
            Issue.record("应当收窄")
            return
        }
        #expect(updated.version == 2)
        #expect(updated.capabilities == [.blueprintRun])
        #expect(updated.id == authorization.id)

        let same = book.propose(actorUserId: 7, workspaceId: 3, capabilities: [.blueprintRun])
        #expect(same == .unchanged(updated))
        #expect(book.activeRecords().first?.version == 2)
    }

    @Test("短授权必须落在有效授权内且不超过 900 秒")
    func grantStaysInsideAuthorization() {
        var book = ledger()
        guard case .created(let authorization) = book.propose(
            actorUserId: 7,
            workspaceId: 3,
            capabilities: [.blueprintRun, .healthRead]
        ) else {
            Issue.record("应当创建授权")
            return
        }
        let issued = book.issueGrant(
            authorizationId: authorization.id,
            capabilities: [.blueprintRun],
            ttlSeconds: 900
        )
        guard case .issued(let grant) = issued else {
            Issue.record("应当签发")
            return
        }
        #expect(grant.authorizationVersion == 1)
        #expect(book.issueGrant(
            authorizationId: authorization.id,
            capabilities: [.deviceRevoke],
            ttlSeconds: 60
        ) == .refused(.capabilitiesExceeded))
        #expect(book.issueGrant(
            authorizationId: authorization.id,
            capabilities: [.blueprintRun],
            ttlSeconds: 901
        ) == .refused(.ttlExceeded))
        #expect(book.issueGrant(
            authorizationId: authorization.id,
            capabilities: [],
            ttlSeconds: 60
        ) == .refused(.emptyCapabilities))

        _ = book.release(actorUserId: 7, authorizationId: authorization.id)
        #expect(book.issueGrant(
            authorizationId: authorization.id,
            capabilities: [.blueprintRun],
            ttlSeconds: 60
        ) == .refused(.authorizationInactive))
    }

    @Test("解除后可以重新授权，工作区编号为零被拒绝")
    func releaseThenAuthorizeAgain() {
        var book = ledger()
        #expect(book.propose(actorUserId: 7, workspaceId: 0, capabilities: [.blueprintRun]) == .refused(.invalidWorkspace))
        guard case .created(let authorization) = book.propose(
            actorUserId: 7,
            workspaceId: 4,
            capabilities: [.auditRead]
        ) else {
            Issue.record("应当创建授权")
            return
        }
        #expect(book.release(actorUserId: 9, authorizationId: authorization.id) == .refused(.notOwner))
        guard case .released = book.release(actorUserId: 7, authorizationId: authorization.id) else {
            Issue.record("应当解除")
            return
        }
        guard case .created(let again) = book.propose(
            actorUserId: 7,
            workspaceId: 4,
            capabilities: [.healthRead]
        ) else {
            Issue.record("解除后应能重新授权")
            return
        }
        #expect(again.version == 1)
        #expect(again.id != authorization.id)
    }
}

@Suite("登记文档")
struct ServerRegistrationTests {
    @Test("登记文档拒绝工作区字段")
    func rejectsWorkspaceBinding() throws {
        let document: [String: Any] = [
            "contractVersion": "local-server-v1",
            "deviceId": UUID().uuidString,
            "label": "Studio",
            "clientVersion": "1.0.0",
            "status": "pending",
            "workspaceId": 9,
            "publicKey": ["algorithm": "ed25519", "publicKey": String(repeating: "A", count: 43)]
        ]
        let data = try JSONSerialization.data(withJSONObject: document)
        #expect(throws: RegistrationDocumentError.workspaceBindingForbidden) {
            try ServerRegistrationDocument.parse(data)
        }
    }

    @Test("发出的登记文档没有工作区，公钥是 43 位")
    func emittedDocumentHasNoWorkspace() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = try #require(key.publicKeyText())
        let registration = try #require(ServerRegistrationDocument.make(
            deviceId: UUID(),
            label: "Studio",
            clientVersion: "1.0.0",
            publicKey: publicKey
        ))
        let data = try JSONEncoder().encode(registration)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["workspaceId"] == nil)
        #expect(object["workspace_id"] == nil)
        #expect(registration.status == "pending")
        #expect(registration.publicKey.publicKey.count == 43)
        let parsed = try ServerRegistrationDocument.parse(data)
        #expect(parsed == registration)
    }
}

@Suite("设备密钥")
struct DeviceIdentityStoreTests {
    @Test("私钥留在钥匙串，签名可以验过")
    func keychainRoundtrip() throws {
        let account = "device-key-test-\(UUID().uuidString)"
        let keychain = KeychainPasswordStore(service: "matind-workboard-test", account: account)
        let store = DeviceIdentityStore(keychain: keychain)
        let created = try store.create()
        let loaded = try #require(try store.load())
        let message = Data("local-server".utf8)
        let signature = try created.signature(for: message)
        #expect(loaded.publicKey.isValidSignature(signature, for: message))
        #expect(loaded.publicKey.rawRepresentation == created.publicKey.rawRepresentation)
        keychain.clear()
    }
}

@Suite("回环监听")
struct LoopbackServerTests {
    @Test("健康检查只来自 127.0.0.1")
    func healthUsesLoopback() async throws {
        let server = LoopbackServer()
        let port = try await server.start(health: LoopbackHealth(
            bind: LoopbackBind.host,
            contractVersion: LocalServerContract.version
        ))
        defer { server.stop() }
        let healthURL = try #require(URL(string: "http://127.0.0.1:\(port)/health"))
        let (body, response) = try await URLSession.shared.data(from: healthURL)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        let health = try JSONDecoder().decode(LoopbackHealth.self, from: body)
        #expect(health.bind == "127.0.0.1")

        let otherURL = try #require(URL(string: "http://127.0.0.1:\(port)/files"))
        let (_, other) = try await URLSession.shared.data(from: otherURL)
        let otherHTTP = try #require(other as? HTTPURLResponse)
        #expect(otherHTTP.statusCode == 404)
    }
}

@Suite("所有者控制台")
struct LocalServerStateTests {
    @Test("其他用户不能接管已经建立的服务器")
    @MainActor
    func otherUserCannotAdopt() async {
        let existing = AuthorizationLedger(server: OwnedServer(ownerUserId: 7, deviceId: UUID()))
        let state = LocalServerState(
            identities: MemoryDeviceKeyStore(),
            ledgers: MemoryLedgerStore(existing),
            host: MemoryLocalServiceHost(),
            label: "Test",
            clientVersion: "1.0.0"
        )
        let result = await state.start(ownerUserId: 8)
        #expect(result == .refused(.ownedBySomeoneElse(ownerUserId: 7)))
        #expect(state.ledger == nil)
    }

    @Test("第一次启动归当前用户，登记文档不带工作区")
    @MainActor
    func firstStartBelongsToCurrentUser() async throws {
        let keys = MemoryDeviceKeyStore()
        let state = LocalServerState(
            identities: keys,
            ledgers: MemoryLedgerStore(nil),
            host: MemoryLocalServiceHost(),
            label: "Studio",
            clientVersion: "1.0.0"
        )
        let result = await state.start(ownerUserId: 3)
        defer { state.stop() }
        guard case .running = result else {
            Issue.record("应当监听成功，实际 \(result)")
            return
        }
        let document = try #require(state.registrationDocument())
        let data = try JSONEncoder().encode(document)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["workspaceId"] == nil)
        #expect(state.ledger?.server.ownerUserId == 3)
        #expect(document.status == "pending")

        let deviceId = try #require(state.ledger?.server.deviceId)
        state.stop()
        let again = await state.start(ownerUserId: 3)
        defer { state.stop() }
        guard case .running = again else {
            Issue.record("重启应当沿用原设备")
            return
        }
        #expect(state.ledger?.server.deviceId == deviceId)
    }
}

final class MemoryLedgerStore: ServerLedgerStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var ledger: AuthorizationLedger?

    init(_ ledger: AuthorizationLedger?) {
        self.ledger = ledger
    }

    func load() -> AuthorizationLedger? {
        lock.lock()
        defer { lock.unlock() }
        return ledger
    }

    func save(_ ledger: AuthorizationLedger) {
        lock.lock()
        self.ledger = ledger
        lock.unlock()
    }
}

final class MemoryDeviceKeyStore: DeviceKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var key: Curve25519.Signing.PrivateKey?

    func load() throws -> Curve25519.Signing.PrivateKey? {
        lock.lock()
        defer { lock.unlock() }
        return key
    }

    func create() throws -> Curve25519.Signing.PrivateKey {
        lock.lock()
        defer { lock.unlock() }
        if key != nil { throw DeviceIdentityError.alreadyExists }
        let created = Curve25519.Signing.PrivateKey()
        key = created
        return created
    }
}

@MainActor
final class MemoryLocalServiceHost: LocalServiceHosting {
    private(set) var isRunning = false
    func start(configuration: LocalServiceLaunch, identity: LocalServiceBootstrap) async throws -> LocalServiceReady {
        isRunning = true
        return LocalServiceReady(port: 43210, identity: LocalServiceIdentity(deviceId: identity.deviceId, publicKey: identity.publicKey))
    }
    func stop() { isRunning = false }
}
