import CryptoKit
import Foundation
import Observation

enum ServerRuntime: Equatable, Sendable {
    case stopped
    case running(port: UInt16)
}

enum ServerStartResult: Equatable, Sendable {
    case running(port: UInt16)
    case refused(ServerStartRefusal)
}

enum ServerStartRefusal: Equatable, Sendable {
    case ownedBySomeoneElse(ownerUserId: Int64)
    case identityUnreadable
    case listenerFailed
}

enum ServerNotice: Equatable {
    case none
    case started(UInt16)
    case startRefused(ServerStartRefusal)
    case authorization(AuthorizationDecision)
}

/// 所有者控制台。默认不监听；启动后只绑回环地址。
@Observable
@MainActor
final class LocalServerState {
    private(set) var runtime: ServerRuntime = .stopped
    private(set) var ledger: AuthorizationLedger?
    private(set) var publicKeyText: String?
    private(set) var notice: ServerNotice = .none

    private let identities: any DeviceKeyProviding
    private let ledgers: any ServerLedgerStoring
    private let loopback: LoopbackServer
    private let label: String
    private let clientVersion: String
    private var startGeneration = 0

    init(
        identities: any DeviceKeyProviding = DeviceIdentityStore(),
        ledgers: any ServerLedgerStoring = UserDefaultsLedgerStore(),
        loopback: LoopbackServer = LoopbackServer(),
        label: String = ServerHostLabel.current(),
        clientVersion: String = ServerHostLabel.clientVersion(from: AppConfig.appVersion)
    ) {
        self.identities = identities
        self.ledgers = ledgers
        self.loopback = loopback
        self.label = label
        self.clientVersion = clientVersion
    }

    func start(ownerUserId: Int64) async -> ServerStartResult {
        startGeneration += 1
        let generation = startGeneration
        loopback.stop()
        runtime = .stopped
        switch prepare(ownerUserId: ownerUserId) {
        case .refused(let refusal):
            notice = .startRefused(refusal)
            return .refused(refusal)
        case .ready:
            return await listen(generation: generation)
        }
    }

    func stop() {
        startGeneration += 1
        loopback.stop()
        runtime = .stopped
    }

    /// 退出登录时清掉内存中的账本。钥匙串和磁盘上的所有者记录保留。
    func clearSession() {
        stop()
        ledger = nil
        publicKeyText = nil
        notice = .none
    }

    func registrationDocument() -> ServerRegistration? {
        guard let ledger, let publicKeyText else { return nil }
        return ServerRegistrationDocument.make(
            deviceId: ledger.server.deviceId,
            label: label,
            clientVersion: clientVersion,
            publicKey: publicKeyText
        )
    }

    func propose(
        actorUserId: Int64,
        workspaceId: Int64,
        capabilities: Set<LocalCapability>
    ) -> AuthorizationDecision {
        guard var current = ledger else {
            return remember(.refused(.missing))
        }
        let decision = current.propose(
            actorUserId: actorUserId,
            workspaceId: workspaceId,
            capabilities: capabilities
        )
        rememberLedger(current, decision: decision)
        return decision
    }

    func release(actorUserId: Int64, authorizationId: UUID) -> AuthorizationDecision {
        guard var current = ledger else {
            return remember(.refused(.missing))
        }
        let decision = current.release(actorUserId: actorUserId, authorizationId: authorizationId)
        rememberLedger(current, decision: decision)
        return decision
    }

    private func listen(generation: Int) async -> ServerStartResult {
        do {
            let port = try await loopback.start(health: LoopbackHealth(
                bind: LoopbackBind.host,
                contractVersion: LocalServerContract.version
            ))
            guard generation == startGeneration else {
                return .refused(.listenerFailed)
            }
            runtime = .running(port: port)
            notice = .started(port)
            return .running(port: port)
        } catch {
            guard generation == startGeneration else {
                return .refused(.listenerFailed)
            }
            runtime = .stopped
            notice = .startRefused(.listenerFailed)
            return .refused(.listenerFailed)
        }
    }

    private func prepare(ownerUserId: Int64) -> PreparedServer {
        if let existing = ledgers.load() {
            return adopt(existing, ownerUserId: ownerUserId)
        }
        return openNew(ownerUserId: ownerUserId)
    }

    private func adopt(_ existing: AuthorizationLedger, ownerUserId: Int64) -> PreparedServer {
        guard existing.server.ownerUserId == ownerUserId else {
            return .refused(.ownedBySomeoneElse(ownerUserId: existing.server.ownerUserId))
        }
        do {
            guard let key = try identities.load() else {
                return .refused(.identityUnreadable)
            }
            return publish(existing, key: key)
        } catch {
            return .refused(.identityUnreadable)
        }
    }

    private func openNew(ownerUserId: Int64) -> PreparedServer {
        do {
            if try identities.load() != nil {
                return .refused(.identityUnreadable)
            }
            let key = try identities.create()
            let created = AuthorizationLedger(
                server: OwnedServer(ownerUserId: ownerUserId, deviceId: UUID())
            )
            ledgers.save(created)
            return publish(created, key: key)
        } catch {
            return .refused(.identityUnreadable)
        }
    }

    private func publish(
        _ ledger: AuthorizationLedger,
        key: Curve25519.Signing.PrivateKey
    ) -> PreparedServer {
        guard let text = key.publicKeyText() else {
            return .refused(.identityUnreadable)
        }
        self.ledger = ledger
        publicKeyText = text
        return .ready
    }

    private func rememberLedger(_ ledger: AuthorizationLedger, decision: AuthorizationDecision) {
        if decision.writesLedger {
            self.ledger = ledger
            ledgers.save(ledger)
        }
        notice = .authorization(decision)
    }

    private func remember(_ decision: AuthorizationDecision) -> AuthorizationDecision {
        notice = .authorization(decision)
        return decision
    }
}

private enum PreparedServer {
    case ready
    case refused(ServerStartRefusal)
}
