import Foundation
import Testing
import MatindCore
@testable import MatindWorkboard

@Suite("控制面设备授权") @MainActor
struct RemoteDeviceAuthorizationTests {
    @Test("退出会话后旧登记响应不能激活设备")
    func logoutCancelsActivation() async {
        let control = PausedDeviceControl(pause: .registration)
        let state = LocalServerState(identities: MemoryDeviceKeyStore(), ledgers: MemoryLedgerStore(nil), host: MemoryLocalServiceHost(), control: control)
        _ = await state.start(ownerUserId: 7)
        let request = Task { await state.connectControlPlane(actorUserId: 7, token: "fixture") }
        await control.waitUntilPaused()
        state.clearSession()
        await control.resume()
        await request.value
        #expect(await control.mutations == 0)
        #expect(state.ledger == nil)
    }

    @Test("停止服务后旧权限查询响应不能创建授权")
    func stopCancelsAuthorization() async {
        let control = PausedDeviceControl(pause: .authorizations)
        let state = LocalServerState(identities: MemoryDeviceKeyStore(), ledgers: MemoryLedgerStore(nil), host: MemoryLocalServiceHost(), control: control)
        _ = await state.start(ownerUserId: 7)
        await state.connectControlPlane(actorUserId: 7, token: "fixture")
        let request = Task { await state.authorizeRemotely(actorUserId: 7, workspaceId: 10, capabilities: [.browserObserve], token: "fixture") }
        await control.waitUntilPaused()
        state.stop()
        await control.resume()
        await request.value
        #expect(await control.mutations == 0)
        #expect(state.ledger?.activeRecords().isEmpty == true)
    }
    @Test("云端登记失败时不声称已连接，也不写入授权")
    func registrationFailure() async {
        let state = LocalServerState(identities: MemoryDeviceKeyStore(), ledgers: MemoryLedgerStore(nil), host: MemoryLocalServiceHost(), control: FixtureDeviceControl(fail: true))
        _ = await state.start(ownerUserId: 7)
        defer { state.stop() }
        await state.connectControlPlane(actorUserId: 7, token: "fixture")
        #expect(!state.controlPlaneConnected)
        #expect(state.ledger?.activeRecords().isEmpty == true)
    }

    @Test("服务端授权ID成为账本身份；扩大服务器响应被拒绝")
    func usesCanonicalAuthorization() async throws {
        let control = FixtureDeviceControl()
        let state = LocalServerState(identities: MemoryDeviceKeyStore(), ledgers: MemoryLedgerStore(nil), host: MemoryLocalServiceHost(), control: control)
        _ = await state.start(ownerUserId: 7)
        defer { state.stop() }
        await state.connectControlPlane(actorUserId: 7, token: "fixture")
        #expect(state.controlPlaneConnected)
        await state.authorizeRemotely(actorUserId: 7, workspaceId: 10, capabilities: [.browserObserve], token: "fixture")
        #expect(state.ledger?.activeRecords().first?.id == control.authorizationId)
        #expect(state.ledger?.activeRecords().first?.capabilities == [.browserObserve])
        await state.authorizeRemotely(actorUserId: 7, workspaceId: 11, capabilities: [.browserObserve], token: "fixture")
        #expect(state.ledger?.activeRecords().count == 1)
    }
}

private actor PausedDeviceControl: LocalDeviceControlling {
    enum Phase { case registration, authorizations }
    let pause: Phase
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var mutations = 0
    init(pause: Phase) { self.pause = pause }
    func waitUntilPaused() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func resume() { continuation?.resume(); continuation = nil }
    private func suspend() async {
        await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
    }
    func register(_ document: ServerRegistration, token: String) async throws -> RegisteredLocalDevice {
        if pause == .registration { await suspend() }
        return RegisteredLocalDevice(deviceId: document.deviceId, ownerUserId: 7, status: pause == .registration ? "pending" : "active", publicKey: document.publicKey.publicKey)
    }
    func activate(deviceId: UUID, token: String) async throws -> RegisteredLocalDevice { mutations += 1; throw URLError(.badServerResponse) }
    func authorizations(workspaceId: Int64, token: String) async throws -> [RegisteredLocalAuthorization] {
        if pause == .authorizations { await suspend() }
        return []
    }
    func authorize(deviceId: UUID, workspaceId: Int64, capabilities: Set<LocalCapability>, token: String) async throws -> RegisteredLocalAuthorization { mutations += 1; throw URLError(.badServerResponse) }
    func narrow(_ record: WorkspaceAuthorization, capabilities: Set<LocalCapability>, token: String) async throws -> RegisteredLocalAuthorization { mutations += 1; throw URLError(.badServerResponse) }
    func release(_ record: WorkspaceAuthorization, token: String) async throws -> RegisteredLocalAuthorization { mutations += 1; throw URLError(.badServerResponse) }
}

private struct FixtureDeviceControl: LocalDeviceControlling {
    var fail = false
    let authorizationId = UUID()
    func register(_ document: ServerRegistration, token: String) async throws -> RegisteredLocalDevice {
        if fail { throw URLError(.notConnectedToInternet) }
        return RegisteredLocalDevice(deviceId: document.deviceId, ownerUserId: 7, status: "active", publicKey: document.publicKey.publicKey)
    }
    func activate(deviceId: UUID, token: String) async throws -> RegisteredLocalDevice { throw URLError(.badServerResponse) }
    func authorizations(workspaceId: Int64, token: String) async throws -> [RegisteredLocalAuthorization] { [] }
    func authorize(deviceId: UUID, workspaceId: Int64, capabilities: Set<LocalCapability>, token: String) async throws -> RegisteredLocalAuthorization {
        RegisteredLocalAuthorization(authorizationId: authorizationId, deviceId: deviceId, workspaceId: workspaceId, capabilities: workspaceId == 11 ? [.browserObserve, .browserClick] : capabilities, status: .active, version: 1)
    }
    func narrow(_ record: WorkspaceAuthorization, capabilities: Set<LocalCapability>, token: String) async throws -> RegisteredLocalAuthorization { throw URLError(.badServerResponse) }
    func release(_ record: WorkspaceAuthorization, token: String) async throws -> RegisteredLocalAuthorization { throw URLError(.badServerResponse) }
}
