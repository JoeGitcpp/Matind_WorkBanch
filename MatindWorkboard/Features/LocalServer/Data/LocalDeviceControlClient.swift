import Foundation
import MatindCore

struct RegisteredLocalDevice: Decodable, Sendable {
    let deviceId: UUID
    let ownerUserId: Int64
    let status: String
    let publicKey: String
}

struct RegisteredLocalAuthorization: Decodable, Sendable {
    let authorizationId: UUID
    let deviceId: UUID
    let workspaceId: Int64
    let capabilities: Set<LocalCapability>
    let status: AuthorizationStatus
    let version: Int

    var record: WorkspaceAuthorization {
        WorkspaceAuthorization(id: authorizationId, deviceId: deviceId, workspaceId: workspaceId,
                               capabilities: capabilities, status: status, version: version)
    }
}

protocol LocalDeviceControlling: Sendable {
    func register(_ document: ServerRegistration, token: String) async throws -> RegisteredLocalDevice
    func activate(deviceId: UUID, token: String) async throws -> RegisteredLocalDevice
    func authorize(deviceId: UUID, workspaceId: Int64, capabilities: Set<LocalCapability>, token: String) async throws -> RegisteredLocalAuthorization
    func authorizations(workspaceId: Int64, token: String) async throws -> [RegisteredLocalAuthorization]
    func narrow(_ record: WorkspaceAuthorization, capabilities: Set<LocalCapability>, token: String) async throws -> RegisteredLocalAuthorization
    func release(_ record: WorkspaceAuthorization, token: String) async throws -> RegisteredLocalAuthorization
}

struct LocalDeviceControlClient: LocalDeviceControlling {
    private let transport = ControlPlaneTransport.shared
    private let base = "/api/v1/local-servers"

    func register(_ document: ServerRegistration, token: String) async throws -> RegisteredLocalDevice {
        struct Receipt: Decodable { let device: RegisteredLocalDevice }
        return try await transport.envelope(.post, path: "\(base)/devices", body: JSONEncoder().encode(document), token: token, as: Receipt.self).device
    }
    func activate(deviceId: UUID, token: String) async throws -> RegisteredLocalDevice {
        try await transport.envelope(.post, path: "\(base)/devices/\(deviceId)/status", body: JSONEncoder().encode(["status": "active"]), token: token, as: RegisteredLocalDevice.self)
    }
    func authorize(deviceId: UUID, workspaceId: Int64, capabilities: Set<LocalCapability>, token: String) async throws -> RegisteredLocalAuthorization {
        struct Request: Encodable { let workspaceId: Int64; let capabilities: Set<LocalCapability> }
        return try await transport.envelope(.post, path: "\(base)/devices/\(deviceId)/authorizations", body: JSONEncoder().encode(Request(workspaceId: workspaceId, capabilities: capabilities)), token: token, as: RegisteredLocalAuthorization.self)
    }
    func authorizations(workspaceId: Int64, token: String) async throws -> [RegisteredLocalAuthorization] {
        try await transport.envelope(.get, path: "\(base)/workspaces/\(workspaceId)/authorizations", token: token, as: [RegisteredLocalAuthorization].self)
    }
    func narrow(_ record: WorkspaceAuthorization, capabilities: Set<LocalCapability>, token: String) async throws -> RegisteredLocalAuthorization {
        try await transport.envelope(.post, path: "\(base)/workspaces/\(record.workspaceId)/authorizations/\(record.id)/narrow", body: JSONEncoder().encode(["capabilities": capabilities]), token: token, as: RegisteredLocalAuthorization.self)
    }
    func release(_ record: WorkspaceAuthorization, token: String) async throws -> RegisteredLocalAuthorization {
        try await transport.envelope(.post, path: "\(base)/workspaces/\(record.workspaceId)/authorizations/\(record.id)/release", token: token, as: RegisteredLocalAuthorization.self)
    }
}
