import CryptoKit
import Foundation
import Observation
import MatindCore

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
    case hostUnavailable(LocalServiceHostError)
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
    private(set) var isStarting = false
    private(set) var controlPlaneConnected = false
    private(set) var isUpdatingAccess = false
    private(set) var accessNotice: String?
    private(set) var browserPolicy: BrowserExecutionPolicy?
    private(set) var browserStatusText = "浏览器执行未启动"
    private(set) var isOpeningBrowser = false

    private let identities: any DeviceKeyProviding
    private let ledgers: any ServerLedgerStoring
    private let host: any LocalServiceHosting
    private let launch: LocalServiceLaunch
    private let control: any LocalDeviceControlling
    private let label: String
    private let clientVersion: String
    private var startGeneration = 0
    private var monitor: Task<Void, Never>?

    init(
        identities: any DeviceKeyProviding = DeviceIdentityStore(),
        ledgers: any ServerLedgerStoring = UserDefaultsLedgerStore(),
        host: any LocalServiceHosting = LocalServiceHost(),
        launch: LocalServiceLaunch = LocalServiceInstallation.configuration(),
        control: any LocalDeviceControlling = LocalDeviceControlClient(),
        label: String = ServerHostLabel.current(),
        clientVersion: String = ServerHostLabel.clientVersion(from: AppConfig.appVersion)
    ) {
        self.identities = identities
        self.ledgers = ledgers
        self.host = host
        self.launch = launch
        self.control = control
        self.label = label
        self.clientVersion = clientVersion
        browserPolicy = try? BrowserPolicyStore(directory: launch.dataDirectory).load()
    }

    func start(ownerUserId: Int64) async -> ServerStartResult {
        startGeneration += 1
        let generation = startGeneration
        monitor?.cancel()
        host.stop()
        runtime = .stopped
        isStarting = true
        defer { if generation == startGeneration { isStarting = false } }
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
        monitor?.cancel()
        monitor = nil
        host.stop()
        runtime = .stopped
        isStarting = false
        controlPlaneConnected = false
        browserStatusText = "浏览器执行未启动"
    }

    /// 退出登录时清掉内存中的账本。钥匙串和磁盘上的所有者记录保留。
    func clearSession() {
        stop()
        ledger = nil
        publicKeyText = nil
        notice = .none
        controlPlaneConnected = false
        accessNotice = nil
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

    func connectControlPlane(actorUserId: Int64, token: String) async {
        guard !isUpdatingAccess, ledger?.server.ownerUserId == actorUserId,
              host.isRunning, let document = registrationDocument() else { return }
        isUpdatingAccess = true
        controlPlaneConnected = false
        let generation = startGeneration
        defer { isUpdatingAccess = false }
        do {
            var device = try await control.register(document, token: token)
            guard generation == startGeneration, ledger?.server.ownerUserId == actorUserId, host.isRunning else { return }
            guard device.deviceId == document.deviceId, device.ownerUserId == actorUserId,
                  device.publicKey == document.publicKey.publicKey else { throw ControlPlaneFailure.undecodable }
            // A revoked/suspended device requires a separate owner decision; registration cannot revive it.
            if device.status == "pending" { device = try await control.activate(deviceId: document.deviceId, token: token) }
            guard generation == startGeneration, device.status == "active", device.deviceId == document.deviceId,
                  device.ownerUserId == actorUserId, device.publicKey == document.publicKey.publicKey else { throw ControlPlaneFailure.undecodable }
            controlPlaneConnected = true
            accessNotice = "设备已登记到当前控制面，可以提交工作区授权"
        } catch {
            if generation == startGeneration { accessNotice = "控制面连接未完成，请检查登录、网络或设备是否已被停用后重试" }
        }
    }

    func authorizeRemotely(actorUserId: Int64, workspaceId: Int64, capabilities: Set<LocalCapability>, token: String) async {
        guard !isUpdatingAccess, controlPlaneConnected, var current = ledger,
              current.server.ownerUserId == actorUserId else { return }
        let decision = current.propose(actorUserId: actorUserId, workspaceId: workspaceId, capabilities: capabilities)
        if case .refused = decision { notice = .authorization(decision); return }
        let generation = startGeneration
        isUpdatingAccess = true
        defer { isUpdatingAccess = false }
        do {
            let remote = try await control.authorizations(workspaceId: workspaceId, token: token)
            guard generation == startGeneration, ledger?.server.ownerUserId == actorUserId, host.isRunning else { return }
            let existing = remote.first { $0.deviceId == current.server.deviceId && $0.status == .active }
            let result: RegisteredLocalAuthorization
            if let existing {
                guard capabilities.isSubset(of: existing.capabilities) else {
                    notice = .authorization(.refused(.expansionForbidden)); return
                }
                result = existing.capabilities == capabilities ? existing : try await control.narrow(existing.record, capabilities: capabilities, token: token)
            } else {
                result = try await control.authorize(deviceId: current.server.deviceId, workspaceId: workspaceId, capabilities: capabilities, token: token)
            }
            guard generation == startGeneration, result.workspaceId == workspaceId, result.status == .active,
                  var confirmed = ledger, confirmed.adoptConfirmed(result.record, requested: capabilities) else {
                throw ControlPlaneFailure.undecodable
            }
            // Narrow the local browser gate before accepting a narrower cloud authorization.
            do { try restrictBrowserPolicy(workspaceId: workspaceId, capabilities: capabilities) }
            catch { stop(); accessNotice = "本机许可更新失败，执行服务已停止；请重新连接核对控制面授权"; return }
            ledger = confirmed
            ledgers.save(confirmed)
            notice = .authorization(existing == nil ? .created(result.record) : .narrowed(result.record))
            accessNotice = "工作区授权已在控制面确认"
        } catch {
            if generation == startGeneration { accessNotice = "工作区授权未确认；没有在本机增加权限，可重试核对服务端结果" }
        }
    }

    func releaseRemotely(actorUserId: Int64, record: WorkspaceAuthorization, token: String) async {
        guard !isUpdatingAccess, ledger?.server.ownerUserId == actorUserId else { return }
        isUpdatingAccess = true
        let generation = startGeneration
        defer { isUpdatingAccess = false }
        do {
            // Stop local access first, including when the network is unavailable.
            try restrictBrowserPolicy(workspaceId: record.workspaceId, capabilities: [])
            let result = try await control.release(record, token: token)
            guard generation == startGeneration, result.authorizationId == record.id,
                  result.workspaceId == record.workspaceId, result.status == .revoked,
                  var current = ledger, current.adoptConfirmed(result.record, requested: record.capabilities) else {
                throw ControlPlaneFailure.undecodable
            }
            ledger = current
            ledgers.save(current)
            notice = .authorization(.released(result.record))
            accessNotice = "本机及控制面的授权均已解除"
        } catch {
            // Even a disk failure must close the execution gate.
            stop()
            accessNotice = "本机执行已停止；控制面解除尚未确认，请联网后重试"
        }
    }

    func saveBrowserBinding(actorUserId: Int64, workspaceId: Int64, connectionId: UUID, origins: [String], allowWrite: Bool) {
        guard ledger?.server.ownerUserId == actorUserId, controlPlaneConnected,
              let authorization = ledger?.activeRecords().first(where: { $0.workspaceId == workspaceId }) else {
            accessNotice = "先连接控制面并确认工作区授权"; return
        }
        let actions = ["browser.observe", "browser.navigate"] + (allowWrite ? ["browser.fill", "browser.click"] : [])
        do {
            let canonical = try origins.map(BrowserAccountBinding.normalizedOrigin)
            let binding = BrowserAccountBinding(workspaceId: workspaceId, connectionId: connectionId, actions: actions, allowedOrigins: canonical)
            try binding.validated(allowedActions: browserActions(authorization.capabilities))
            var policy = try BrowserPolicyStore(directory: launch.dataDirectory).load() ?? LocalServiceInstallation.browserPolicy()
            policy.controlPlaneUrl = AppConfig.apiBaseURL
            policy.enabled = true
            policy.bindings.removeAll { $0.connectionId == connectionId && $0.workspaceId == workspaceId }
            policy.bindings.append(binding)
            try BrowserPolicyStore(directory: launch.dataDirectory).save(policy)
            browserPolicy = policy
            accessNotice = "已保存本机网站许可；执行器还会核验模块签名、账号绑定和逐次操作授权"
        } catch { accessNotice = "未保存许可：请检查工作区能力和网站地址（仅 HTTPS 域名，可带端口，不含路径）" }
    }

    func removeBrowserBinding(actorUserId: Int64, connectionId: UUID) {
        guard ledger?.server.ownerUserId == actorUserId else { return }
        do {
            guard var policy = try BrowserPolicyStore(directory: launch.dataDirectory).load() else { return }
            policy.bindings.removeAll { $0.connectionId == connectionId }
            try BrowserPolicyStore(directory: launch.dataDirectory).save(policy)
            browserPolicy = policy
            accessNotice = "已解除该账号在本机的网站许可"
        } catch { stop(); accessNotice = "许可文件更新失败，本机执行已停止" }
    }

    func setBrowserEnabled(actorUserId: Int64, enabled: Bool) {
        guard ledger?.server.ownerUserId == actorUserId else { return }
        do {
            guard var policy = try BrowserPolicyStore(directory: launch.dataDirectory).load() else { return }
            policy.enabled = enabled
            try BrowserPolicyStore(directory: launch.dataDirectory).save(policy)
            browserPolicy = policy
            accessNotice = enabled ? "已启用本机浏览器许可，等待执行器校验" : "已停用本机浏览器执行"
        } catch { stop(); accessNotice = "策略保存失败，执行服务已停止" }
    }

    private func refreshBrowserHealth(port: UInt16, generation: Int) async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 2
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/health")!)
            guard generation == startGeneration, data.count <= 16384,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let capabilities = body["capabilities"] as? [String: Any],
                  let browser = capabilities["localBrowser"] as? [String: Any] else { return }
            let testOnly = browser["testOnlyModuleRoot"] as? Bool == true
            let qualifier = testOnly ? "（开发测试组件）" : ""
            if browser["ready"] as? Bool == true {
                browserStatusText = "浏览器执行器已就绪\(qualifier)"
            } else if browser["enabled"] as? Bool == false {
                browserStatusText = "浏览器执行未启用\(qualifier)"
            } else {
                browserStatusText = "浏览器组件尚未就绪\(qualifier)，请检查安装与网站许可"
            }
        } catch {
            if generation == startGeneration { browserStatusText = "浏览器执行状态暂时无法读取" }
        }
    }

    func openAccountBrowser(actorUserId: Int64, binding: BrowserAccountBinding) async {
        guard !isOpeningBrowser, ledger?.server.ownerUserId == actorUserId, case .running(let port) = runtime,
              let deviceId = ledger?.server.deviceId, let origin = binding.allowedOrigins.first,
              let url = URL(string: origin + "/") else { return }
        let generation = startGeneration
        isOpeningBrowser = true
        defer { isOpeningBrowser = false }
        do {
            guard let key = try identities.load() else { throw BrowserPolicyError.invalidScope }
            let nonce = UUID()
            let command = try LocalProfileCommand(deviceId: deviceId, workspaceId: binding.workspaceId, connectionId: binding.connectionId, url: url, nonce: nonce)
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/browser/open-profile")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try command.signed(privateKey: key.rawRepresentation)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.connectionProxyDictionary = [:]
            configuration.httpCookieStorage = nil
            configuration.timeoutIntervalForRequest = 10
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (_, response) = try await session.data(for: request)
            guard generation == startGeneration, let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { throw BrowserPolicyError.invalidScope }
            accessNotice = "正在打开该账号的独立浏览器…"
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline, generation == startGeneration {
                let (data, _) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/health")!)
                guard generation == startGeneration, !Task.isCancelled else { return }
                guard data.count <= 16384, let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let caps = body["capabilities"] as? [String: Any], let browser = caps["localBrowser"] as? [String: Any] else {
                    throw BrowserPolicyError.invalidScope
                }
                if let result = browser["lastOwnerRequest"] as? [String: Any], result["requestId"] as? String == nonce.uuidString.lowercased() {
                    if result["status"] as? String == "succeeded" {
                        accessNotice = "账号浏览器已打开，请在窗口中手动登录；登录状态由网站确认"
                        return
                    }
                    if result["status"] as? String == "failed" { throw BrowserPolicyError.invalidScope }
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            if generation == startGeneration { accessNotice = "浏览器打开结果尚未确认，请检查执行器状态后再操作" }
        } catch {
            if generation == startGeneration { accessNotice = "账号浏览器未打开，请检查本机服务、网站许可与浏览器组件是否就绪" }
        }
    }

    private func browserActions(_ capabilities: Set<LocalCapability>) -> Set<String> {
        Set(capabilities.map(\.rawValue).filter { $0.hasPrefix("local.browser.") }.map { String($0.dropFirst(6)) })
    }

    private func restrictBrowserPolicy(workspaceId: Int64, capabilities: Set<LocalCapability>) throws {
        let store = BrowserPolicyStore(directory: launch.dataDirectory)
        guard var policy = try store.load() else { return }
        let allowed = browserActions(capabilities)
        policy.bindings = policy.bindings.compactMap { binding in
            guard binding.workspaceId == workspaceId else { return binding }
            var restricted = binding
            restricted.actions = binding.actions.filter { allowed.contains($0) }
            return restricted.actions.isEmpty ? nil : restricted
        }
        try store.save(policy)
        browserPolicy = policy
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
            guard let ledger, let key = try identities.load() else { return .refused(.identityUnreadable) }
            let result = try await host.start(configuration: launch, identity: LocalServiceBootstrap(
                deviceId: ledger.server.deviceId, privateKey: key.rawRepresentation
            ))
            guard generation == startGeneration else {
                return .refused(.listenerFailed)
            }
            let port = result.port
            runtime = .running(port: port)
            notice = .started(port)
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, self.startGeneration == generation else { return }
                    if !self.host.isRunning {
                        self.runtime = .stopped
                        self.notice = .startRefused(.hostUnavailable(.processExited))
                        return
                    }
                    await self.refreshBrowserHealth(port: port, generation: generation)
                }
            }
            return .running(port: port)
        } catch {
            guard generation == startGeneration else {
                return .refused(.listenerFailed)
            }
            runtime = .stopped
            let refusal = ServerStartRefusal.hostUnavailable((error as? LocalServiceHostError) ?? .launchFailed)
            notice = .startRefused(refusal)
            return .refused(refusal)
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
